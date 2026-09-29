import SwiftUI

struct KeepAwakeView: View {
    @ObservedObject var store: KeepAwakeStore
    @ObservedObject private var language = Localization.shared
    var compact = false
    var body: some View {
        Group {
            if compact { content }
            else { ScrollView { content } }
        }.environment(\.locale, language.locale)
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("防止休眠")).font(compact ? .headline : .title2.bold())
                    if !compact {
                        Text(L("下载、演示或远程工作时，保持 Mac 唤醒。"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle(L("保持唤醒"), isOn: Binding(get: { store.enabled }, set: store.setEnabled))
                    .toggleStyle(.switch)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(L("持续时间"), selection: Binding(get: { store.duration }, set: store.setDuration)) {
                        ForEach(AwakeDuration.allCases) { Text($0.label).tag($0) }
                    }.id(language.code).frame(maxWidth: 300)
                    Divider()
                    Toggle(L("同时保持屏幕亮起"), isOn: Binding(get: { store.keepDisplayAwake }, set: store.setKeepDisplayAwake))
                    Text(L("关闭此选项后，屏幕可按系统设置熄灭，Mac 继续运行。"))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: store.issue != nil ? "exclamationmark.circle" : (store.enabled ? "cup.and.saucer.fill" : "moon"))
                    .foregroundStyle(store.issue != nil ? Color.orange : (store.enabled ? Color.green : Color.secondary))
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.issue ?? (store.enabled ? L("防止休眠已开启") : L("已关闭 · 使用系统休眠设置")))
                        .font(.callout)
                    if store.enabled {
                        if let endsAt = store.endsAt {
                            Text(L("将在 %@ 自动关闭", endsAt.formatted(.dateTime.hour().minute().locale(language.locale))))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(L("直到手动关闭或退出 MacToys")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !compact {
                Text(L("更改持续时间会重新计时。关闭窗口后继续生效；菜单栏右键可快速开关。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(L("用于防止闲置休眠。手动睡眠、合盖与锁屏仍按 macOS 的设置处理。退出后结束，下次启动保持关闭。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(compact ? 14 : 24)
    }
}
