import SwiftUI
import WebKit

@MainActor
final class NotesEditorRegistry {
    static let shared = NotesEditorRegistry()
    private let editors = NSHashTable<NotesEditor.Coordinator>.weakObjects()
    // Retain dismantling editors only until their last IPC/save completes.
    private var closing: [UUID: Task<Void, Never>] = [:]
    func add(_ editor: NotesEditor.Coordinator) { editors.add(editor) }
    func flushAll() async throws {
        for task in closing.values { await task.value }
        for editor in editors.allObjects { try await editor.flush() }
    }
    func close(_ editor: NotesEditor.Coordinator, webView: WKWebView) {
        editors.remove(editor)
        let id = UUID()
        closing[id] = Task {
            defer { webView.configuration.userContentController.removeScriptMessageHandler(forName: "notes"); closing[id] = nil }
            do { try await editor.flush(); try editor.store.flush() }
            catch { editor.store.editorFailed() }
        }
    }
}

struct NotesEditor: NSViewRepresentable {
    @ObservedObject var store: NotesStore
    let note: NoteItem
    let language: String
    func makeCoordinator() -> Coordinator { Coordinator(store: store, note: note, language: language) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "notes")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        NotesEditorRegistry.shared.add(context.coordinator)
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("NotesEditor", isDirectory: true),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.html").path) {
            webView.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        } else { store.editorFailed() }
        return webView
    }
    func updateNSView(_ webView: WKWebView, context: Context) { context.coordinator.update(note: note, language: language) }
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) { NotesEditorRegistry.shared.close(coordinator, webView: webView) }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let store: NotesStore
        weak var webView: WKWebView?
        private var id: UUID
        private var lastMarkdown: String
        private var epoch = UUID().uuidString
        private var generation: UUID
        private var language: String
        private var ready = false
        init(store: NotesStore, note: NoteItem, language: String) {
            self.store = store; id = note.id; lastMarkdown = note.markdown; generation = store.generation; self.language = language
        }
        func update(note: NoteItem, language: String) {
            guard id != note.id || lastMarkdown != note.markdown || generation != store.generation || self.language != language else { return }
            id = note.id; lastMarkdown = note.markdown; generation = store.generation; self.language = language
            epoch = UUID().uuidString
            if ready { load() }
        }
        private func load() {
            guard let webView else { return }
            let payload: [String: Any] = ["id": id.uuidString, "epoch": epoch, "markdown": lastMarkdown, "language": language]
            Task { [weak self, weak webView] in
                do {
                    guard let webView else { return }
                    let success = try await webView.callAsyncJavaScript("return await window.MacToysNotes.load(payload)", arguments: ["payload": payload], in: nil, contentWorld: .page)
                    if success as? Bool != true { self?.store.editorFailed() }
                } catch { self?.store.editorFailed() }
            }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready": ready = true; load()
            case "change": accept(body)
            case "error": store.editorFailed()
            case "link":
                if let string = body["url"] as? String, let url = URL(string: string), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            default: break
            }
        }
        func accept(_ body: [String: Any]) {
            guard body["epoch"] as? String == epoch, body["id"] as? String == id.uuidString,
                  generation == store.generation, let markdown = body["markdown"] as? String,
                  let item = store.items.first(where: { $0.id == id }), item.markdown == lastMarkdown else { return }
            if store.update(id, markdown: markdown) { lastMarkdown = markdown }
        }
        func flush() async throws {
            guard ready, let webView else { return }
            let value = try await webView.callAsyncJavaScript("return window.MacToysNotes.snapshot()", arguments: [:], in: nil, contentWorld: .page)
            if let body = value as? [String: Any] { accept(body) }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false; store.editorFailed()
            // The latest received transaction is in NotesStore, even if its disk save was pending.
            try? store.flush()
            webView.reload()
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            let isInitialPage = navigationAction.navigationType == .other && url?.isFileURL == true && url?.lastPathComponent == "index.html"
            decisionHandler(isInitialPage ? .allow : .cancel)
        }
    }
}
