import AppKit
import InputStatsCore

extension ScreenColor {
    init?(nativeColor: NSColor) {
        guard let color = nativeColor.usingColorSpace(.sRGB) else { return nil }
        let components = [color.redComponent, color.greenComponent, color.blueComponent]
        guard components.allSatisfy(\.isFinite) else { return nil }
        let bytes = components.map { UInt8((min(1, max(0, $0)) * 255).rounded()) }
        self.init(red: bytes[0], green: bytes[1], blue: bytes[2])
    }
    var nativeColor: NSColor { NSColor(srgbRed: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: 1) }
}

final class ColorPickerStore: ObservableObject {
    @Published private(set) var selected: ScreenColor
    @Published private(set) var history: [ScreenColor]
    @Published private(set) var favorites: [ScreenColor]
    @Published var format: ColorTextFormat { didSet { defaults.set(format.rawValue, forKey: "color.format") } }
    @Published var autoCopy: Bool { didSet { defaults.set(autoCopy, forKey: "color.autoCopy") } }
    @Published var showAfterPicking: Bool { didSet { defaults.set(showAfterPicking, forKey: "color.showAfterPicking") } }
    @Published var shortcutEnabled: Bool { didSet {
        defaults.set(shortcutEnabled, forKey: "color.shortcutEnabled")
        cancelRecording(); updateRegistration()
    } }
    @Published private(set) var shortcut: ColorShortcut
    @Published private(set) var isSampling = false
    @Published private(set) var isRecording = false
    @Published private(set) var shortcutError: String?
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let runSampler: (@escaping (NSColor?) -> Void) -> Void
    private let registration = ColorShortcutRegistration()
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(defaults: UserDefaults? = nil, pasteboard: NSPasteboard = .general,
         sampler: @escaping (@escaping (NSColor?) -> Void) -> Void = { handler in NSColorSampler().show(selectionHandler: handler) }) {
        let defaults = defaults ?? (ProcessInfo.processInfo.environment["INPUTSTATS_TEST_HOME"] == nil ? .standard : UserDefaults(suiteName: "com.local.inputstats.tests")!)
        self.defaults = defaults
        self.pasteboard = pasteboard; self.runSampler = sampler
        history = ColorHistory(hexValues: defaults.stringArray(forKey: "color.history") ?? []).colors
        var seen = Set<ScreenColor>()
        favorites = Array((defaults.stringArray(forKey: "color.favorites") ?? []).compactMap(ScreenColor.init(hex:))
            .filter { seen.insert($0).inserted }.prefix(64))
        selected = defaults.string(forKey: "color.selected").flatMap(ScreenColor.init(hex:)) ?? ScreenColor(red: 59, green: 130, blue: 246)
        format = defaults.string(forKey: "color.format").flatMap(ColorTextFormat.init(rawValue:)) ?? .hex
        autoCopy = defaults.object(forKey: "color.autoCopy") as? Bool ?? true
        showAfterPicking = defaults.object(forKey: "color.showAfterPicking") as? Bool ?? true
        shortcutEnabled = defaults.object(forKey: "color.shortcutEnabled") as? Bool ?? true
        let saved = defaults.data(forKey: "color.shortcut").flatMap { try? JSONDecoder().decode(ColorShortcut.self, from: $0) }
        shortcut = saved?.isValid == true ? saved! : .standard
    }
    func startShortcut(action: @escaping () -> Void) {
        registration.action = action
        updateRegistration()
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelRecording()
        }
    }
    private func updateRegistration() {
        guard registration.action != nil else { return }
        guard shortcutEnabled, !isRecording else { registration.unregister(); shortcutError = nil; return }
        let status = registration.register(shortcut)
        shortcutError = status == noErr ? nil : L("快捷键未能注册（%@），可能已被占用。请更换组合键；仍可使用取色按钮。", String(describing: status))
    }
    func beginRecording() {
        guard !isRecording else { cancelRecording(); return }
        isRecording = true; shortcutError = nil; registration.unregister()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.cancelRecording(); return nil }
            guard let candidate = ColorShortcut(event: event) else {
                self.shortcutError = L("请使用字母或数字，加上 ⌘、⌥、⌃ 中的至少一个修饰键。"); return nil
            }
            let status = self.registration.register(candidate)
            self.endRecording()
            if status == noErr {
                self.shortcut = candidate; self.shortcutEnabled = true
                self.defaults.set(try? JSONEncoder().encode(candidate), forKey: "color.shortcut")
                self.shortcutError = nil
            } else {
                self.updateRegistration()
                self.shortcutError = L("这个快捷键未能注册（%@），已保留原设置。请换一个组合键。", String(describing: status))
            }
            return nil
        }
    }
    private func endRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil; isRecording = false
    }
    func cancelRecording() {
        guard isRecording else { return }
        endRecording(); updateRegistration()
    }
    func sample(completion: @escaping (Bool) -> Void) {
        guard !isSampling else { return }
        cancelRecording(); isSampling = true; message = nil; errorMessage = nil
        // Give the menu and the obscuring window a frame to disappear before sampling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { completion(false); return }
            self.runSampler { [weak self] color in
                guard let self else { completion(false); return }
                self.isSampling = false
                guard let color else { completion(false); return }
                guard let value = ScreenColor(nativeColor: color) else {
                    self.errorMessage = L("这个颜色无法转换为 sRGB，请重新取色。"); completion(false); return
                }
                self.select(value); self.remember(value)
                if self.autoCopy { self.copy(self.format) }
                else { self.message = L("已拾取 %@", String(describing: value.hex)) }
                completion(true)
            }
        }
    }
    func select(_ color: ScreenColor) {
        selected = color; defaults.set(color.hex, forKey: "color.selected")
        message = nil; errorMessage = nil
    }
    func preview(_ color: NSColor) {
        if let value = ScreenColor(nativeColor: color) { select(value) }
    }
    func apply(hex: String) {
        guard let color = ScreenColor(hex: hex) else { errorMessage = L("请输入 3 位或 6 位 HEX，例如 #F80 或 #FF8800。"); message = nil; return }
        select(color); remember(color)
    }
    func copy(_ format: ColorTextFormat) {
        let text = selected.formatted(format)
        pasteboard.clearContents()
        if pasteboard.setString(text, forType: .string) {
            remember(selected); message = L("已复制 %@", String(describing: text)); errorMessage = nil
        } else { errorMessage = L("无法写入剪贴板，请重试。") }
    }
    private func remember(_ color: ScreenColor) {
        var recent = ColorHistory(hexValues: history.map(\.hex)); recent.record(color)
        history = recent.colors; defaults.set(history.map(\.hex), forKey: "color.history")
    }
    func toggleFavorite(_ color: ScreenColor) {
        if favorites.contains(color) { favorites.removeAll { $0 == color } }
        else {
            guard favorites.count < 64 else { errorMessage = L("收藏已满（64 个），请先移除不需要的颜色。"); return }
            favorites.append(color)
        }
        defaults.set(favorites.map(\.hex), forKey: "color.favorites")
    }
    func removeFromHistory(_ color: ScreenColor) {
        history.removeAll { $0 == color }; defaults.set(history.map(\.hex), forKey: "color.history")
    }
    func clearHistory() { history = []; defaults.removeObject(forKey: "color.history") }
    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}
