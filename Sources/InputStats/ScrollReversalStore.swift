import AppKit
import ApplicationServices

/// Owned by the application, so closing a tool page never stops wheel reversal.
/// Configuration and event callbacks run on the main run loop; no polling is used.
final class ScrollReversalStore: ObservableObject {
    @Published var enabled: Bool { didSet {
        guard enabled != oldValue else { return }
        defaults.set(enabled, forKey: "scroll.enabled"); refresh()
    } }
    @Published var reverseVertical: Bool { didSet {
        guard reverseVertical != oldValue else { return }
        defaults.set(reverseVertical, forKey: "scroll.vertical"); refresh()
    } }
    @Published var reverseHorizontal: Bool { didSet {
        guard reverseHorizontal != oldValue else { return }
        defaults.set(reverseHorizontal, forKey: "scroll.horizontal"); refresh()
    } }
    @Published private(set) var running = false
    @Published private(set) var issue: String?
    private let defaults: UserDefaults
    private let allowEventTap: Bool
    private let accessAvailable: () -> Bool
    private let conflictingApp: () -> String?
    private var started = false
    private var sleeping = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var applicationsObservation: NSKeyValueObservation?
    private var activeToken: NSObjectProtocol?

    var options: ScrollReversalOptions {
        ScrollReversalOptions(enabled: enabled, vertical: reverseVertical, horizontal: reverseHorizontal)
    }
    var status: String {
        if let issue { return issue }
        if !enabled { return L("已关闭") }
        if !reverseVertical && !reverseHorizontal { return L("请选择要反转的方向") }
        return running ? L("鼠标滚轮反转已启用") : L("反转已暂停")
    }

    init(defaults: UserDefaults? = nil, allowEventTap: Bool? = nil,
         accessAvailable: @escaping () -> Bool = { AXIsProcessTrusted() },
         conflictingApp: (() -> String?)? = nil) {
        let isTest = ProcessInfo.processInfo.environment["INPUTSTATS_TEST_HOME"] != nil
        let defaults = defaults ?? (isTest ? UserDefaults(suiteName: "com.local.inputstats.tests")! : .standard)
        self.defaults = defaults
        self.allowEventTap = allowEventTap ?? !isTest
        self.accessAvailable = accessAvailable; self.conflictingApp = conflictingApp ?? Self.findConflict
        enabled = defaults.bool(forKey: "scroll.enabled")
        reverseVertical = defaults.object(forKey: "scroll.vertical") as? Bool ?? true
        reverseHorizontal = defaults.bool(forKey: "scroll.horizontal")
    }

    func start() {
        guard !started else { return }
        started = true
        let nc = NSWorkspace.shared.notificationCenter
        // Observe the running-app list directly: launch/termination notifications
        // are not reliable for every menu-bar-only app. Defer until the list settles.
        applicationsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        workspaceTokens.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false; self?.refresh()
        })
        workspaceTokens.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true; self?.stopTap()
        })
        activeToken = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func retry() { stopTap(); refresh() }

    private func refresh() {
        guard started else { return }
        guard enabled, reverseVertical || reverseHorizontal, !sleeping else {
            stopTap(); issue = nil; return
        }
        guard allowEventTap else { stopTap(); issue = L("界面测试 · 全局反转已关闭"); return }
        if let app = conflictingApp() {
            stopTap(); issue = L("%@ 正在运行。退出它后自动启用，避免重复反转。", String(describing: app)); return
        }
        guard accessAvailable() else {
            stopTap(); issue = L("辅助功能授权未生效，请在系统设置中检查 MacToys 的权限。"); return
        }
        issue = nil
        if let tap, CFMachPortIsValid(tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            running = CGEvent.tapIsEnabled(tap: tap)
            if !running { issue = L("滚轮监听未能恢复，请重试。") }
            return
        }
        stopTap()
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let store = Unmanaged<ScrollReversalStore>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if store.started, store.enabled, !store.sleeping, let tap = store.tap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        store.running = CGEvent.tapIsEnabled(tap: tap)
                        if !store.running { store.issue = L("滚轮监听已暂停，请重试。") }
                    }
                } else if type == .scrollWheel {
                    MouseWheelReversal.apply(to: event, options: store.options)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                issue = L("无法连接滚轮监听，请检查辅助功能权限后重试。"); return
            }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port); issue = L("无法创建滚轮监听，请重试。"); return
        }
        tap = port; source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        running = CGEvent.tapIsEnabled(tap: port)
        if !running { stopTap(); issue = L("滚轮监听未能启用，请重试。") }
    }

    private func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil
        if running { running = false }
    }

    func stop() {
        started = false; sleeping = false
        stopTap()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
        applicationsObservation?.invalidate(); applicationsObservation = nil
        if let activeToken { NotificationCenter.default.removeObserver(activeToken) }
        activeToken = nil
    }
    deinit { stop() }

    private static func findConflict() -> String? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.pilotmoon.scroll-reverser" && !$0.isTerminated
        }.map { $0.localizedName ?? "Scroll Reverser" }
    }
}
