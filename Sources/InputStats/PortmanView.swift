import SwiftUI
import WebKit

final class PortmanController: ObservableObject {
    @Published var url: URL?
    @Published var error: String?
    @Published var loading = false
    weak var webView: WKWebView?
    private var generation = 0
    func connect() {
        guard !loading else { return }
        generation += 1
        let ticket = generation
        loading = true; error = nil
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try Self.discover() }
            DispatchQueue.main.async {
                guard self.generation == ticket else { return }
                self.loading = false
                switch result {
                case .success(let url): self.url = url
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
    func disconnectView() { generation += 1; loading = false; webView?.stopLoading(); webView = nil; url = nil }
    private static func discover() throws -> URL {
        let launch = try PortmanLaunch.resolve(bundle: Bundle.main.bundleURL,
            home: FileManager.default.homeDirectoryForCurrentUser, environment: ProcessInfo.processInfo.environment)
        let process = Process()
        process.executableURL = launch.executable
        process.arguments = launch.arguments
        process.environment = launch.environment
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); timeout.cancel()
        guard process.terminationStatus == 0,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["url"] as? String, var parts = URLComponents(string: value),
              parts.scheme == "http", parts.host == "127.0.0.1", let port = parts.port, (1...65535).contains(port),
              parts.user == nil, parts.password == nil, parts.fragment?.hasPrefix("token=") == true else {
            throw PortmanError.message(L("无法连接 Portman 后台。请重试，或运行 portman daemon status 查看状态。"))
        }
        parts.queryItems = [URLQueryItem(name: "embedded", value: "1")]
        guard let url = parts.url else { throw PortmanError.message(L("Portman 返回了无效地址。")) }
        return url
    }
    enum PortmanError: Error, LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
    }
}

struct PortmanView: View {
    @ObservedObject private var language = Localization.shared
    @StateObject private var controller = PortmanController()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(L("Portman · 端口转发"), systemImage: "arrow.left.arrow.right").font(.headline)
                Spacer()
                Button(L("SSH 主机")) { controller.webView?.evaluateJavaScript("document.getElementById('nav-hosts').click()") }
                Button(L("命令行")) { controller.webView?.evaluateJavaScript("document.getElementById('nav-help').click()") }
                Button { controller.url = nil; controller.connect() } label: { Image(systemName: "arrow.clockwise") }.help(L("重新连接"))
            }.padding(20)
            Divider()
            if let url = controller.url {
                PortmanWebView(url: url, controller: controller, language: language.code)
            } else if let error = controller.error {
                ContentUnavailableView {
                    Label(L("Portman 暂不可用"), systemImage: "network.slash")
                } description: { Text(error) } actions: { Button(L("重试")) { controller.connect() } }
            } else { Spacer(); ProgressView(L("正在连接本机 Portman…")); Spacer() }
        }
        .onAppear { controller.connect() }
        .onDisappear { controller.disconnectView() }
    }
}

private struct PortmanWebView: NSViewRepresentable {
    let url: URL
    let controller: PortmanController
    let language: String
    func makeCoordinator() -> Coordinator { Coordinator(controller: controller, origin: url, language: language) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let scriptURL = Bundle.main.resourceURL?.appendingPathComponent("Portman/portman/static/i18n.js"),
           let script = try? String(contentsOf: scriptURL, encoding: .utf8) {
            let initialLanguage = language == "zh-Hans" ? "zh-Hans" : "en"
            configuration.userContentController.addUserScript(WKUserScript(
                source: "window.MacToysLanguage = '\(initialLanguage)';\n" + script,
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        controller.webView = view
        view.load(URLRequest(url: url))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.language != language else { return }
        context.coordinator.language = language
        context.coordinator.applyLanguage(to: view)
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil; view.loadHTMLString("", baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: PortmanController
        let origin: URL
        var language: String
        init(controller: PortmanController, origin: URL, language: String) {
            self.controller = controller; self.origin = origin; self.language = language
        }
        func applyLanguage(to view: WKWebView) {
            let code = language == "zh-Hans" ? "zh-Hans" : "en"
            view.evaluateJavaScript("window.MacToysPortman?.setLanguage('\(code)')")
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // A language change during loading must win over the initial user script.
            applyLanguage(to: webView)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = action.request.url else { decisionHandler(.cancel); return }
            let same = target.scheme == origin.scheme && target.host == origin.host && target.port == origin.port
            decisionHandler(same || target.absoluteString == "about:blank" ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            controller.url = nil; controller.error = L("本机 Portman 页面加载失败，请重新连接。")
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            controller.url = nil; controller.error = L("Portman 界面进程已退出，请重新连接。")
        }
    }
}
