import AppKit
import ScreenSaver
import QuartzCore

@objc(MultiscreenSaverView)
final class DiagnosticSaverView: ScreenSaverView {
    private struct Card {
        let photo: DecodedPhoto
        let path: KenBurnsPath
        let start: CFTimeInterval
    }
    private let instance = String(UUID().uuidString.prefix(8))
    private var configuration: ConfigurationController?
    private var requested = false
    private var classified = false
    private var staticPreview = true
    private var signature: String?
    private var generation = 0
    private var session: PhotoSession?
    private var settings = SaverSettings()
    private var rng = SeededGenerator(seed: UInt64.random(in: 0...UInt64.max))
    private var current: Card?
    private var incoming: Card?
    private var prepared: DecodedPhoto?
    private var loading = false
    private var failed = false
    private var status = "请选择照片文件夹"
    private var observers: [NSObjectProtocol] = []
    private var frames = 0
    private static var engineRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.ScreenSaver.Engine" && !$0.isTerminated }
    }
    override init?(frame: NSRect, isPreview: Bool) { super.init(frame: frame, isPreview: isPreview);setup() }
    required init?(coder: NSCoder) { super.init(coder: coder);setup() }
    private func setup() {
        wantsLayer = true;layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = true;animationTimeInterval = 1 / 60
        for name in [NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, note.object as? NSWindow === self.window else { return };self.reconcile()
            })
        }
        report("id=\(instance) init preview=\(isPreview) build=\(Bundle(for: Self.self).object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown")")
    }
    override var isOpaque: Bool { true }
    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        if configuration == nil { configuration = ConfigurationController() }
        if configuration?.window.isVisible == false { configuration?.beginEditing() }
        if let panel = configuration?.window {
            DispatchQueue.main.async { if !panel.isVisible { panel.makeKeyAndOrderFront(nil) } }
        }
        return configuration?.window
    }
    override func startAnimation() {
        if !classified {
            let systemPresentation = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow"
            staticPreview = isPreview || !(Self.engineRunning || systemPresentation)
            classified = true
        }
        requested = true;reconcile()
    }
    override func stopAnimation() { requested = false;suspend();reportState("stop") }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow();reconcile() }
    override func setFrameSize(_ size: NSSize) { super.setFrameSize(size);reconcile() }
    private func suspend() {
        generation += 1;session?.cancel();session = nil;signature = nil
        current = nil;incoming = nil;prepared = nil;loading = false;failed = false;frames = 0
        super.stopAnimation()
        needsDisplay = true
    }
    private func reconcile() {
        guard requested, let screen = window?.screen, bounds.width > 0, bounds.height > 0 else {
            if signature != nil || isAnimating { suspend();reportState("inactive") };return
        }
        let route = staticPreview ? "H" : (screen.frame.width >= screen.frame.height ? "H" : "V")
        let loaded = SettingsStore.load()
        let key = "\(route)-\(bounds.size)-\(screen.backingScaleFactor)"
        guard signature != key || settings != loaded else { return }
        suspend();signature = key;settings = loaded
        status = "正在读取照片…"
        guard let bookmark = settings.folders[route] else { status = "请在选项中选择\(route == "H" ? "横屏" : "竖屏")照片文件夹";needsDisplay = true;return }
        session = PhotoSession(settings: settings, bookmark: bookmark, viewport: bounds.size, scale: screen.backingScaleFactor, seed: rng.next())
        if !staticPreview { super.startAnimation() }
        reportState("activate route=\(route)")
        requestNext()
    }
    private func card(_ photo: DecodedPhoto, now: CFTimeInterval) -> Card {
        Card(photo: photo, path: KenBurnsPath(image: CGSize(width: photo.image.width, height: photo.image.height), viewport: bounds.size,
                                            backingScale: window?.screen?.backingScaleFactor ?? 1, maximumZoom: settings.maximumZoom, generator: &rng), start: now)
    }
    private func requestNext() {
        guard !loading, !failed, prepared == nil, let session else { return }
        loading = true;let epoch = generation
        session.requestNext { [weak self] result in
            guard let self, self.generation == epoch, self.requested else { return }
            self.loading = false
            switch result {
            case .success(let photo):
                if self.current == nil {
                    self.current = self.card(photo, now: CACurrentMediaTime());self.status = ""
                    if !self.staticPreview { self.requestNext() }
                } else { self.prepared = photo }
            case .failure:
                self.failed = true
                self.status = "未找到可读照片；请检查文件夹或在选项中重新选择。"
                if self.current == nil { self.stopEmptyTimer() }
            }
            self.needsDisplay = true;self.layer?.setNeedsDisplay();self.displayIfNeeded()
        }
    }
    // Stop empty/error sessions without invalidating the status message or issuing retries every frame.
    private func stopEmptyTimer() { super.stopAnimation() }
    override func animateOneFrame() {
        if frames % 60 == 0 { reconcile() }
        guard requested, !staticPreview, window != nil, bounds.width > 0, bounds.height > 0 else { return }
        let now = CACurrentMediaTime()
        let timing = PlaybackTiming.evaluate(now: now, currentStart: current?.start, incomingStart: incoming?.start,
                                             ready: prepared != nil, duration: settings.duration, fade: settings.fade)
        if timing.finishIncoming, let next = incoming { current = next;incoming = nil }
        if timing.startNext, let photo = prepared {
            prepared = nil
            let next = card(photo, now: now)
            if settings.fade == 0 { current = next } else { incoming = next }
            requestNext()
        }
        frames += 1
        needsDisplay = true;layer?.setNeedsDisplay();displayIfNeeded()
        if frames % 600 == 0 { reportState("frames") }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let now = CACurrentMediaTime()
        func frame(_ value: Card) -> PhotoFrame {
            let progress = staticPreview ? 0 : (now - value.start) / (settings.duration + settings.fade)
            return PhotoFrame(image: value.photo.image, rect: value.path.rect(progress: progress))
        }
        let fraction = incoming.map { (now - $0.start) / max(0.001, settings.fade) } ?? 0
        PhotoRenderer.draw(in: ctx, bounds: bounds, lower: current.map(frame), upper: incoming.map(frame), fraction: fraction)
        if current == nil {
            let paragraph = NSMutableParagraphStyle();paragraph.alignment = .center
            let text = NSAttributedString(string: status, attributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.lightGray, .paragraphStyle: paragraph])
            text.draw(in: CGRect(x: 20, y: bounds.midY - 30, width: max(0, bounds.width - 40), height: 80))
        }
    }
    private func reportState(_ event: String) {
        report("id=\(instance) \(event) staticPreview=\(staticPreview) attached=\(window != nil) timer=\(isAnimating) loading=\(loading) resident=\((current == nil ? 0 : 1) + (incoming == nil ? 0 : 1) + (prepared == nil ? 0 : 1)) cachedBytes=\(ImageBudget.shared.current) frames=\(frames)")
    }
    deinit { session?.cancel();for observer in observers { NotificationCenter.default.removeObserver(observer) };report("id=\(instance) deinit") }
}
