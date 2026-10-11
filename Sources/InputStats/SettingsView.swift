import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var quickPanel: QuickPanelSettings
    @ObservedObject private var language = Localization.shared
    @State private var confirmReset = false
    @State private var errorMessage: String?
    var body: some View {
        Form {
            SetupChecklist()
            Section(L("小菜单")) {
                HStack {
                    Text(L("选择常用功能"))
                    Spacer()
                    Text("\(quickPanel.configuration.tools.count) / \(QuickPanelSettings.limit)")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                ForEach(QuickTool.allCases) { tool in
                    let included = quickPanel.configuration.tools.contains(tool)
                    Toggle(isOn: Binding(get: { quickPanel.configuration.tools.contains(tool) }, set: { quickPanel.setIncluded($0, tool: tool) })) {
                        Label(tool.tool.title, systemImage: tool.tool.symbol)
                    }
                    .disabled(tool == .notes || (!included && quickPanel.configuration.tools.count == QuickPanelSettings.limit))
                }
                Picker(L("默认打开"), selection: Binding(get: { quickPanel.configuration.preferred }, set: quickPanel.setPreferred)) {
                    ForEach(quickPanel.configuration.tools) { Text($0.tool.title).tag($0) }
                }.id(language.code)
                Text(L("笔记固定在小菜单中，可再添加最多 3 个功能。每次打开默认页签；其他功能仍可在主窗口使用。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("通用")) {
                Picker(L("语言 / Language"), selection: $language.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                Toggle(L("登录时启动 MacToys"), isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
                    .disabled(settings.keepRunning)
                if let error = settings.loginError { Text(error).foregroundStyle(.orange).font(.caption) }
                Toggle(L("退出后自动重启"), isOn: Binding(get: { settings.keepRunning }, set: settings.setKeepRunning))
                    .disabled(settings.residentBusy)
                Text(L("常驻开启时，登录后自动启动，退出后会重新拉起。要彻底退出，请先关闭此项。"))
                    .font(.caption).foregroundStyle(.secondary)
                if let error = settings.residentError { Text(error).foregroundStyle(.orange).font(.caption) }
                Picker(L("时间格式"), selection: $settings.use24Hour) {
                    Text(L("24 小时制")).tag(true); Text("AM / PM").tag(false)
                }
                Stepper(L("近期趋势：%@ 天", String(describing: settings.weekDays)), value: $settings.weekDays, in: 3...30)
            }
            Section(L("输入统计")) {
                Toggle(L("暂停统计"), isOn: $settings.paused)
                Toggle(L("把 ⌘V 粘贴计入输入"), isOn: $settings.includePaste)
                Picker(L("输入来源"), selection: $settings.sourceMode) {
                    Text(L("自动识别 Fn（豆包 / 系统听写）")).tag("auto")
                    Text(L("全部计为键盘")).tag("keyboard")
                    Text(L("全部计为语音")).tag("voice")
                }
                Text(L("Fn 按住、双击锁定与松开后的延迟上屏均会处理。其他语音快捷键可手动切换来源。应用未提供文本时，英文按键会标为估算；中文不使用拼音长度猜测。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("本机数据")) {
                Text(L("输入统计只保存计数，不记录输入原文。待办、长期目标和笔记独立保存，清空统计不会删除它们。可在云端同步中手动备份。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(L("导出每日统计"))
                    Spacer(); Button("CSV…") { Exporter.export(.csv) }; Button("JSON…") { Exporter.export(.json) }
                }
                HStack {
                    Button(L("打开数据文件夹")) { NSWorkspace.shared.open(Database.directory) }
                    Spacer(); Button(L("清空历史数据…"), role: .destructive) { confirmReset = true }
                }
            }
            Section("MacToys") {
                Text(L("关闭窗口后功能继续运行；常驻开启时，退出后自动恢复。Portman 转发由独立后台管理。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert(L("清空全部历史统计？"), isPresented: $confirmReset) {
            Button(L("取消"), role: .cancel) {}
            Button(L("清空"), role: .destructive) {
                InputMonitor.shared.resetAll { error in errorMessage = error.map(Database.errorDescription) }
            }
        } message: { Text(L("此操作会清空已保存和等待保存的全部计数，无法撤销。")) }
        .alert(L("数据操作失败"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(L("好")) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}
