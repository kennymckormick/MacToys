import SwiftUI

private extension TodoItem {
    // LazyVStack flattens both ForEach sections. A moved row needs a distinct identity
    // so its checkbox does not retain the old section's captured binding.
    var rowIdentity: String { "\(id.uuidString)-\(isCompleted)" }
}

struct TodoView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject private var language = Localization.shared
    var compact = false
    @State private var showCompleted = false
    @State private var editingID: UUID?
    @State private var editingTitle = ""
    @State private var confirmClear = false
    @FocusState private var editorFocused: Bool
    private var pending: [TodoItem] { store.items.filter { !$0.isCompleted } }
    private var completed: [TodoItem] { store.items.filter(\.isCompleted) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("待办清单")).font(compact ? .headline : .title2.bold())
                Spacer()
                Text(L("%@ 项待办", String(pending.count))).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField(L("添加待办…"), text: $store.draft)
                    .textFieldStyle(.roundedBorder).onSubmit(add)
                    .accessibilityLabel(L("新待办"))
                Button(action: add) { Image(systemName: "plus").frame(width: 18) }
                    .buttonStyle(.borderedProminent).help(L("添加待办")).accessibilityLabel(L("添加待办"))
                    .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.disabled(!store.canEdit)
            if let error = store.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    if !store.canEdit { Button(L("重试")) { store.reload() } }
                }
            }
            if compact {
                ScrollView {
                    listContent
                }.frame(height: min(300, (pending.isEmpty ? 76 : CGFloat(pending.count) * 46) + (completed.isEmpty ? 0 : 40) + (showCompleted ? CGFloat(completed.count) * 46 : 0)))
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                ScrollView { listContent }.frame(maxHeight: .infinity)
            }
            HStack {
                Text(L("保存在本机")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !completed.isEmpty {
                    Button(L("清除已完成…")) { confirmClear = true }.font(.caption).buttonStyle(.plain)
                        .foregroundStyle(.secondary).disabled(!store.canEdit)
                }
            }
        }
        .padding(compact ? 14 : 24)
        .alert(L("清除所有已完成的待办？"), isPresented: $confirmClear) {
            Button(L("取消"), role: .cancel) {}
            Button(L("清除"), role: .destructive) { store.clearCompleted() }
        } message: { Text(L("未完成的待办会保留。此操作无法撤销。")) }
        .onChange(of: store.items) { _, items in
            if let editingID, !items.contains(where: { $0.id == editingID }) { self.editingID = nil }
        }
        .environment(\.locale, language.locale)
    }

    private var listContent: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            if pending.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    Text(store.items.isEmpty ? L("记下下一件要做的事") : L("待办已全部完成"))
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            }
            ForEach(pending, id: \.rowIdentity) { row($0) }
            if !completed.isEmpty {
                Button { showCompleted.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showCompleted ? "chevron.down" : "chevron.right").font(.caption2)
                        Text(L("已完成（%@）", String(completed.count))).font(.caption)
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if showCompleted { ForEach(completed, id: \.rowIdentity) { row($0) } }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Toggle(isOn: Binding(get: { item.isCompleted }, set: { store.setCompleted($0, id: item.id) })) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel(L("完成待办：%@", item.title))
            if editingID == item.id {
                TextField(L("待办内容"), text: $editingTitle)
                    .textFieldStyle(.roundedBorder).focused($editorFocused)
                    .onSubmit { saveEdit(item.id) }.onExitCommand { editingID = nil }
                Button { saveEdit(item.id) } label: { Image(systemName: "checkmark") }
                    .help(L("保存")).accessibilityLabel(L("保存"))
                    .disabled(editingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { editingID = nil } label: { Image(systemName: "xmark") }
                    .help(L("取消")).accessibilityLabel(L("取消"))
            } else {
                Text(item.title).font(.system(size: compact ? 13 : 14))
                    .strikethrough(item.isCompleted).foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(compact ? 2 : nil).frame(maxWidth: .infinity, alignment: .leading).help(item.title)
                Button {
                    editingTitle = item.title; editingID = item.id; editorFocused = true
                } label: { Image(systemName: "pencil") }
                    .help(L("编辑")).accessibilityLabel(L("编辑待办：%@", item.title))
                Button { store.remove(item.id) } label: { Image(systemName: "trash") }
                    .help(L("删除")).accessibilityLabel(L("删除待办：%@", item.title))
            }
        }.buttonStyle(.borderless).padding(.horizontal, 8).padding(.vertical, 7)
            .frame(minHeight: 40)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
            .disabled(!store.canEdit)
    }

    private func add() {
        if store.add(store.draft) { store.draft = "" }
    }
    private func saveEdit(_ id: UUID) {
        if store.rename(id, to: editingTitle) { editingID = nil }
    }
}
