import SwiftUI
import UniformTypeIdentifiers

struct NotesView: View {
    @ObservedObject var store: NotesStore
    var compact = false
    @ObservedObject private var language = Localization.shared
    @State private var deleting: UUID?
    @State private var exportError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if !compact { Text(L("笔记")).font(.title2.bold()) }
                if !store.items.isEmpty {
                    Picker(L("选择笔记"), selection: $store.selection) {
                        ForEach(store.items) { note in Text(note.title.isEmpty ? L("未命名笔记") : note.title).tag(Optional(note.id)) }
                    }.labelsHidden().frame(maxWidth: .infinity).disabled(!store.canEdit)
                } else { Spacer() }
                Button { store.add() } label: { Image(systemName: "plus") }.help(L("新建笔记")).accessibilityLabel(L("新建笔记"))
                    .disabled(!store.canEdit || store.items.count >= 1_000)
                if let note = store.selected {
                    Button { export(note) } label: { Image(systemName: "square.and.arrow.up") }.help(L("导出 Markdown"))
                        .accessibilityLabel(L("导出 Markdown"))
                    Button { deleting = note.id } label: { Image(systemName: "trash") }.help(L("删除笔记"))
                        .accessibilityLabel(L("删除笔记")).disabled(!store.canEdit)
                }
            }.controlSize(compact ? .small : .regular)
            if let note = store.selected {
                TextField(L("笔记标题"), text: Binding(get: { store.items.first { $0.id == note.id }?.title ?? "" }, set: { store.update(note.id, title: $0) }))
                    .textFieldStyle(.plain).font(.system(size: compact ? 15 : 19, weight: .semibold)).disabled(!store.canEdit)
                NotesEditor(store: store, note: note, language: language.code)
                    .id(note.id).frame(minHeight: compact ? 255 : 350, maxHeight: compact ? 255 : .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    .disabled(!store.canEdit)
                HStack {
                    Text(store.dirty ? L("正在保存…") : L("已保存在本机"))
                    Spacer()
                    Text(L("Markdown · ⌘B 加粗 · ⌘I 斜体"))
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.and.pencil").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text(L("记下临时想法、会议记录或草稿。"))
                    Button(L("新建笔记")) { store.add() }.disabled(!store.canEdit)
                }.frame(maxWidth: .infinity, minHeight: compact ? 160 : 280)
            }
            if let error = store.errorMessage ?? exportError {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    if store.canEdit { Button(L("重试保存")) { try? store.flush() }.controlSize(.small) }
                }
            }
        }.padding(compact ? 12 : 22)
            .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity, alignment: .topLeading)
            .alert(L("删除这篇笔记？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { id in
                Button(L("取消"), role: .cancel) { deleting = nil }
                Button(L("删除"), role: .destructive) { store.remove(id); deleting = nil }
            }
    }
    private func export(_ note: NoteItem) {
        Task {
            // A failed WebKit process must not prevent exporting the last native copy.
            try? await NotesEditorRegistry.shared.flushAll()
            let latest = store.items.first { $0.id == note.id } ?? note
            let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            let title = latest.title.trimmingCharacters(in: .whitespacesAndNewlines)
            panel.nameFieldStringValue = (title.isEmpty ? "Note" : String(title.prefix(80)).replacingOccurrences(of: "/", with: "-")) + ".md"
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do { try latest.markdown.write(to: url, atomically: true, encoding: .utf8); exportError = nil }
                    catch { exportError = L("无法导出笔记，请检查目标文件夹的写入权限。") }
                }
            }
        }
    }
}
