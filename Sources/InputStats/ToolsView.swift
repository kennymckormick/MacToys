import SwiftUI

final class ToolsModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case input = "输入统计", ports = "端口转发", colors = "屏幕取色", scroll = "滚轮反转", awake = "防止休眠", settings = "设置"
        var id: String { rawValue }
        var symbol: String {
            switch self { case .input: return "keyboard"; case .ports: return "arrow.left.arrow.right"; case .colors: return "eyedropper"; case .scroll: return "computermouse"; case .awake: return "cup.and.saucer"; case .settings: return "gearshape" }
        }
    }
    @Published var selection: Tool = .input
    @Published var visible = true
}
struct ToolsView: View {
    @ObservedObject var model: ToolsModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var colors: ColorPickerStore
    @ObservedObject var scroll: ScrollReversalStore
    @ObservedObject var awake: KeepAwakeStore
    var onPickColor: () -> Void
    @StateObject private var stats = StatsStore()
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 9) {
                    Image(systemName: "square.grid.2x2.fill").font(.title2).foregroundStyle(.blue)
                    Text("MacToys").font(.title2.bold())
                }.padding(.top, 12)
                Text("你的 Mac 工具箱").font(.caption).foregroundStyle(.secondary)
                VStack(spacing: 7) {
                    row(.input, subtitle: "InputStats")
                    row(.ports, subtitle: "Portman")
                    row(.colors, subtitle: "Color Picker")
                    row(.scroll, subtitle: "Scroll Reversal")
                    row(.awake, subtitle: "Keep Awake")
                }
                Spacer()
                row(.settings, subtitle: "偏好与数据")
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · 本机运行")
                    .font(.caption2).foregroundStyle(.tertiary)
            }.padding(20).frame(width: 205).background(.thinMaterial)
            Divider()
            Group {
                if model.visible {
                    switch model.selection {
                    case .input:
                        ScrollView { StatsView(store: stats, settings: settings, onOpenSettings: { model.selection = .settings }) }
                    case .ports: PortmanView()
                    case .colors: ColorPickerView(store: colors, onPick: onPickColor)
                    case .scroll: ScrollReversalView(store: scroll)
                    case .awake: KeepAwakeView(store: awake)
                    case .settings: SettingsView(settings: settings)
                    }
                } else { Color.clear }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 920, minHeight: 660)
    }
    private func row(_ tool: ToolsModel.Tool, subtitle: String) -> some View {
        Button { model.selection = tool } label: {
            HStack(spacing: 12) {
                Image(systemName: tool.symbol).frame(width: 20).font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.rawValue).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(12).contentShape(Rectangle())
                .background(model.selection == tool ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}
