import Foundation

var checks = 0, failures = 0
func check(_ value: Bool, _ name: String) {
    checks += 1
    if !value { failures += 1; print("FAIL: \(name)") }
}
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mactoys-goals-\(UUID())")
defer { try? FileManager.default.removeItem(at: folder) }
let url = folder.appendingPathComponent("goals.json")
let store = GoalStore(url: url)
check(store.canEdit && store.items.isEmpty, "Missing file is an editable empty list")
check(!FileManager.default.fileExists(atPath: url.path), "No writes until an edit")
check(!store.add(goal: " \n ", status: "Status"), "Reject blank goal")
check(store.add(goal: "  读 12 本书 📚  ", status: "已读 3 本\n正在读第四本"), "Create Unicode goal with multiline status")
let first = store.items[0]
check(first.goal == "读 12 本书 📚" && first.status == "已读 3 本\n正在读第四本", "Preserve both string fields")
check(store.add(goal: "Learn Swift", status: ""), "Empty status is valid")
check(store.update(first.id, goal: "每年读 12 本书", status: "已读 4 本"), "Update both fields")
check(store.items[0].id == first.id && store.items[0].createdAt == first.createdAt, "Editing preserves identity and creation date")
let saved = store.items
check(GoalStore(url: url).items == saved, "Goals persist exactly across launches")
check(!store.update(first.id, goal: "", status: "No"), "Reject blank edited goal")
check(store.items == saved, "Rejected edit leaves saved data intact")
check(!store.update(UUID(), goal: "Missing", status: ""), "Stale edit cannot recreate a deleted goal")
check(store.add(goal: saved[0].goal, status: "Separate"), "Equal goal titles are independent")
check(Set(store.items.map(\.id)).count == 3, "Each item has a distinct identity")
check(store.remove(first.id) && store.items.count == 2, "Delete selected goal")
check(GoalStore(url: url).items == store.items, "Deletion persists")
let original = try Data(contentsOf: url)
for data in [Data("broken".utf8), Data(#"{"version":2,"items":[]}"#.utf8),
             try JSONEncoder().encode(GoalStore.Document(items: [first, first]))] {
    try data.write(to: url)
    let invalid = GoalStore(url: url)
    check(!invalid.canEdit && invalid.errorMessage != nil, "Invalid document blocks editing")
    check(!invalid.add(goal: "Replace", status: "") && (try? Data(contentsOf: url)) == data, "Invalid document is never overwritten")
}
try original.write(to: url)
store.reload()
check(store.canEdit && store.errorMessage == nil, "Reload recovers repaired file")
let beforeFailure = store.items
try FileManager.default.removeItem(at: url)
try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
check(!store.update(beforeFailure[0].id, goal: "Unsaved", status: "No"), "Save failure is reported")
check(store.items == beforeFailure, "Save failure preserves in-memory data")
try FileManager.default.removeItem(at: url)
check(store.add(goal: "Retry", status: "Saved"), "Retry succeeds after disk issue is repaired")
check(!store.add(goal: String(repeating: "a", count: 16_385), status: ""), "Reject oversized goals")
print("Goal checks: \(checks - failures)/\(checks) passed")
exit(failures == 0 ? 0 : 1)
