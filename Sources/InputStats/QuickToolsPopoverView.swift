import SwiftUI

enum QuickTool: String, CaseIterable, Identifiable {
    case input, colors, scroll, awake
    var id: String { rawValue }
    var title: String {
        switch self {
        case .input: return L("统计")
        case .colors: return L("取色")
        case .scroll: return L("滚轮")
        case .awake: return L("防休眠")
        }
    }
    var tool: ToolsModel.Tool {
        switch self { case .input: return .input; case .colors: return .colors; case .scroll: return .scroll; case .awake: return .awake }
    }
}

private struct QuickContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct QuickToolsPopoverView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var settings: AppSettings
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
                HStack(spacing: 7) {
                    Image(systemName: "wrench.and.screwdriver.fill").foregroundStyle(.secondary)
                    Text("MacToys").font(.system(size: 12, weight: .semibold))
                    if awake.enabled {
                        Image(systemName: "cup.and.saucer.fill").foregroundStyle(.green)
                            .help(L("防止休眠已开启")).accessibilityLabel(L("防止休眠已开启"))
                    }
                    Spacer()
                    Menu {
                        Picker(L("语言"), selection: $language.language) {
                            ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.inline)
                    } label: { Image(systemName: "globe") }
                        .menuStyle(.borderlessButton).fixedSize().help(L("语言 / Language"))
                        .accessibilityLabel(L("语言 / Language"))
                }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
                Picker(L("快捷工具"), selection: $settings.quickTool) {
                    ForEach(QuickTool.allCases) { tab in
                        Label(tab.title, systemImage: tab.tool.symbol).tag(tab)
                    }
                }.id(language.code).pickerStyle(.segmented).labelsHidden().controlSize(.regular)
                    .padding(.horizontal, 14).padding(.bottom, 8)
                Group {
                    switch settings.quickTool {
                    case .input: StatsView(store: store, settings: settings, compact: true, onOpenSettings: onOpenSettings)
                    case .colors: QuickColorPickerView(store: colors, onPick: onPickColor)
                    case .scroll: ScrollReversalView(store: scroll, compact: true)
                    case .awake: KeepAwakeView(store: awake, compact: true)
                    }
                }
                Divider().padding(.horizontal, 14)
                HStack {
                    Button { onOpenTools(.ports) } label: { Label(L("端口转发"), systemImage: "arrow.left.arrow.right") }
                    Spacer()
                    Button { onOpenTools(settings.quickTool.tool) } label: { Label(L("打开主窗口"), systemImage: "arrow.up.right.square") }
                    Button(action: onOpenSettings) { Image(systemName: "gearshape").frame(width: 24, height: 24) }
                        .help(L("设置")).accessibilityLabel(L("设置"))
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in Color.clear.preference(key: QuickContentHeightKey.self, value: proxy.size.height) })
        }
        .id(settings.quickTool)
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
