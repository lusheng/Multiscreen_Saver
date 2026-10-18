import AppKit
import ScreenSaver

final class ConfigurationController: NSObject, NSWindowDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 270),
                          styleMask: [.titled], backing: .buffered, defer: false)
    private var bookmarks: [String: Data]
    private let status = NSTextField(wrappingLabelWithString: "仅选择本项目生成的 H / V 合成图库。")
    private var buttons: [NSButton] = []

    override init() {
        bookmarks = moduleDefaults()?.dictionary(forKey: "G1Folders") as? [String: Data] ?? [:]
        super.init()
        window.title = "Multiscreen Saver — G1 诊断"
        window.isReleasedWhenClosed = false
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 270))
        window.contentViewController = controller
        window.level = .floating
        window.center()
        window.delegate = self
        guard let content = window.contentView else { return }
        let title = NSTextField(labelWithString: "G1 原生宿主与目录权限验证（非完整播放器）")
        title.frame = NSRect(x: 22, y: 220, width: 500, height: 24)
        content.addSubview(title)
        for (index, route) in ["H", "V"].enumerated() {
            let button = NSButton(title: "\(route == "H" ? "横屏 H" : "竖屏 V")：\(bookmarks[route] == nil ? "选择合成图库…" : "已保存，可重新选择…")", target: self, action: #selector(choose(_:)))
            button.tag = index
            button.frame = NSRect(x: 22, y: 170 - index * 45, width: 496, height: 34)
            content.addSubview(button); buttons.append(button)
        }
        status.frame = NSRect(x: 24, y: 60, width: 490, height: 54)
        content.addSubview(status)
        for (index, title) in ["取消", "保存"].enumerated() {
            let button = NSButton(title: title, target: self, action: index == 0 ? #selector(cancel) : #selector(save))
            button.frame = NSRect(x: 330 + index * 90, y: 15, width: 85, height: 32)
            content.addSubview(button)
        }
        report("configuration opened pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    func windowDidBecomeKey(_ notification: Notification) { report("configuration becameKey") }
    func windowWillClose(_ notification: Notification) { report("configuration closing") }

    @objc private func choose(_ sender: NSButton) {
        let route = sender.tag == 0 ? "H" : "V"
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择 \(route) 合成图库"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                // Read a known synthetic file, not an arbitrary user's photo inventory.
                let marker = url.appendingPathComponent("\(route)-marker.png")
                let size = try marker.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0 else { throw CocoaError(.fileReadCorruptFile) }
                let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
                self.bookmarks[route] = data
                sender.title = "\(route)：已选择合成图库"
                self.status.stringValue = "\(route) 文件可访问，书签已暂存；点击保存生效。"
                report("configuration route=\(route) selected readable=true scope=\(scoped)")
            } catch {
                self.status.stringValue = "无法读取 \(route)-marker.png 或创建书签，请重新选择合成目录。"
                report("configuration route=\(route) selectionFailed code=\((error as NSError).code)")
            }
        }
    }
    @objc private func save() {
        guard bookmarks["H"] != nil, bookmarks["V"] != nil, let defaults = moduleDefaults() else {
            status.stringValue = "请先选择横屏和竖屏两套合成图库。"; return
        }
        defaults.set(bookmarks, forKey: "G1Folders")
        guard defaults.synchronize() else { status.stringValue = "设置同步失败，请重试。"; return }
        report("configuration saved H=true V=true")
        finish(.OK)
    }
    @objc private func cancel() { report("configuration cancelled"); finish(.cancel) }
    private func finish(_ response: NSApplication.ModalResponse) {
        if let parent = window.sheetParent { parent.endSheet(window, returnCode: response) }
        window.orderOut(nil)
    }
}
