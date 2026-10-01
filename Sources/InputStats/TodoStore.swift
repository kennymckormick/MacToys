import Foundation
import Combine

struct TodoItem: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var completedAt: Date?
    var isCompleted: Bool { completedAt != nil }
}

/// One store is shared by both windows. Only explicit edits write to disk; there is no polling.
final class TodoStore: ObservableObject {
    struct Document: Codable {
        var version = 1
        let items: [TodoItem]
    }
    private enum FileError: Error { case invalidDocument }
    @Published private(set) var items: [TodoItem] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var canEdit = false
    @Published var draft = ""
    let url: URL

    init(url: URL) {
        self.url = url
        reload()
    }

    static func validate(_ items: [TodoItem]) throws {
        guard items.count <= 100_000, Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.title.utf8.count <= 65_536 && $0.createdAt.timeIntervalSince1970.isFinite &&
                  ($0.completedAt?.timeIntervalSince1970.isFinite ?? true) }) else { throw FileError.invalidDocument }
    }

    static func read(from url: URL) throws -> [TodoItem] {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch CocoaError.fileReadNoSuchFile { return [] }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1 else { throw FileError.invalidDocument }
        try validate(document.items)
        return document.items
    }

    func reload() {
        do {
            items = try Self.read(from: url)
            canEdit = true
            errorMessage = nil
        } catch {
            // Leave a damaged or unreadable file untouched; never replace it with an empty list.
            canEdit = false
            errorMessage = L("无法读取待办文件，原文件已保留。请检查数据文件夹后重试。")
        }
    }

    @discardableResult func add(_ title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        return save(items + [TodoItem(id: UUID(), title: title, createdAt: Date())])
    }

    @discardableResult func rename(_ id: UUID, to title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var updated = items
        updated[index].title = title
        return save(updated)
    }

    @discardableResult func setCompleted(_ completed: Bool, id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var updated = items
        if updated[index].isCompleted == completed { return true }
        updated[index].completedAt = completed ? Date() : nil
        return save(updated)
    }

    @discardableResult func remove(_ id: UUID) -> Bool { save(items.filter { $0.id != id }) }
    @discardableResult func clearCompleted() -> Bool { save(items.filter { !$0.isCompleted }) }

    private func save(_ updated: [TodoItem]) -> Bool {
        guard canEdit else { return false }
        if updated == items { return true }
        do {
            try Self.validate(updated)
            let data = try JSONEncoder().encode(Document(items: updated))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            items = updated
            errorMessage = nil
            return true
        } catch {
            // Publish a change only after it is saved; failed edits remain available to retry.
            errorMessage = L("待办未能保存，请检查磁盘空间或文件权限后重试。")
            return false
        }
    }
}
