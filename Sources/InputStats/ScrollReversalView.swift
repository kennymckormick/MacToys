import SwiftUI

struct ScrollReversalView: View {
    @ObservedObject var store: ScrollReversalStore
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
                    Text(L("滚轮反转")).font(compact ? .headline : .title2.bold())
                    if !compact {
                        Text(L("调整鼠标滚轮，保留触控板的滚动方向。"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle(L("反转鼠标滚轮"), isOn: $store.enabled).toggleStyle(.switch)
            }
            GroupBox {
                VStack(spacing: 14) {
                    Toggle(L("反转垂直滚动"), isOn: $store.reverseVertical)
                    Divider()
                    Toggle(L("反转水平滚动"), isOn: $store.reverseHorizontal)
                }.disabled(!store.enabled).padding(10)
            }
            HStack(alignment: .top) {
                Image(systemName: store.issue != nil ? "exclamationmark.circle" : (store.running ? "checkmark.circle.fill" : "pause.circle"))
                    .foregroundStyle(store.issue != nil ? Color.orange : (store.running ? Color.green : Color.secondary))
                Text(store.status).font(.callout)
                Spacer()
                if store.enabled && store.issue != nil { Button(L("重试")) { store.retry() } }
            }
            if !compact { GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.and.hand.point.up.left").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("触控板保持系统方向")).font(.callout.bold())
                        Text(L("双指滚动和惯性滚动均不反转。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(10)
            } }
            Text(L("适用于普通滚轮鼠标。Magic Mouse、连续滚动及其他软件生成的滚动保持原样。方向相对于 macOS 当前设置反转。"))
                .font(.caption).foregroundStyle(.secondary)
            if !compact {
                Text(L("关闭窗口后继续生效；菜单栏右键可快速开关。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(compact ? 14 : 24)
    }
}
