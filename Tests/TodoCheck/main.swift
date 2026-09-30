import Foundation
import Combine

var checks = 0, failures = 0
func check(_ result: Bool, _ name: String) {
    checks += 1
    if !result { failures += 1; print("FAIL: \(name)") }
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("mactoys-todo-tests-\(UUID())")
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
let url = temporary.appendingPathComponent("nested/todos.json")
let store = TodoStore(url: url)
check(store.canEdit && store.items.isEmpty, "Missing file starts empty")
check(!FileManager.default.fileExists(atPath: url.path), "Reading an empty list does not write")
check(!store.add(" \n\t"), "Reject empty tasks")
check(store.add("  买咖啡 ☕️\n "), "Create Unicode task and parent folder")
let id = store.items[0].id
check(store.items[0].title == "买咖啡 ☕️", "Trim outer whitespace only")
check(store.add("买咖啡 ☕️") && store.items[1].id != id, "Equal titles have independent identities")
check(store.rename(id, to: "阅读 Swift 文档\n第二章"), "Edit multiline title")
check(!store.rename(id, to: "   "), "Empty edit keeps task")
check(store.setCompleted(true, id: id) && store.items[0].completedAt != nil, "Complete with timestamp")
let completion = store.items[0].completedAt
check(store.setCompleted(true, id: id) && store.items[0].completedAt == completion, "Repeated completion preserves date")
let reopened = TodoStore(url: url)
check(reopened.items == store.items, "Reopen restores titles, order, IDs, and completion dates")
check(reopened.setCompleted(false, id: id) && reopened.items[0].completedAt == nil, "Restore completed task")
check(reopened.setCompleted(true, id: id), "Complete restored task")
check(reopened.clearCompleted() && reopened.items.count == 1 && reopened.items[0].id != id, "Clear completed keeps unfinished task")
check(reopened.remove(reopened.items[0].id) && TodoStore(url: url).items.isEmpty, "Delete last item persists empty list")
check(!reopened.rename(UUID(), to: "missing") && !reopened.setCompleted(true, id: UUID()), "Stale row edits do not create items")

let damagedURL = temporary.appendingPathComponent("damaged.json")
let damagedData = Data("broken JSON".utf8)
try damagedData.write(to: damagedURL)
let damaged = TodoStore(url: damagedURL)
check(!damaged.canEdit && damaged.errorMessage != nil, "Corrupt file reports an error")
let rejected = !damaged.add("Do not overwrite")
check(rejected && (try? Data(contentsOf: damagedURL)) == damagedData, "Corrupt file is never overwritten")
try Data(contentsOf: url).write(to: damagedURL)
damaged.reload()
check(damaged.canEdit && damaged.errorMessage == nil, "Retry recovers a repaired file")
for (name, json) in [
    ("Future version", #"{"version":2,"items":[]}"#),
    ("Missing version", #"{"items":[]}"#),
    ("Blank title", #"{"version":1,"items":[{"id":"00000000-0000-0000-0000-000000000001","title":"  ","createdAt":0}]}"#),
    ("Duplicate IDs", #"{"version":1,"items":[{"id":"00000000-0000-0000-0000-000000000001","title":"A","createdAt":0},{"id":"00000000-0000-0000-0000-000000000001","title":"B","createdAt":0}]}"#)
] {
    try Data(json.utf8).write(to: damagedURL)
    let invalid = TodoStore(url: damagedURL)
    check(!invalid.canEdit && !invalid.add("replace"), "\(name) is preserved")
}

// Turn the destination into a directory to reliably fail atomic replacement even when run as root.
check(store.add("Keep this task"), "Prepare write failure")
let savedItems = store.items
try FileManager.default.removeItem(at: url)
try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
check(!store.add("Unsaved task") && store.items == savedItems && store.errorMessage != nil, "Failed add does not pretend to save")
check(!store.remove(savedItems[0].id) && store.items == savedItems, "Failed delete retains task")
try FileManager.default.removeItem(at: url)
check(store.add("Retry") && store.errorMessage == nil && TodoStore(url: url).items == store.items, "Retry after write failure succeeds")

let suite = "com.local.mactoys.quick-panel-tests.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
defaults.set("scroll", forKey: "quickTool") // Old remembered tab must not override the new explicit default.
let panel = QuickPanelSettings(defaults: defaults)
check(panel.configuration.tools == [.todo, .input, .colors, .awake] && panel.selection == .todo, "New configuration defaults to Todo")
check(!panel.setIncluded(true, tool: .scroll) && panel.configuration.tools.count == 4, "Reject fifth tool")
panel.select(.colors)
panel.beginPresentation()
check(panel.selection == .todo, "Reopening uses default, not last tab")
panel.beginPresentation(selecting: .colors)
check(panel.selection == .colors, "Color sampler can return to its tab")
panel.setPreferred(.scroll)
check(panel.configuration.preferred == .todo, "Cannot prefer a hidden tab")
check(panel.setIncluded(false, tool: .input) && panel.setIncluded(true, tool: .scroll), "Replace a tool")
panel.setPreferred(.scroll)
panel.beginPresentation()
check(panel.selection == .scroll, "User-selected default opens")
let persisted = QuickPanelSettings(defaults: defaults)
check(persisted.configuration == panel.configuration && persisted.selection == .scroll, "List, order, and default survive restart")
check(panel.setIncluded(false, tool: .scroll) && panel.selection == .todo && panel.configuration.preferred == .todo, "Removing default repairs active and preferred selection")
panel.select(.awake)
check(panel.setIncluded(false, tool: .awake) && panel.selection == .todo, "Removing active tab selects valid default")
check(panel.setIncluded(false, tool: .colors) && !panel.setIncluded(false, tool: .todo), "Keep at least one visible tab")
panel.select(.scroll)
check(panel.selection == .todo, "Cannot select hidden tab")
panel.beginPresentation(selecting: .colors)
check(panel.selection == .todo, "Hidden sampler return falls back to preferred tab")
defaults.set(["tools": ["unknown", "colors", "colors", "scroll", "input", "awake", "todo"], "preferred": "todo"], forKey: "quickPanel.configuration")
let repaired = QuickPanelSettings(defaults: defaults)
check(repaired.configuration.tools == [.colors, .scroll, .input, .awake] && repaired.configuration.preferred == .colors, "Repair unknown, duplicate, excessive, and hidden saved choices")
defaults.set(["tools": [], "preferred": "unknown"], forKey: "quickPanel.configuration")
check(QuickPanelSettings(defaults: defaults).configuration.tools == QuickPanelSettings.defaultTools, "Empty configuration recovers")
defaults.set("invalid", forKey: "quickPanel.configuration")
check(QuickPanelSettings(defaults: defaults).configuration.preferred == .todo, "Malformed configuration recovers")

print("Todo and Quick Panel checks: \(checks - failures)/\(checks) passed")
exit(failures == 0 ? 0 : 1)
