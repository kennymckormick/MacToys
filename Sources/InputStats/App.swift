import SwiftUI
import AppKit
import ApplicationServices
import Combine
import Darwin

@main
struct InputStatsApp {
    static func main() {
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "--quit-running" {
            let target = URL(fileURLWithPath: args[2]).resolvingSymlinksInPath()
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: "com.local.inputstats")
                where running.processIdentifier != ProcessInfo.processInfo.processIdentifier && running.bundleURL?.resolvingSymlinksInPath() == target {
                _ = running.terminate()
            }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var popoverStore: StatsStore?
    private var window: NSWindow?
    private var inputTestWindow: NSWindow?
    private let model = ToolsModel()
    private let colors = ColorPickerStore()
    private let scroll = ScrollReversalStore()
    private let awake = KeepAwakeStore()
    private var awakeStateToken: AnyCancellable?
    private var lockFD: Int32 = -1
    private var ownsLock = false
    private var reopenObserver: NSObjectProtocol?
    private var signalSources: [DispatchSourceSignal] = []
    private let isTest = ProcessInfo.processInfo.environment["INPUTSTATS_TEST_HOME"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: Database.directory, withIntermediateDirectories: true)
        lockFD = Darwin.open(Database.directory.appendingPathComponent("app.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.local.inputstats.show"), object: nil, deliverImmediately: true)
            NSApp.terminate(nil); return
        }
        ownsLock = true
        if !isTest {
            reopenObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.local.inputstats.show"), object: nil, queue: .main) { [weak self] _ in self?.showTools() }
        }
        // Never automatically request/reset TCC. Reuse the existing signed app identity.
        InputMonitor.shared.start()
        scroll.start()
        awake.start()
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                // NSTerminateLater must not block the main dispatch queue that delivers the save reply.
                RunLoop.main.perform { NSApp.terminate(nil) }
            }; source.resume(); signalSources.append(source)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "MacToys 工具箱")
            button.action = #selector(statusClicked); button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        awakeStateToken = awake.$enabled.removeDuplicates().sink { [weak self] enabled in
            guard let button = self?.statusItem.button else { return }
            button.image = NSImage(systemSymbolName: enabled ? "cup.and.saucer.fill" : "square.grid.2x2",
                                   accessibilityDescription: enabled ? "MacToys · 防止休眠已开启" : "MacToys 工具箱")
            button.toolTip = enabled ? "MacToys · 防止休眠已开启（右键可关闭）" : "MacToys · 输入统计、端口转发、屏幕取色、滚轮反转与防止休眠"
        }
        popover.behavior = .transient; popover.delegate = self
        installMenu()
        colors.startShortcut { [weak self] in self?.pickColor() }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--diagnostics") {
            let report: [String: Any] = ["accessibility": AXIsProcessTrusted(), "inputMonitoring": CGPreflightListenEventAccess(),
                "monitorRunning": MonitorStatus.shared.running, "database": Database.directory.path,
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "colorShortcut": colors.shortcut.label, "colorShortcutError": colors.shortcutError ?? "",
                "scrollReversalEnabled": scroll.enabled, "scrollReversalRunning": scroll.running,
                "scrollReverseVertical": scroll.reverseVertical, "scrollReverseHorizontal": scroll.reverseHorizontal,
                "scrollReversalError": scroll.issue ?? "",
                "awakeEnabled": awake.enabled, "awakeKeepDisplayAwake": awake.keepDisplayAwake,
                "awakeDurationMinutes": awake.duration.rawValue, "awakeEndsAt": awake.endsAt?.ISO8601Format() ?? "",
                "awakeError": awake.issue ?? ""]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
            }
            NSApp.terminate(nil)
        } else if !args.contains("--background") {
            showTools()
            if isTest && args.contains("--input-fixture") { openInputTest() }
        }
    }
    /// Isolated native controls for end-to-end verification with real key events.
    private func openInputTest() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 350), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MacToys · 输入验证（临时数据）"
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 350))
        let arm = NSButton(title: "启用 30 秒验证窗口", target: self, action: #selector(armInputTest))
        arm.frame = NSRect(x: 360, y: 300, width: 215, height: 32); container.addSubview(arm)
        let label = NSTextField(labelWithString: "普通输入（临时数据）")
        label.frame = NSRect(x: 24, y: 305, width: 330, height: 25); container.addSubview(label)
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 120, width: 550, height: 175))
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds); text.isRichText = false
        text.font = .systemFont(ofSize: 18); text.setAccessibilityLabel("验证文本")
        scroll.documentView = text; container.addSubview(scroll)
        let secureLabel = NSTextField(labelWithString: "密码测试（应当完全跳过）")
        secureLabel.frame = NSRect(x: 24, y: 76, width: 550, height: 25); container.addSubview(secureLabel)
        let password = NSSecureTextField(frame: NSRect(x: 24, y: 32, width: 550, height: 32))
        password.setAccessibilityLabel("验证密码"); container.addSubview(password)
        window.contentView = container; window.isReleasedWhenClosed = false; window.center()
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(text); inputTestWindow = window
    }
    @objc private func armInputTest() { InputMonitor.shared.armInputTest() }
    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 MacToys", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 MacToys", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 MacToys", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); menu.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        let toolsItem = NSMenuItem(title: "工具", action: nil, keyEquivalent: ""); menu.addItem(toolsItem)
        let toolsMenu = NSMenu(title: "工具"); toolsItem.submenu = toolsMenu
        toolsMenu.addItem(withTitle: "快速统计", action: #selector(togglePopover), keyEquivalent: "").target = self
        toolsMenu.addItem(withTitle: "颜色面板", action: #selector(openColors), keyEquivalent: "").target = self
        let pickItem = toolsMenu.addItem(withTitle: "拾取屏幕颜色…", action: #selector(pickColor), keyEquivalent: "p")
        pickItem.keyEquivalentModifierMask = [.command, .shift]; pickItem.target = self
        toolsMenu.addItem(withTitle: "滚轮反转…", action: #selector(openScroll), keyEquivalent: "").target = self
        toolsMenu.addItem(withTitle: "防止休眠…", action: #selector(openAwake), keyEquivalent: "").target = self
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: ""); menu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口"); windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }
    @objc private func statusClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) { showMenu() }
        else { togglePopover() }
    }
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        let store = StatsStore(); popoverStore = store
        let visibleFrame = (button.window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 700)
        let size = StatsPopoverView.contentSize(in: visibleFrame)
        let controller = NSHostingController(rootView:
            StatsPopoverView(store: store, settings: AppSettings.shared, size: size,
                onOpenSettings: { [weak self] in self?.openSettings() }, onOpenTools: { [weak self] in self?.showTools() },
                onHeightChange: { [weak self, weak store] height in
                    DispatchQueue.main.async {
                        guard let self, let store, self.popoverStore === store else { return }
                        let fitted = NSSize(width: size.width, height: height)
                        guard self.popover.contentSize != fitted else { return }
                        self.popover.contentViewController?.preferredContentSize = fitted
                        self.popover.contentSize = fitted
                    }
                }))
        let initialSize = NSSize(width: size.width, height: min(size.height, StatsPopoverView.initialHeight))
        controller.sizingOptions = []
        controller.preferredContentSize = initialSize
        popover.contentViewController = controller
        popover.contentSize = initialSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func popoverDidClose(_ notification: Notification) {
        popoverStore?.deactivate(); popoverStore = nil; popover.contentViewController = nil
    }
    private func showMenu() {
        awake.expireIfNeeded()
        let menu = NSMenu(); menu.delegate = self
        menu.addItem(withTitle: "打开 MacToys", action: #selector(showTools), keyEquivalent: "").target = self
        menu.addItem(withTitle: "端口转发", action: #selector(openPorts), keyEquivalent: "").target = self
        menu.addItem(withTitle: "拾取屏幕颜色…", action: #selector(pickColor), keyEquivalent: "").target = self
        menu.addItem(withTitle: "颜色面板", action: #selector(openColors), keyEquivalent: "").target = self
        let scrollItem = menu.addItem(withTitle: "反转鼠标滚轮", action: #selector(toggleScroll), keyEquivalent: "")
        scrollItem.target = self; scrollItem.state = scroll.enabled ? .on : .off
        menu.addItem(withTitle: "滚轮设置…", action: #selector(openScroll), keyEquivalent: "").target = self
        let awakeItem = menu.addItem(withTitle: "防止休眠", action: #selector(toggleAwake), keyEquivalent: "")
        awakeItem.target = self; awakeItem.state = awake.enabled ? .on : .off
        menu.addItem(withTitle: "防休眠设置…", action: #selector(openAwake), keyEquivalent: "").target = self
        menu.addItem(withTitle: AppSettings.shared.paused ? "继续输入统计" : "暂停输入统计", action: #selector(togglePaused), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 MacToys", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu; statusItem.button?.performClick(nil)
    }
    func menuDidClose(_ menu: NSMenu) { statusItem.menu = nil }
    @objc private func togglePaused() { AppSettings.shared.paused.toggle() }
    @objc private func openSettings() { model.selection = .settings; showTools() }
    @objc private func openPorts() { model.selection = .ports; showTools() }
    @objc private func openColors() { model.selection = .colors; showTools() }
    @objc private func openScroll() { model.selection = .scroll; showTools() }
    @objc private func openAwake() { model.selection = .awake; showTools() }
    @objc private func toggleAwake() {
        awake.setEnabled(!awake.enabled)
        if awake.issue != nil { openAwake() }
    }
    @objc private func toggleScroll() {
        scroll.enabled.toggle()
        if scroll.enabled && scroll.issue != nil { openScroll() }
    }
    @objc private func pickColor() {
        guard !colors.isSampling else { return }
        popover.performClose(nil)
        let previousApp = NSWorkspace.shared.frontmostApplication
        let restoreWindow = window?.isVisible == true && window?.isMiniaturized == false
        let restoreFocus = NSApp.isActive
        if restoreWindow { window?.orderOut(nil); model.visible = false }
        NSColorPanel.shared.orderOut(nil)
        colors.sample { [weak self] picked in
            guard let self else { return }
            if self.colors.errorMessage != nil || (picked && self.colors.showAfterPicking) { self.openColors() }
            else {
                if restoreWindow {
                    self.model.visible = true
                    self.window?.orderFront(nil)
                    if restoreFocus { self.window?.makeKeyAndOrderFront(nil) }
                }
                if !restoreFocus { previousApp?.activate(options: []) }
            }
        }
    }
    @objc private func showTools() {
        popover.performClose(nil)
        model.visible = true
        if window == nil {
            let value = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            value.title = "MacToys"
            value.contentViewController = NSHostingController(rootView: ToolsView(model: model, settings: AppSettings.shared,
                colors: colors, scroll: scroll, awake: awake, onPickColor: { [weak self] in self?.pickColor() }))
            value.minSize = NSSize(width: 920, height: 690)
            value.isReleasedWhenClosed = false; value.delegate = self
            value.setFrameAutosaveName(isTest ? "MacToysTestWindow" : "MacToysMainWindow")
            value.center(); window = value
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.deminiaturize(nil); window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { model.visible = false; NSApp.setActivationPolicy(.accessory) }
    func windowDidMiniaturize(_ notification: Notification) { model.visible = false }
    func windowDidDeminiaturize(_ notification: Notification) { model.visible = true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if isTest, let inputTestWindow { inputTestWindow.makeKeyAndOrderFront(nil) }
        else { showTools() }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ownsLock else { return .terminateNow }
        InputMonitor.shared.prepareForTermination { error in
            if let error {
                sender.reply(toApplicationShouldTerminate: false)
                let alert = NSAlert(); alert.messageText = "统计尚未保存，已取消退出"
                alert.informativeText = error.localizedDescription; alert.runModal()
            } else { sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        if ownsLock {
            scroll.stop()
            awake.stop()
            if !isTest || ProcessInfo.processInfo.environment["INPUTSTATS_ENABLE_TEST_MONITOR"] == "1" { InputMonitor.shared.stop() }
            flock(lockFD, LOCK_UN); Darwin.close(lockFD)
        }
    }
}
