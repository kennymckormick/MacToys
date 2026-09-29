import SwiftUI
import InputStatsCore

struct QuickColorPickerView: View {
    @ObservedObject var store: ColorPickerStore
    @ObservedObject private var language = Localization.shared
    var onPick: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: store.selected.nativeColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))
                    .frame(width: 48, height: 48).accessibilityLabel(L("颜色预览 %@", String(describing: store.selected.hex)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.selected.hex).font(.system(size: 17, weight: .semibold, design: .monospaced))
                    Text(store.shortcutEnabled ? store.shortcut.label : L("屏幕取色")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onPick) { Label(L("拾取"), systemImage: "eyedropper") }
                    .buttonStyle(.borderedProminent).disabled(store.isSampling)
                    .help(L("启动系统放大镜；点击取色，Esc 取消"))
                Button { store.toggleFavorite(store.selected) } label: {
                    Image(systemName: store.favorites.contains(store.selected) ? "star.fill" : "star")
                }.buttonStyle(.plain).help(L("收藏当前颜色")).accessibilityLabel(L("收藏当前颜色"))
            }
            VStack(spacing: 8) {
                ForEach(ColorTextFormat.allCases) { format in
                    HStack {
                        Text(format.rawValue).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                        Text(store.selected.formatted(format)).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        Button { store.copy(format) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.plain).help(L("复制 %@", String(describing: format.rawValue))).accessibilityLabel(L("复制 %@", String(describing: format.rawValue)))
                    }
                }
            }.padding(10).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Toggle(L("取色后自动复制"), isOn: $store.autoCopy).font(.caption)
                Spacer()
                Picker(L("复制格式"), selection: $store.format) {
                    ForEach(ColorTextFormat.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 76)
            }.controlSize(.small)
            if !store.history.isEmpty { swatches(L("最近颜色"), colors: Array(store.history.prefix(10))) }
            if !store.favorites.isEmpty { swatches(L("收藏"), colors: Array(store.favorites.prefix(10))) }
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            } else if let message = store.message {
                Label(message, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14)
    }
    private func swatches(_ title: String, colors: [ScreenColor]) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
            ForEach(colors) { color in
                Button { store.select(color) } label: {
                    RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: color.nativeColor))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(store.selected == color ? 0.7 : 0.12)))
                        .frame(width: 27, height: 24)
                }.buttonStyle(.plain).help(color.hex).accessibilityLabel("\(title) \(color.hex)")
            }
            Spacer(minLength: 0)
        }
    }
}
