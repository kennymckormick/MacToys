import AppKit
import SwiftUI

@main
struct ReleaseCheck {
    @MainActor static func main() throws {
        var count = 0
        func check(_ value: Bool, _ name: String) {
            count += 1
            if !value { fatalError("FAIL: \(name)") }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mactoys-release-\(UUID().uuidString)")
        let suite = "com.local.mactoys.release-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        check(FirstLaunch.needsSetup(directory: root, defaults: defaults), "Fresh install gets setup")
        defaults.set(true, forKey: "setup.seen")
        check(!FirstLaunch.needsSetup(directory: root, defaults: defaults), "Setup is not forced on later launches")
        defaults.removeObject(forKey: "setup.seen")
        for file in ["stats.sqlite", "todos.json", "notes.json", "goals.json"] {
            let url = root.appendingPathComponent(file)
            try Data("preserve".utf8).write(to: url)
            check(!FirstLaunch.needsSetup(directory: root, defaults: defaults), "Existing \(file) skips setup")
            check(try Data(contentsOf: url) == Data("preserve".utf8), "Migration does not rewrite \(file)")
            try FileManager.default.removeItem(at: url)
        }
        let bundle = root.appendingPathComponent("Applications With Spaces/MacToys.app")
        let bundled = bundle.appendingPathComponent("Contents/MacOS/portman").path
        let existing = root.appendingPathComponent(".local/bin/portman").path
        let env = ["PATH": "/bad/python", "PYTHONHOME": "/bad/venv", "INPUTSTATS_TEST_HOME": root.appendingPathComponent("isolated").path]
        let launch = try PortmanLaunch.resolve(bundle: bundle, home: root, environment: env, isExecutable: { [bundled, existing].contains($0) })
        check(launch.executable.path == bundled, "Bundled CLI wins over installed external CLI")
        check(launch.arguments == ["gui", "--no-open", "--json"], "GUI cannot open an external browser")
        check(launch.environment["PORTMAN_HOME"] == root.appendingPathComponent("isolated/portman").path, "Test daemon isolated")
        check(launch.environment["PYTHONDONTWRITEBYTECODE"] == "1", "No writes in signed bundle")
        let fallback = try PortmanLaunch.resolve(bundle: bundle, home: root, environment: [:], isExecutable: { $0 == existing })
        check(fallback.executable.path == existing, "Source build keeps external CLI fallback")
        let resource = bundle.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resource, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: resource.appendingPathComponent("distribution.json"))
        do {
            _ = try PortmanLaunch.resolve(bundle: bundle, home: root, environment: [:], isExecutable: { $0 == existing })
            check(false, "Broken distribution must not silently use external CLI")
        } catch { check(true, "Broken distribution gives a reinstall error") }
        try FileManager.default.removeItem(at: resource.appendingPathComponent("distribution.json"))
        let entry = resource.appendingPathComponent("Portman/portman/_entry.py")
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: entry)
        let source = try PortmanLaunch.resolve(bundle: bundle, home: root, environment: [:], isExecutable: { $0 == "/usr/bin/python3" })
        check(source.arguments.prefix(2) == ["-I", "-B"], "Source runtime isolates Python settings too")
        check(source.arguments[2] == entry.path, "Entry path remains one argument with spaces")

        // Render the real SwiftUI permission guide without showing or activating a window.
        if CommandLine.arguments.count > 1 {
            setenv("INPUTSTATS_TEST_HOME", root.path, 1)
            _ = NSApplication.shared
            let content = Form { SetupChecklist() }.formStyle(.grouped)
                .frame(width: 720, height: 430).environment(\.colorScheme, .light)
            let view = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 430),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
                }
            }
        }
        print("Release setup and runtime checks: \(count)/\(count) passed")
    }
}
