import Foundation
import Combine

struct LongTermGoal: Codable, Identifiable, Equatable {
    let id: UUID
    var goal: String
    var status: String
    let createdAt: Date
    var updatedAt: Date
}

final class GoalStore: ObservableObject {
    struct Document: Codable { var version = 1; let items: [LongTermGoal] }
    @Published private(set) var items: [LongTermGoal] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var canEdit = false
    @Published var draftGoal = ""
    @Published var draftStatus = ""
    let url: URL

    init(url: URL) { self.url = url; reload() }

    static func validate(_ items: [LongTermGoal]) throws {
        guard items.count <= 10_000, Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ !$0.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.goal.utf8.count <= 16_384 && $0.status.utf8.count <= 65_536 &&
                  $0.createdAt.timeIntervalSince1970.isFinite && $0.updatedAt.timeIntervalSince1970.isFinite }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    static func read(from url: URL) throws -> [LongTermGoal] {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch CocoaError.fileReadNoSuchFile { return [] }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        try validate(document.items)
        return document.items
    }

    func reload() {
        do { items = try Self.read(from: url); canEdit = true; errorMessage = nil }
        catch { canEdit = false; errorMessage = L("无法读取长期目标，原文件已保留。请检查数据文件夹后重试。") }
    }

    @discardableResult func add(goal: String, status: String) -> Bool {
        let now = Date()
        return save(items + [LongTermGoal(id: UUID(), goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: now, updatedAt: now)])
    }

    @discardableResult func update(_ id: UUID, goal: String, status: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var updated = items
        updated[index].goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        updated[index].status = status.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated == items { return true }
        updated[index].updatedAt = Date()
        return save(updated)
    }

    @discardableResult func remove(_ id: UUID) -> Bool { save(items.filter { $0.id != id }) }

    private func save(_ updated: [LongTermGoal]) -> Bool {
        guard canEdit else { return false }
        do { try Self.validate(updated) }
        catch { errorMessage = L("请输入目标，并将目标和状态控制在合理长度内。"); return false }
        if updated == items { return true }
        do {
            let data = try JSONEncoder().encode(Document(items: updated))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            items = updated; errorMessage = nil
            return true
        } catch {
            errorMessage = L("长期目标未能保存，请检查磁盘空间或文件权限后重试。")
            return false
        }
    }
}
