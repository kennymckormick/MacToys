import SwiftUI

final class ToolsModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case todo, input, ports, colors, scroll, awake, settings
        var title: String {
            switch self {
            case .todo: return L("待办清单")
            case .input: return L("输入统计")
            case .ports: return L("端口转发")
            case .colors: return L("屏幕取色")
            case .scroll: return L("滚轮反转")
            case .awake: return L("防止休眠")
            case .settings: return L("设置")
            }
        }
        var id: String { rawValue }
        var symbol: String {
            switch self { case .todo: return "checklist"; case .input: return "keyboard"; case .ports: return "arrow.left.arrow.right"; case .colors: return "eyedropper"; case .scroll: return "computermouse"; case .awake: return "cup.and.saucer"; case .settings: return "gearshape" }
        }
    }
    @Published var selection: Tool = .todo
    @Published var visible = true
}
struct ToolsView: View {
    @ObservedObject var model: ToolsModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var todos: TodoStore
    @ObservedObject var colors: ColorPickerStore
    @ObservedObject var scroll: ScrollReversalStore
    @ObservedObject var awake: KeepAwakeStore
    var onPickColor: () -> Void
    @ObservedObject private var language = Localization.shared
    @StateObject private var stats = StatsStore()
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 9) {
                    Image(systemName: "wrench.and.screwdriver.fill").font(.title2).foregroundStyle(.blue)
                    Text("MacToys").font(.title2.bold())
                }.padding(.top, 12)
                Text(L("你的 Mac 工具箱")).font(.caption).foregroundStyle(.secondary)
                VStack(spacing: 7) {
                    row(.todo)
                    row(.input)
                    row(.ports)
                    row(.colors)
                    row(.scroll)
                    row(.awake)
                }
                Spacer()
                row(.settings)
                Text(L("%@ · 本机运行", String(describing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")))
                    .font(.caption2).foregroundStyle(.tertiary)
            }.padding(20).frame(width: 205).background(.thinMaterial)
            Divider()
            Group {
                if model.visible {
                    switch model.selection {
                    case .todo: TodoView(store: todos)
                    case .input:
                        ScrollView { StatsView(store: stats, settings: settings, onOpenSettings: { model.selection = .settings }) }
                    case .ports: PortmanView()
                    case .colors: ColorPickerView(store: colors, onPick: onPickColor)
                    case .scroll: ScrollReversalView(store: scroll)
                    case .awake: KeepAwakeView(store: awake)
                    case .settings: SettingsView(settings: settings, quickPanel: settings.quickPanel)
                    }
                } else { Color.clear }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 920, minHeight: 660).environment(\.locale, language.locale)
    }
    private func row(_ tool: ToolsModel.Tool) -> some View {
        Button { model.selection = tool } label: {
            HStack(spacing: 12) {
                Image(systemName: tool.symbol).frame(width: 20).font(.title3)
                Text(tool.title).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer()
            }.padding(12).contentShape(Rectangle())
                .background(model.selection == tool ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}
