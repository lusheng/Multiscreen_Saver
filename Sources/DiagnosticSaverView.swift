import AppKit
import ScreenSaver
import QuartzCore
import ImageIO

@objc(MultiscreenSaverView)
final class DiagnosticSaverView: ScreenSaverView {
    private let instance = String(UUID().uuidString.prefix(8))
    private var diagnosticImage: CGImage?
    private let movingMarker = CALayer()
    private let label = CATextLayer()
    private let worker = DispatchQueue(label: "com.lusheng.MultiscreenSaver.g1.decode", qos: .userInitiated)
    private var ticket: WorkTicket?
    private var generation = 0
    private var requested = false
    private var staticPreview = true
    private var classified = false
    private var markerEpoch: CFTimeInterval?
    private var diagnosticFrames = 0
    private var diagnosticDraws = 0
    private static var engineRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.ScreenSaver.Engine" && !$0.isTerminated
        }
    }
    private var signature: String?
    private var configuration: ConfigurationController?
    private var observers: [NSObjectProtocol] = []

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    private func setup() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.darkGray.cgColor
        layer?.masksToBounds = true
        movingMarker.backgroundColor = NSColor.white.cgColor
        layer?.addSublayer(movingMarker)
        label.fontSize = 26; label.alignmentMode = .center
        label.foregroundColor = NSColor.white.cgColor
        label.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        label.isWrapped = true
        layer?.addSublayer(label)
        animationTimeInterval = 1.0 / 60.0 // Native frame callbacks drive model-layer diagnostics.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, note.object as? NSWindow === self.window else { return }; self.reconcile()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification, object: nil, queue: .main) { [weak self] _ in self?.reconcile() })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, note.object as? NSWindow === self.window else { return }
            self.reportState("occlusion")
        })
        report("id=\(instance) init pid=\(ProcessInfo.processInfo.processIdentifier) preview=\(isPreview) build=\(Bundle(for: Self.self).object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown")")
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        diagnosticDraws += 1
        if diagnosticDraws == 1 || diagnosticDraws % 300 == 0 {
            let clip = context.boundingBoxOfClipPath
            report("id=\(instance) draws=\(diagnosticDraws) dirty=\(Int(dirtyRect.width))x\(Int(dirtyRect.height)) clip=\(Int(clip.width))x\(Int(clip.height))")
        }
        context.saveGState()
        context.clip(to: bounds)
        context.setFillColor(NSColor.darkGray.cgColor)
        context.fill(bounds)
        if let image = diagnosticImage {
            let scale = max(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
            context.draw(image, in: rect)
        }
        context.restoreGState()
    }
    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        if configuration == nil { configuration = ConfigurationController() }
        if let panel = configuration?.window {
            DispatchQueue.main.async {
                report("configuration presentation visible=\(panel.isVisible) sheet=\(panel.sheetParent != nil)")
                if !panel.isVisible { panel.makeKeyAndOrderFront(nil) }
                report("configuration afterOrder visible=\(panel.isVisible)")
            }
        }
        return configuration?.window
    }
    override func startAnimation() {
        if !classified {
            // G1 candidate: settings fullscreen rendering starts after loginwindow
            // becomes frontmost. Existing thumbnail instances retain their identity.
            let systemPresentation = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow"
            staticPreview = isPreview || !(Self.engineRunning || systemPresentation)
            classified = true
        }
        requested = true; reportState("start")
        reconcile()
    }
    override func stopAnimation() {
        requested = false; suspend(); reportState("stop")
        super.stopAnimation()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); reportState("window"); reconcile() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); reconcile() }
    override func animateOneFrame() {
        // Screen/size/backing changes already reconcile via lifecycle callbacks.
        // Retain a bounded fallback check without formatting signatures per frame.
        if diagnosticFrames % 60 == 0 { reconcile() }
        guard window != nil, bounds.width > 0, bounds.height > 0,
              let epoch = markerEpoch, !staticPreview, requested else { return }
        let phase = (CACurrentMediaTime() - epoch).truncatingRemainder(dividingBy: 6) / 3
        let progress = phase <= 1 ? phase : 2 - phase
        CATransaction.begin(); CATransaction.setDisableActions(true)
        movingMarker.transform = CATransform3DMakeTranslation(max(0, bounds.width * 0.8 - 50) * progress, 0, 0)
        movingMarker.opacity = Float(1 - 0.8 * progress)
        CATransaction.commit()
        needsDisplay = true
        layer?.setNeedsDisplay()
        displayIfNeeded()
        diagnosticFrames += 1
        if diagnosticFrames % 300 == 0 {
            report("id=\(instance) frameCallbacks=\(diagnosticFrames) markerProgress=\(progress)")
        }
    }

    private func reportState(_ event: String) {
        let screen = window?.screen
        let engineRunning = Self.engineRunning
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let frontKind = front == "com.apple.systempreferences" ? "settings" : (front == "com.apple.ScreenSaver.Engine" ? "engine" : (front == "com.apple.loginwindow" ? "loginwindow" : "other"))
        report("id=\(instance) presentationFacts event=\(event) systemOptions=\(NSApp.currentSystemPresentationOptions.rawValue) appOptions=\(NSApp.presentationOptions.rawValue) front=\(frontKind)")
        report("id=\(instance) engineFacts event=\(event) running=\(engineRunning) staticPreview=\(staticPreview)")
        if let window {
            report("id=\(instance) windowFacts event=\(event) visible=\(window.isVisible) occluded=\(!window.occlusionState.contains(.visible)) level=\(window.level.rawValue) style=\(window.styleMask.rawValue) activeSpace=\(window.isOnActiveSpace) windowSize=\(Int(window.frame.width))x\(Int(window.frame.height)) visibleRect=\(Int(visibleRect.width))x\(Int(visibleRect.height))")
        }
        report("id=\(instance) \(event) preview=\(isPreview) attached=\(window != nil) view=\(Int(bounds.width))x\(Int(bounds.height)) screen=\(Int(screen?.frame.width ?? 0))x\(Int(screen?.frame.height ?? 0)) scale=\(screen?.backingScaleFactor ?? 0) animations=\(movingMarker.animationKeys()?.count ?? 0) timer=\(isAnimating) markerActive=\(markerEpoch != nil) frameCallbacks=\(diagnosticFrames)")
    }
    private func suspend() {
        generation += 1; ticket?.cancel(); ticket = nil; signature = nil
        movingMarker.removeAllAnimations(); markerEpoch = nil; diagnosticFrames = 0; diagnosticImage = nil
        super.stopAnimation()
    }
    private func reconcile() {
        guard requested, window != nil, let screen = window?.screen, bounds.width > 0, bounds.height > 0 else {
            if signature != nil || isAnimating { suspend(); reportState("inactive") }
            return
        }
        let route = staticPreview ? "H" : (screen.frame.width >= screen.frame.height ? "H" : "V")
        let next = staticPreview ? "preview-\(bounds.size)" : "\(route)-\(bounds.size)-\(screen.frame)-\(screen.backingScaleFactor)"
        guard signature != next else { return }
        suspend(); signature = next
        // Keep the native timer paired with the framework's stopAnimation contract.
        if !staticPreview { super.startAnimation() }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        movingMarker.frame = CGRect(x: bounds.width * 0.1, y: bounds.height * 0.18, width: 50, height: 50)
        label.contentsScale = screen.backingScaleFactor
        label.frame = CGRect(x: 0, y: bounds.height * 0.43, width: bounds.width, height: min(150, bounds.height * 0.5))
        label.string = "G1 \(route) · \(staticPreview ? "PREVIEW" : "HOST")\n等待合成图库 · \(instance)"
        CATransaction.commit()
        reportState("activate route=\(route)")
        guard let data = (moduleDefaults()?.dictionary(forKey: "G1Folders") as? [String: Data])?[route] else {
            label.string = "G1 \(route)\n请在选项中选择合成图库"
            if staticPreview { finishPreview() }; return
        }
        let work = WorkTicket(); ticket = work
        let epoch = generation, id = instance
        // A bounded thumbnail suffices for the G1 marker; no catalog or player here.
        worker.async { [weak self] in
            guard !work.isCancelled else { return }
            Resources.shared.change(tasks: 1, id: id)
            defer { Resources.shared.change(tasks: -1, id: id) }
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                guard !work.isCancelled else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                if scoped { Resources.shared.change(scopes: 1, id: id) }
                defer { if scoped { url.stopAccessingSecurityScopedResource(); Resources.shared.change(scopes: -1, id: id) } }
                guard !stale else { throw CocoaError(.fileReadUnknown) }
                let marker = url.appendingPathComponent("\(route)-marker.png")
                guard let source = CGImageSourceCreateWithURL(marker as CFURL, nil), !work.isCancelled,
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
                report("id=\(id) decoded route=\(route) scope=\(scoped) stale=\(stale) pixels=\(image.width)x\(image.height)")
                guard !work.isCancelled else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !work.isCancelled, self.generation == epoch, self.requested else { return }
                    self.diagnosticImage = image
                    self.needsDisplay = true
                    self.label.string = "G1 \(route) · \(self.staticPreview ? "PREVIEW" : "HOST")\n\(id) · \(self.staticPreview ? "静态预览" : "白块应往返移动并明暗变化")"
                    // Preview is static and never schedules continuous diagnostic work.
                    if self.staticPreview { self.finishPreview() } else { self.startMarker() }
                    self.reportState("presented route=\(route)")
                }
            } catch {
                report("id=\(id) readFailed route=\(route) code=\((error as NSError).code)")
                DispatchQueue.main.async { [weak self] in
                    guard let self, !work.isCancelled, self.generation == epoch else { return }
                    self.label.string = "G1 \(route) 读取失败\n请重新选择合成图库"
                    if self.staticPreview { self.finishPreview() }
                }
            }
        }
    }
    private func finishPreview() { super.stopAnimation() }
    private func startMarker() {
        // The settings fullscreen path may snapshot model layers rather than
        // present server-side CA animations. Native frames update those values.
        markerEpoch = CACurrentMediaTime()
        diagnosticFrames = 0
    }
    deinit {
        ticket?.cancel(); movingMarker.removeAllAnimations()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        report("id=\(instance) deinit")
    }
}
