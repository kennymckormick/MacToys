import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var confirmReset = false
    @State private var errorMessage: String?
    var body: some View {
        Form {
            Section("通用") {
                Toggle("登录时启动 MacToys", isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
                if let error = settings.loginError { Text(error).foregroundStyle(.orange).font(.caption) }
                Picker("时间格式", selection: $settings.use24Hour) {
                    Text("24 小时制").tag(true); Text("AM / PM").tag(false)
                }
                Stepper("近期趋势：\(settings.weekDays) 天", value: $settings.weekDays, in: 3...30)
            }
            Section("输入统计") {
                Toggle("暂停统计", isOn: $settings.paused)
                Toggle("把 ⌘V 粘贴计入输入", isOn: $settings.includePaste)
                Picker("输入来源", selection: $settings.sourceMode) {
                    Text("自动识别 Fn（豆包 / 系统听写）").tag("auto")
                    Text("全部计为键盘").tag("keyboard")
                    Text("全部计为语音").tag("voice")
                }
                Text("Fn 按住、双击锁定与松开后的延迟上屏均会处理。其他语音快捷键可手动切换来源。应用未提供文本时，英文按键会标为估算；中文不使用拼音长度猜测。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("本机数据") {
                Text("只保存分钟级计数，不保存输入内容。原 InputStats 历史记录继续保留。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("导出每日统计")
                    Spacer(); Button("CSV…") { Exporter.export(.csv) }; Button("JSON…") { Exporter.export(.json) }
                }
                HStack {
                    Button("打开数据文件夹") { NSWorkspace.shared.open(Database.directory) }
                    Spacer(); Button("清空历史数据…", role: .destructive) { confirmReset = true }
                }
            }
            Section("MacToys 0.2") {
                Text("输入统计 + Portman + 屏幕取色。关闭窗口后输入统计、转发和取色快捷键继续可用；退出 MacToys 会停止输入统计和快捷键，Portman 的连接继续由后台管理。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("清空全部历史统计？", isPresented: $confirmReset) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                InputMonitor.shared.resetAll { error in errorMessage = error?.localizedDescription }
            }
        } message: { Text("此操作会清空已保存和等待保存的全部计数，无法撤销。") }
        .alert("数据操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}
