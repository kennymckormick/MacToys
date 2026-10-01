import SwiftUI

extension QuickTool {
    var title: String {
        switch self {
        case .todo: return L("待办")
        case .notes: return L("笔记")
        case .goals: return L("目标")
        case .input: return L("统计")
        case .colors: return L("取色")
        case .scroll: return L("滚轮")
        case .awake: return L("防休眠")
        }
    }
    var tool: ToolsModel.Tool {
        switch self { case .todo: return .todo; case .notes: return .notes; case .goals: return .goals; case .input: return .input; case .colors: return .colors; case .scroll: return .scroll; case .awake: return .awake }
    }
}

private struct QuickContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct QuickToolsPopoverView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var quickPanel: QuickPanelSettings
    @ObservedObject var todos: TodoStore
    @ObservedObject var goals: GoalStore
    @ObservedObject var notes: NotesStore
    @ObservedObject var colors: ColorPickerStore
    @ObservedObject var scroll: ScrollReversalStore
    @ObservedObject var awake: KeepAwakeStore
    @ObservedObject private var language = Localization.shared
    let size: NSSize
    var onPickColor: () -> Void
    var onOpenSettings: () -> Void
    var onOpenTools: (ToolsModel.Tool) -> Void
    var onHeightChange: (CGFloat) -> Void
    @State private var contentHeight = Self.initialHeight
    static let initialHeight: CGFloat = 420

    static func contentSize(in visibleFrame: NSRect) -> NSSize {
        NSSize(width: min(460, max(1, visibleFrame.width - 32)), height: min(600, max(1, visibleFrame.height - 40)))
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill").foregroundStyle(.secondary)
                        .help(L("MacToys 工具箱")).accessibilityLabel(L("MacToys 工具箱"))
                    Picker(L("快捷工具"), selection: Binding(get: { quickPanel.selection }, set: quickPanel.select)) {
                        ForEach(quickPanel.configuration.tools) { tab in
                            Label(tab.title, systemImage: tab.tool.symbol).tag(tab)
                        }
                    }.id(language.code).pickerStyle(.segmented).labelsHidden().controlSize(.small)
                        .frame(maxWidth: .infinity)
                    if awake.enabled {
                        Image(systemName: "cup.and.saucer.fill").foregroundStyle(.green)
                            .help(L("防止休眠已开启")).accessibilityLabel(L("防止休眠已开启"))
                    }
                    Menu {
                        Picker(L("语言"), selection: $language.language) {
                            ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.inline)
                    } label: { Image(systemName: "globe") }
                        .menuStyle(.borderlessButton).fixedSize().help(L("语言 / Language"))
                        .accessibilityLabel(L("语言 / Language"))
                }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                Group {
                    switch quickPanel.selection {
                    case .todo: TodoView(store: todos, compact: true)
                    case .notes: NotesView(store: notes, compact: true)
                    case .goals: GoalView(store: goals, compact: true)
                    case .input: StatsView(store: store, settings: settings, compact: true, onOpenSettings: onOpenSettings)
                    case .colors: QuickColorPickerView(store: colors, onPick: onPickColor)
                    case .scroll: ScrollReversalView(store: scroll, compact: true)
                    case .awake: KeepAwakeView(store: awake, compact: true)
                    }
                }
                Divider().padding(.horizontal, 12)
                HStack {
                    Button { onOpenTools(quickPanel.selection.tool) } label: { Label(L("打开主窗口"), systemImage: "arrow.up.right.square") }
                    Spacer()
                    Button(action: onOpenSettings) { Image(systemName: "gearshape").frame(width: 22, height: 22) }
                        .help(L("设置与小菜单配置")).accessibilityLabel(L("设置与小菜单配置"))
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in Color.clear.preference(key: QuickContentHeightKey.self, value: proxy.size.height) })
        }
        .id(quickPanel.selection)
        .defaultScrollAnchor(.top)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: size.width, height: min(size.height, contentHeight), alignment: .topLeading)
        .environment(\.locale, language.locale)
        .onPreferenceChange(QuickContentHeightKey.self) { height in
            let height = ceil(height)
            guard height.isFinite, height > 0, abs(contentHeight - height) >= 1 else { return }
            contentHeight = height; onHeightChange(min(size.height, height))
        }
        .onAppear { awake.expireIfNeeded() }
    }
}
