import Foundation
import Combine

struct NoteItem: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var markdown: String
    let createdAt: Date
    var updatedAt: Date
}

@MainActor
final class NotesStore: ObservableObject {
    struct Document: Codable { var version = 1; let items: [NoteItem] }
    static let maximumNoteBytes = 512 * 1024
    @Published private(set) var items: [NoteItem] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var canEdit = false
    @Published private(set) var dirty = false
    @Published private(set) var generation = UUID()
    @Published var selection: UUID?
    let url: URL
    private var pendingSave: DispatchWorkItem?

    init(url: URL) { self.url = url; reload() }
    var selected: NoteItem? { items.first { $0.id == selection } }
    nonisolated static func validate(_ items: [NoteItem]) throws {
        guard items.count <= 1_000, Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ $0.title.utf8.count <= 1024 && $0.markdown.utf8.count <= 512 * 1024 &&
                  $0.createdAt.timeIntervalSince1970.isFinite && $0.updatedAt.timeIntervalSince1970.isFinite }),
              items.reduce(0, { $0 + $1.markdown.utf8.count }) <= 20 * 1024 * 1024 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
    nonisolated static func read(from url: URL) throws -> [NoteItem] {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch CocoaError.fileReadNoSuchFile { return [] }
        guard data.count <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        try validate(document.items)
        return document.items
    }
    func reload() {
        pendingSave?.cancel(); pendingSave = nil
        do {
            let loaded = try Self.read(from: url)
            items = loaded; canEdit = true; dirty = false; errorMessage = nil; generation = UUID()
            if !items.contains(where: { $0.id == selection }) { selection = items.first?.id }
        } catch { canEdit = false; errorMessage = L("无法读取笔记，原文件已保留。请检查数据文件夹后重试。") }
    }
    @discardableResult func add() -> Bool {
        guard canEdit else { return false }
        let now = Date(), note = NoteItem(id: UUID(), title: "", markdown: "", createdAt: now, updatedAt: now)
        guard commit(items + [note]) else { return false }
        selection = note.id; return true
    }
    @discardableResult func update(_ id: UUID, title: String? = nil, markdown: String? = nil) -> Bool {
        guard canEdit, let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var updated = items
        if let title { updated[index].title = title }
        if let markdown { updated[index].markdown = markdown }
        guard updated != items else { return true }
        updated[index].updatedAt = Date()
        do { try Self.validate(updated) }
        catch {
            pendingSave?.cancel(); pendingSave = nil
            items = updated; dirty = true
            errorMessage = L("笔记过大：每篇最多 512 KB，全部笔记最多 20 MB。请先导出整理。")
            return true
        }
        items = updated; dirty = true
        pendingSave?.cancel()
        let task = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { try? self?.flush() } }
        pendingSave = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
        return true
    }
    @discardableResult func remove(_ id: UUID) -> Bool {
        guard canEdit, items.contains(where: { $0.id == id }) else { return false }
        let success = commit(items.filter { $0.id != id })
        if success, selection == id { selection = items.first?.id }
        return success
    }
    func flush() throws {
        pendingSave?.cancel(); pendingSave = nil
        guard dirty else { return }
        do { try write(items); dirty = false; errorMessage = nil }
        catch { errorMessage = L("笔记尚未保存，请检查磁盘空间或文件权限。未保存内容仍保留在编辑器中。"); throw error }
    }
    private func commit(_ updated: [NoteItem]) -> Bool {
        do {
            try write(updated)
            pendingSave?.cancel(); pendingSave = nil
            items = updated; dirty = false; errorMessage = nil
            return true
        } catch { errorMessage = L("笔记未能保存，原有内容保持不变。请检查磁盘空间或文件权限。"); return false }
    }
    private func write(_ updated: [NoteItem]) throws {
        try Self.validate(updated)
        let data = try JSONEncoder().encode(Document(items: updated))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func editorFailed() { errorMessage = L("笔记编辑器暂时不可用。已保存的内容仍在本机，可以导出 Markdown。"); }
}
