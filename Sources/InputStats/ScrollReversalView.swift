import SwiftUI

struct ScrollReversalView: View {
    @ObservedObject var store: ScrollReversalStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("滚轮反转").font(.title2.bold())
                        Text("调整鼠标滚轮，保留触控板的滚动方向。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("反转鼠标滚轮", isOn: $store.enabled).toggleStyle(.switch)
                }
                GroupBox {
                    VStack(spacing: 14) {
                        Toggle("反转垂直滚动", isOn: $store.reverseVertical)
                        Divider()
                        Toggle("反转水平滚动", isOn: $store.reverseHorizontal)
                    }.disabled(!store.enabled).padding(10)
                }
                HStack(alignment: .top) {
                    Image(systemName: store.issue != nil ? "exclamationmark.circle" : (store.running ? "checkmark.circle.fill" : "pause.circle"))
                        .foregroundStyle(store.issue != nil ? Color.orange : (store.running ? Color.green : Color.secondary))
                    Text(store.status).font(.callout)
                    Spacer()
                    if store.enabled && store.issue != nil { Button("重试") { store.retry() } }
                }
                GroupBox {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.and.hand.point.up.left").font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("触控板保持系统方向").font(.callout.bold())
                            Text("双指滚动和惯性滚动均不反转。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.padding(10)
                }
                Text("适用于普通滚轮鼠标。Magic Mouse、连续滚动及其他软件生成的滚动保持原样。方向相对于 macOS 当前设置反转。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("关闭窗口后继续生效；菜单栏右键可快速开关。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
}
