import Foundation

@main
struct NotesChecks {
    @MainActor static func main() async throws {
        var checks = 0, failures = 0
        func check(_ value: Bool, _ name: String) { checks += 1; if !value { failures += 1; print("FAIL: \(name)") } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mactoys-notes-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("notes.json")
        let store = NotesStore(url: url)
        check(store.canEdit && store.items.isEmpty, "Missing file starts empty")
        check(!FileManager.default.fileExists(atPath: url.path), "Reading does not create a note")
        check(store.add() && store.items.count == 1, "Add and save a note")
        let id = store.items[0].id
        check(store.selection == id && store.items[0].title.isEmpty, "New note is selected")
        let markdown = "# 想法 ☕️\n\n- [ ] Write **Markdown**\n- [x] Done\n\n```swift\nlet n = 1\n```\n"
        check(store.update(id, title: "会议记录", markdown: markdown) && store.dirty, "Edit Unicode title and rich Markdown")
        check(NotesStore(url: url).items[0].markdown.isEmpty, "Edits are debounced")
        try store.flush()
        check(!store.dirty && NotesStore(url: url).items == store.items, "Explicit flush preserves exact Markdown and IDs")
        let updated = store.items[0].updatedAt
        check(store.update(id, markdown: markdown) && store.items[0].updatedAt == updated && !store.dirty, "Unchanged editor snapshot is not a write")
        store.update(id, markdown: "Auto saved")
        try await Task.sleep(nanoseconds: 600_000_000)
        check(!store.dirty && NotesStore(url: url).items[0].markdown == "Auto saved", "Autosave runs after edits")
        check(!store.update(UUID(), markdown: "stale"), "A stale editor cannot recreate a deleted note")
        store.add(); let second = store.selection!
        check(second != id && store.items.count == 2, "Notes have separate IDs")
        check(store.remove(second) && store.selection == id, "Delete selects remaining note")
        let generation = store.generation
        store.reload()
        check(store.generation != generation && store.selection == id, "Reload invalidates old editor sessions and preserves valid selection")
        let saved = try Data(contentsOf: url)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        check(permissions?.intValue == 0o600, "Notes file is owner-only")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        store.update(id, markdown: "Must survive a full disk")
        do { try store.flush(); check(false, "Write failure is surfaced") } catch { check(true, "Write failure is surfaced") }
        check(store.dirty && store.items[0].markdown == "Must survive a full disk" && store.errorMessage != nil, "Unsaved edits remain in memory")
        check(!store.add() && !store.remove(id) && store.items.count == 1, "Failed add/delete keep unsaved notes")
        try FileManager.default.removeItem(at: url)
        try store.flush()
        check(!store.dirty && NotesStore(url: url).items == store.items, "Retry persists unsaved text")
        let oversized = String(repeating: "x", count: NotesStore.maximumNoteBytes + 1)
        check(store.update(id, markdown: oversized) && store.dirty && store.errorMessage != nil, "Oversized text remains recoverable in memory")
        do { try store.flush(); check(false, "Oversize cannot be marked saved") } catch { check(true, "Oversize cannot be marked saved") }
        store.update(id, markdown: markdown); try store.flush()
        check(!store.dirty && store.errorMessage == nil, "Shortening oversized note makes it saveable")
        try Data("damaged".utf8).write(to: url)
        let damaged = NotesStore(url: url)
        check(!damaged.canEdit && !damaged.add() && damaged.errorMessage != nil, "Corrupt file is preserved")
        check(try Data(contentsOf: url) == Data("damaged".utf8), "Corrupt file was not overwritten")
        try saved.write(to: url); damaged.reload()
        check(damaged.canEdit && damaged.items[0].markdown == "Auto saved", "Reload can recover a repaired file")
        for data in [Data(#"{"version":2,"items":[]}"#.utf8), try JSONEncoder().encode(NotesStore.Document(items: [store.items[0], store.items[0]]))] {
            try data.write(to: url)
            check(!NotesStore(url: url).canEdit, "Future or duplicate-ID file is rejected")
        }
        print("Notes checks: \(checks - failures)/\(checks) passed")
        exit(failures == 0 ? 0 : 1)
    }
}
