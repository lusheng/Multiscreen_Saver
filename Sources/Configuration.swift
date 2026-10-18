import AppKit
import ScreenSaver

final class SettingsStore {
    static func load() -> SaverSettings {
        let defaults = moduleDefaults()
        return SaverSettings.load(from: defaults?.data(forKey: "SettingsV1"),
                                  legacyFolders: defaults?.dictionary(forKey: "G1Folders") as? [String: Data] ?? [:])
    }
    static func save(_ value: SaverSettings) throws {
        let data = try value.encoded()
        guard let defaults = moduleDefaults() else { throw CocoaError(.fileWriteUnknown) }
        let previous = defaults.data(forKey: "SettingsV1")
        defaults.set(data, forKey: "SettingsV1")
        guard defaults.synchronize() else {
            defaults.set(previous, forKey: "SettingsV1")
            _ = defaults.synchronize()
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

final class ConfigurationController: NSObject, NSWindowDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 480),
                          styleMask: [.titled], backing: .buffered, defer: false)
    private var draft = SaverSettings()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var folderButtons: [NSButton] = []
    private let duration = NSTextField(string: "5")
    private let fade = NSTextField(string: "1.5")
    private let zoom = NSTextField(string: "1.20")
    private let random = NSButton(checkboxWithTitle: "随机播放（每轮不重复）", target: nil, action: nil)
    private let recursive = NSButton(checkboxWithTitle: "包含子文件夹", target: nil, action: nil)

    override init() {
        super.init()
        window.title = "Multiscreen Saver — 照片设置"
        window.isReleasedWhenClosed = false
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 570, height: 480))
        window.contentViewController = controller
        window.level = .floating
        window.center(); window.delegate = self
        guard let content = window.contentView else { return }
        let title = NSTextField(labelWithString: "为横屏和竖屏分别选择本地照片文件夹")
        title.frame = NSRect(x: 22, y: 435, width: 525, height: 24); content.addSubview(title)
        for index in 0..<2 {
            let button = NSButton(title: "", target: self, action: #selector(choose(_:)))
            button.tag = index
            button.frame = NSRect(x: 22, y: 390 - index * 45, width: 525, height: 34)
            content.addSubview(button); folderButtons.append(button)
        }
        let labels = ["相邻照片开始间隔（2–120 秒）", "过渡时长（0–min(5, 间隔/2) 秒）", "缩放上限（1.10–1.20）"]
        for (index, field) in [duration, fade, zoom].enumerated() {
            let y = 300 - index * 38
            let text = NSTextField(labelWithString: labels[index])
            text.frame = NSRect(x: 24, y: y, width: 340, height: 24);content.addSubview(text)
            field.frame = NSRect(x: 380, y: y, width: 160, height: 24);content.addSubview(field)
        }
        random.frame = NSRect(x: 24, y: 180, width: 500, height: 24);content.addSubview(random)
        recursive.frame = NSRect(x: 24, y: 145, width: 500, height: 24);content.addSubview(recursive)
        status.frame = NSRect(x: 24, y: 55, width: 520, height: 76);content.addSubview(status)
        for (index, title) in ["取消", "保存"].enumerated() {
            let button = NSButton(title: title, target: self, action: index == 0 ? #selector(cancel) : #selector(save))
            button.frame = NSRect(x: 350 + index * 100, y: 12, width: 90, height: 32)
            button.keyEquivalent = index == 0 ? "\u{1b}" : "\r"
            content.addSubview(button)
        }
        beginEditing()
    }
    // Cached native configuration windows must discard any cancelled draft on reopen.
    func beginEditing() {
        draft = SettingsStore.load()
        duration.stringValue = String(draft.duration);fade.stringValue = String(draft.fade)
        zoom.stringValue = String(draft.maximumZoom)
        random.state = draft.random ? .on : .off; recursive.state = draft.recursive ? .on : .off
        for (i, route) in ["H", "V"].enumerated() {
            folderButtons[i].title = "\(i == 0 ? "横屏" : "竖屏")：\(draft.folders[route] == nil ? "选择文件夹…" : "已保存，重新选择…")"
        }
        status.stringValue = "默认每 5 秒开始下一张，过渡 1.5 秒。关闭随机播放后按相对路径自然顺序循环。"
    }
    @objc private func choose(_ sender: NSButton) {
        let route = sender.tag == 0 ? "H" : "V"
        let panel = NSOpenPanel();panel.canChooseDirectories = true;panel.canChooseFiles = false
        panel.allowsMultipleSelection = false;panel.prompt = "选择照片文件夹"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                      FileManager.default.isReadableFile(atPath: url.path) else { throw CocoaError(.fileReadNoPermission) }
                let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
                self.draft.folders[route] = data
                sender.title = "\(sender.tag == 0 ? "横屏" : "竖屏")：\(url.lastPathComponent)"
                self.status.stringValue = "文件夹已暂存；点击保存生效，取消不会更改设置。"
                report("configuration route=\(route) selected readable=true scope=\(scoped)")
            } catch { self.status.stringValue = "无法访问该文件夹或保存授权，请重新选择。" }
        }
    }
    @objc private func save() {
        guard let d = Double(duration.stringValue), let f = Double(fade.stringValue), let z = Double(zoom.stringValue) else {
            status.stringValue = "请输入有效数字，小数使用点号。";return
        }
        draft.duration = d;draft.fade = f;draft.maximumZoom = z
        draft.random = random.state == .on;draft.recursive = recursive.state == .on
        if let message = draft.validationMessage { status.stringValue = message;return }
        guard draft.folders["H"] != nil, draft.folders["V"] != nil else { status.stringValue = "请选择横屏和竖屏文件夹。";return }
        do { try SettingsStore.save(draft); report("configuration saved version=1");finish(.OK) }
        catch { status.stringValue = "设置保存失败，请重试。" }
    }
    @objc private func cancel() { finish(.cancel) }
    private func finish(_ response: NSApplication.ModalResponse) {
        if let parent = window.sheetParent { parent.endSheet(window, returnCode: response) }
        window.orderOut(nil)
    }
}
