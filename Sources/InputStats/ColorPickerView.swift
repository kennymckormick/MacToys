import SwiftUI
import InputStatsCore

struct ColorPickerView: View {
    @ObservedObject private var language = Localization.shared
    @ObservedObject var store: ColorPickerStore
    var onPick: () -> Void
    @State private var hexInput = ""
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("屏幕取色")).font(.largeTitle.bold())
                        Text(L("拾取屏幕上的颜色，用在设计与代码中。")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onPick) { Label(L("拾取屏幕颜色"), systemImage: "eyedropper") }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(store.isSampling)
                        .help(L("启动系统放大镜；点击取色，Esc 取消"))
                }
                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(nsColor: store.selected.nativeColor))
                            .overlay(alignment: .bottomLeading) {
                                Text(store.selected.hex).font(.system(.title3, design: .monospaced).bold())
                                    .foregroundStyle(store.selected.prefersDarkText ? .black : .white).padding(16)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)))
                            .frame(height: 155).accessibilityLabel(L("颜色预览 %@", String(describing: store.selected.hex)))
                        HStack {
                            ColorPicker(L("调整颜色"), selection: Binding(
                                get: { Color(nsColor: store.selected.nativeColor) }, set: { store.preview(NSColor($0)) }), supportsOpacity: false)
                                .font(.caption)
                            Spacer()
                            Button { store.toggleFavorite(store.selected) } label: {
                                Image(systemName: store.favorites.contains(store.selected) ? "star.fill" : "star")
                            }.help(store.favorites.contains(store.selected) ? L("取消收藏") : L("收藏当前颜色"))
                                .accessibilityLabel(store.favorites.contains(store.selected) ? L("取消收藏当前颜色") : L("收藏当前颜色"))
                        }
                    }.frame(width: 180)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(ColorTextFormat.allCases) { format in
                            HStack(spacing: 12) {
                                Text(format.rawValue).font(.caption.bold()).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                                Text(store.selected.formatted(format)).font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled).lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                                Button { store.copy(format) } label: { Image(systemName: "doc.on.doc") }
                                    .help(L("复制 %@", String(describing: format.rawValue))).accessibilityLabel(L("复制 %@", String(describing: format.rawValue)))
                            }.padding(.vertical, 13)
                            if format != .hsl { Divider() }
                        }
                        HStack {
                            TextField("#RRGGBB", text: $hexInput).font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder).frame(maxWidth: 130)
                                .accessibilityLabel(L("HEX 颜色输入")).onSubmit { store.apply(hex: hexInput) }
                            Button(L("应用 HEX")) { store.apply(hex: hexInput) }
                            Spacer(minLength: 0)
                            Text(L("sRGB · 8 位")).font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 14)
                    }.frame(maxWidth: .infinity)
                }
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                } else if let message = store.message {
                    Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.secondary).font(.callout)
                }
                palette(title: L("最近颜色"), colors: store.history, isHistory: true)
                palette(title: L("收藏"), colors: store.favorites, isHistory: false)
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Toggle(L("取色后自动复制"), isOn: $store.autoCopy)
                            Spacer()
                            Picker(L("复制格式"), selection: $store.format) {
                                ForEach(ColorTextFormat.allCases) { Text($0.rawValue).tag($0) }
                            }.frame(width: 165)
                        }
                        Toggle(L("取色后打开颜色面板"), isOn: $store.showAfterPicking)
                        Divider()
                        HStack {
                            Toggle(L("全局取色快捷键"), isOn: $store.shortcutEnabled)
                            Spacer()
                            Button(store.isRecording ? L("按下组合键…") : store.shortcut.label) { store.beginRecording() }
                                .font(.system(.body, design: .monospaced)).frame(minWidth: 100)
                                .accessibilityLabel(L("设置取色快捷键"))
                                .accessibilityValue(store.isRecording ? L("正在录制") : store.shortcut.label)
                            if store.isRecording { Button(L("取消")) { store.cancelRecording() } }
                        }
                        if let error = store.shortcutError { Text(error).font(.caption).foregroundStyle(.orange) }
                        Text(store.isRecording ? L("字母或数字 + ⌘ / ⌥ / ⌃；Esc 取消。") : L("菜单栏右键也可取色。使用放大镜时，空格显示 RGB，Esc 取消。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
                Text(L("最近保留 24 个颜色，收藏单独保存于本机。HEX、RGB 和 HSL 使用 sRGB；超出其范围的广色域颜色会被截取到可表示范围。"))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }
        .onAppear { hexInput = store.selected.hex }
        .onChange(of: store.selected) { _, color in hexInput = color.hex }
        .onDisappear { store.cancelRecording() }
        .confirmationDialog(L("清空最近颜色？收藏会保留。"), isPresented: $confirmClear) {
            Button(L("清空最近颜色"), role: .destructive) { store.clearHistory() }
        }
    }

    private func palette(title: String, colors: [ScreenColor], isHistory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Text("\(colors.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if isHistory && !colors.isEmpty { Button(L("清空…")) { confirmClear = true }.font(.caption) }
            }
            if colors.isEmpty {
                Text(isHistory ? L("拾取或复制的颜色会保留在这里，点击色块可再次查看。") : L("点击星标收藏常用颜色。"))
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 110), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(colors) { color in
                        Button { store.select(color) } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: color.nativeColor))
                                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.12)))
                                    .frame(height: 38)
                                Text(color.hex).font(.system(.caption2, design: .monospaced)).foregroundStyle(.primary)
                            }.padding(5).background(store.selected == color ? Color.accentColor.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).help(L("查看 %@", String(describing: color.hex)))
                            .accessibilityLabel("\(title) \(color.hex)")
                            .contextMenu {
                                ForEach(ColorTextFormat.allCases) { format in
                                    Button(L("复制 %@", String(describing: format.rawValue))) { store.select(color); store.copy(format) }
                                }
                                Divider()
                                Button(store.favorites.contains(color) ? L("取消收藏") : L("收藏")) { store.toggleFavorite(color) }
                                if isHistory { Button(L("从最近颜色移除"), role: .destructive) { store.removeFromHistory(color) } }
                            }
                    }
                }
            }
        }
    }
}
