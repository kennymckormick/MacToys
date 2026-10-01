import AppKit
import WebKit
import SwiftUI

@main
struct EditorChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task {
            do { try await run() }
            catch { print("FAIL: Editor test error: \(error)"); exit(1) }
        }
        app.run()
    }
    @MainActor static func run() async throws {
        var checks = 0, failures = 0
        func check(_ value: Bool, _ name: String) { checks += 1; if !value { failures += 1; print("FAIL: \(name)") } }
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("mactoys-web-notes-\(UUID())")
        defer { try? fm.removeItem(at: folder) }
        let store = NotesStore(url: folder.appendingPathComponent("notes.json"))
        store.add(); let id = store.selection!
        let original = "# 会议记录\n\nQuick **ideas** ☕️\n\n- [ ] Follow up\n- [x] Saved\n\n```swift\nlet answer = 42\n```\n\n| Item | Status |\n| --- | --- |\n| Notes | Ready |\n"
        store.update(id, title: "Quick notes", markdown: original); try store.flush()
        let coordinator = NotesEditor.Coordinator(store: store, note: store.items[0], language: "zh-Hans")
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.userContentController.add(coordinator, name: "notes")
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 430, height: 300), configuration: config)
        coordinator.webView = webView; webView.navigationDelegate = coordinator
        NotesEditorRegistry.shared.add(coordinator)
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        webView.loadFileURL(resources.appendingPathComponent("index.html"), allowingReadAccessTo: resources)
        func js(_ body: String) async throws -> Any? {
            try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page)
        }
        var loaded = false
        for _ in 0..<200 {
            if (try? await js("return !!window.MacToysNotes?.snapshot()")) as? Bool == true { loaded = true; break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        check(loaded, "Offline editor loads in WKWebView")
        guard loaded else { print(store.errorMessage ?? "No ready signal"); exit(1) }
        check(try await js("return document.querySelector('h1')?.textContent") as? String == "会议记录", "Heading renders as an editable heading")
        check(try await js("return document.querySelector('strong')?.textContent") as? String == "ideas", "Bold renders directly")
        check(try await js("return document.querySelectorAll('li[data-item-type=task]').length") as? Int == 2, "GFM task lists render")
        _ = try await js("const task=document.querySelector('li[data-item-type=task]'); task.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:task.getBoundingClientRect().left-8})); return true")
        try await coordinator.flush()
        check(store.items[0].markdown.contains("[x] Follow up"), "Checkbox click updates saved Markdown")
        // Restore exact source for the untouched-open check.
        store.update(id, markdown: original); coordinator.update(note: store.items[0], language: "zh-Hans")
        try await Task.sleep(nanoseconds: 100_000_000)

        check(try await js("return !!document.querySelector('pre code') && !!document.querySelector('table')") as? Bool == true, "Code and tables render")
        check(try await js("return document.querySelector('button').getAttribute('aria-label')") as? String == "标题", "Toolbar is localized")
        try await coordinator.flush(); try store.flush()
        check(store.items[0].markdown == original, "Opening and closing does not normalize saved Markdown")
        _ = try await js("MacToysNotes.select(1, 5); MacToysNotes.command('bold'); return true")
        try await coordinator.flush(); try store.flush()
        check(store.items[0].markdown.contains("**会议记录**"), "Toolbar command changes actual Markdown")
        _ = try await js("MacToysNotes.select(1); MacToysNotes.insert('临时 '); return true")
        try await NotesEditorRegistry.shared.flushAll(); try store.flush()
        check(store.items[0].markdown.contains("临时"), "Native flush receives last typed transaction")
        _ = try await js("document.querySelector('.ProseMirror').dispatchEvent(new KeyboardEvent('keydown', {key:'z', code:'KeyZ', metaKey:true, bubbles:true, cancelable:true})); return true")
        try await coordinator.flush()
        check(!store.items[0].markdown.contains("临时"), "Undo works through the editor keyboard handler")

        _ = try await js("MacToysNotes.setSource(true); const t=document.querySelector('#source'); t.value='# 源码\\n\\n**Text**'; t.dispatchEvent(new Event('input')); return true")
        try await coordinator.flush(); try store.flush()
        check(store.items[0].markdown == "# 源码\n\n**Text**", "Source edits are saved verbatim")
        _ = try await js("MacToysNotes.setSource(false); return true")
        check(try await js("return document.querySelector('h1')?.textContent") as? String == "源码", "Source switches back to editable rich text")
        let old = try await js("return MacToysNotes.snapshot()") as! [String: Any]
        store.update(id, markdown: "# Restored"); try store.flush(); store.reload()
        coordinator.accept(old)
        check(store.items[0].markdown == "# Restored", "Stale editor cannot overwrite restored data")
        coordinator.update(note: store.items[0], language: "en")
        for _ in 0..<100 {
            if (try? await js("return document.querySelector('h1')?.textContent")) as? String == "Restored" { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        coordinator.accept(old)
        check(store.items[0].markdown == "# Restored", "Prior epoch messages are rejected")
        check(try await js("return document.querySelector('button').getAttribute('aria-label')") as? String == "Heading", "English toolbar switches live")
        // Raw HTML is represented as text; remote resources are denied by CSP.
        let malicious = "<script>window.pwned=true</script>\n\n<img src=\"https://example.invalid/tracker\" onerror=\"window.pwned=true\">\n\n![external](https://example.invalid/image.png)"
        store.update(id, markdown: malicious); coordinator.update(note: store.items[0], language: "en")
        try await Task.sleep(nanoseconds: 150_000_000)
        check(try await js("return window.pwned === undefined") as? Bool == true, "Raw HTML cannot execute script")
        check(try await js("return [...document.images].every(image => image.naturalWidth === 0)") as? Bool == true, "External images are not fetched")
        check(try await js("return document.querySelectorAll('iframe,object').length === 0") as? Bool == true, "No embedded active content")
        // Seed a screenshot without global keyboard events or interacting with the user's app.
        store.update(id, markdown: original); coordinator.update(note: store.items[0], language: "en")
        try await Task.sleep(nanoseconds: 150_000_000)
        let image = try await webView.takeSnapshot(configuration: nil)
        if let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]), CommandLine.arguments.count > 2 {
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
        _ = try await js("MacToysNotes.select(1); MacToysNotes.insert('Closing '); return true")
        NotesEditorRegistry.shared.close(coordinator, webView: webView)
        try await NotesEditorRegistry.shared.flushAll()
        check(try NotesStore.read(from: store.url)[0].markdown.contains("Closing"), "Dismantling editor flushes before releasing WebKit")

        final class WeakView { weak var view: WKWebView?; init(_ view: WKWebView) { self.view = view } }
        func openAndClose() async throws -> WeakView {
            let item = store.items[0]
            let bridge = NotesEditor.Coordinator(store: store, note: item, language: "en")
            let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.add(bridge, name: "notes")
            let view = WKWebView(frame: .zero, configuration: configuration)
            bridge.webView = view; view.navigationDelegate = bridge
            NotesEditorRegistry.shared.add(bridge)
            view.loadFileURL(resources.appendingPathComponent("index.html"), allowingReadAccessTo: resources)
            for _ in 0..<200 {
                if (try? await view.callAsyncJavaScript("return !!window.MacToysNotes?.snapshot()", arguments: [:], in: nil, contentWorld: .page)) as? Bool == true { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let weakView = WeakView(view)
            NotesEditorRegistry.shared.close(bridge, webView: view)
            try await NotesEditorRegistry.shared.flushAll()
            return weakView
        }
        for _ in 0..<3 {
            let weakView = try await openAndClose()
            try await Task.sleep(nanoseconds: 300_000_000)
            check(weakView.view == nil, "Closing releases the WKWebView instead of keeping one per visit")
        }
        print("Notes WebKit checks: \(checks - failures)/\(checks) passed")
        exit(failures == 0 ? 0 : 1)
    }
}
