import SwiftUI
import ApplicationServices

enum FirstLaunch {
    static func needsSetup(directory: URL, defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: "setup.seen") else { return false }
        // Existing installations keep their default tool and permissions.
        return !["stats.sqlite", "todos.json", "notes.json", "goals.json"].contains {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }
}

struct SetupChecklist: View {
    @State private var accessibility = AXIsProcessTrusted()
    @State private var inputMonitoring = CGPreflightListenEventAccess()
    private var testing: Bool { ProcessInfo.processInfo.environment["INPUTSTATS_TEST_HOME"] != nil }
    private var installed: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
    var body: some View {
        Section(L("开始使用")) {
            if !installed {
                Text(L("先将 MacToys 拖入「应用程序」，从那里打开，再授予权限。"))
                    .font(.callout).foregroundStyle(.orange)
                Button(L("打开应用程序文件夹")) { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications")) }
            }
            Text(L("待办、笔记、长期目标、端口转发和防止休眠可直接使用。输入统计与滚轮反转需要以下系统权限。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Label(L("辅助功能"), systemImage: accessibility ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(accessibility ? .green : .secondary)
                Spacer()
                Button(accessibility ? L("查看设置") : L("授予权限")) {
                    if !accessibility {
                        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                    }
                    openPrivacy("Privacy_Accessibility")
                }.disabled(testing)
            }
            HStack {
                Label(L("输入监控"), systemImage: inputMonitoring ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(inputMonitoring ? .green : .secondary)
                Spacer()
                Button(inputMonitoring ? L("查看设置") : L("授予权限")) {
                    if !inputMonitoring { _ = CGRequestListenEventAccess() }
                    openPrivacy("Privacy_ListenEvent")
                }.disabled(testing)
            }
            Text(L("在系统设置中启用 MacToys；如列表中没有它，点「+」添加应用。授权后退出并重新打开 MacToys。输入统计只保存计数，不保存输入原文。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func refresh() { accessibility = AXIsProcessTrusted(); inputMonitoring = CGPreflightListenEventAccess() }
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) { NSWorkspace.shared.open(url) }
    }
}
