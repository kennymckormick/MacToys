import SwiftUI

struct GoalView: View {
    @ObservedObject var store: GoalStore
    @ObservedObject private var language = Localization.shared
    var compact = false
    @State private var adding = false
    @State private var editingID: UUID?
    @State private var editingGoal = ""
    @State private var editingStatus = ""
    @State private var deleting: LongTermGoal?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 18) {
            HStack {
                Text(L("长期目标")).font(compact ? .headline : .title2.bold())
                Spacer()
                Text(L("%@ 个目标", String(store.items.count))).font(.caption).foregroundStyle(.secondary)
                Button { adding.toggle() } label: { Image(systemName: adding ? "minus" : "plus") }
                    .help(L("添加目标")).accessibilityLabel(L("添加目标")).disabled(!store.canEdit)
            }
            if adding || store.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    fields(goal: $store.draftGoal, status: $store.draftStatus)
                    HStack {
                        Spacer()
                        Button(L("添加目标")) {
                            if store.add(goal: store.draftGoal, status: store.draftStatus) {
                                store.draftGoal = ""; store.draftStatus = ""; adding = false
                            }
                        }.buttonStyle(.borderedProminent)
                            .disabled(store.draftGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.disabled(!store.canEdit)
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
                if !store.canEdit { Button(L("重试")) { store.reload() } }
            }
            if compact {
                ScrollView { rows }.frame(height: min(260, store.items.isEmpty ? 42 : CGFloat(store.items.count) * 90 + (editingID == nil ? 0 : 110)))
                    .scrollBounceBehavior(.basedOnSize)
            } else { ScrollView { rows }.frame(maxHeight: .infinity) }
            Text(L("持续记录目标与当前状态，不会自动清除。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(compact ? 14 : 24)
            .environment(\.locale, language.locale)
            .alert(L("删除这个长期目标？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { item in
                Button(L("取消"), role: .cancel) { deleting = nil }
                Button(L("删除"), role: .destructive) { store.remove(item.id); deleting = nil }
            } message: { item in Text(item.goal) }
            .onChange(of: store.items) { _, items in
                if let editingID, !items.contains(where: { $0.id == editingID }) { self.editingID = nil }
            }
    }

    private func fields(goal: Binding<String>, status: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(L("目标"), text: goal, axis: .vertical)
                .lineLimit(1...3).accessibilityLabel(L("目标"))
            TextField(L("当前状态（可留空）"), text: status, axis: .vertical)
                .lineLimit(2...5).accessibilityLabel(L("当前状态"))
        }.textFieldStyle(.roundedBorder)
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if store.items.isEmpty {
                Text(L("写下你想长期推进的事"))
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 36)
            }
            ForEach(store.items) { item in
                VStack(alignment: .leading, spacing: 7) {
                    if editingID == item.id {
                        fields(goal: $editingGoal, status: $editingStatus)
                        HStack {
                            Spacer()
                            Button(L("取消")) { editingID = nil }
                            Button(L("保存")) {
                                if store.update(item.id, goal: editingGoal, status: editingStatus) { editingID = nil }
                            }.buttonStyle(.borderedProminent)
                                .disabled(editingGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        HStack(alignment: .top) {
                            Text(item.goal).font(.system(size: compact ? 13 : 15, weight: .semibold))
                                .lineLimit(compact ? 2 : nil).help(item.goal).frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                editingGoal = item.goal; editingStatus = item.status; editingID = item.id
                            } label: { Image(systemName: "pencil") }
                                .help(L("编辑")).accessibilityLabel(L("编辑目标：%@", item.goal))
                            Button { deleting = item } label: { Image(systemName: "trash") }
                                .help(L("删除")).accessibilityLabel(L("删除目标：%@", item.goal))
                        }
                        Text(item.status.isEmpty ? L("尚未填写状态") : item.status)
                            .font(.system(size: compact ? 12 : 13)).foregroundStyle(.secondary)
                            .lineLimit(compact ? 3 : nil).help(item.status)
                    }
                }.buttonStyle(.borderless).padding(compact ? 10 : 14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    .disabled(!store.canEdit)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
