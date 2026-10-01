import Foundation
import ServiceManagement

extension Notification.Name {
    static let statsDidReset = Notification.Name("InputStats.statsDidReset")
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @Published var use24Hour: Bool { didSet { save(use24Hour, "use24Hour") } }
    @Published var weekDays: Int { didSet { save(weekDays, "weekDays"); NotificationCenter.default.post(name: .statsDidChange, object: nil) } }
    @Published var paused: Bool { didSet { save(paused, "paused"); changed() } }
    @Published var includePaste: Bool { didSet { save(includePaste, "includePaste"); changed() } }
    @Published var sourceMode: String { didSet { save(sourceMode, "sourceMode"); changed() } }
    let quickPanel: QuickPanelSettings
    @Published var launchAtLogin = false
    @Published var loginError: String?
    private let defaults: UserDefaults
    private init() {
        defaults = ProcessInfo.processInfo.environment["INPUTSTATS_TEST_HOME"] == nil ? .standard : UserDefaults(suiteName: "com.local.inputstats.tests")!
        use24Hour = defaults.object(forKey: "use24Hour") as? Bool ?? true
        weekDays = min(30, max(3, defaults.object(forKey: "weekDays") as? Int ?? 7))
        paused = defaults.bool(forKey: "paused")
        includePaste = defaults.bool(forKey: "includePaste")
        let mode = defaults.string(forKey: "sourceMode") ?? "auto"
        sourceMode = ["auto", "keyboard", "voice"].contains(mode) ? mode : "auto"
        quickPanel = QuickPanelSettings(defaults: defaults)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
    private func changed() { NotificationCenter.default.post(name: .monitorSettingsDidChange, object: nil) }
    func reloadPreferences() {
        use24Hour = defaults.object(forKey: "use24Hour") as? Bool ?? true
        weekDays = defaults.object(forKey: "weekDays") as? Int ?? 7
        paused = defaults.bool(forKey: "paused")
        includePaste = defaults.bool(forKey: "includePaste")
        sourceMode = defaults.string(forKey: "sourceMode") ?? "auto"
        quickPanel.reload()
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? L("请在系统设置的登录项中启用 MacToys。") : nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = error.localizedDescription
        }
    }
}
