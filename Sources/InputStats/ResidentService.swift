import Foundation
import Darwin

/// A user LaunchAgent supervises a small helper, so disabling supervision never
/// terminates the app or its unsaved editors. No administrator access is needed.
struct ResidentService {
    static let label = "com.local.mactoys.watchdog"
    let app: URL
    let dataDirectory: URL
    var agentsDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    var domain: String { "gui/\(getuid())" }
    var service: String { "\(domain)/\(Self.label)" }
    var plist: URL { agentsDirectory.appendingPathComponent(Self.label + ".plist") }

    var configuration: [String: Any] {
        ["Label": Self.label,
         "ProgramArguments": [app.appendingPathComponent("Contents/MacOS/MacToysWatchdog").path,
                              "--app", app.path, "--data", dataDirectory.path],
         "KeepAlive": true, "RunAtLoad": true, "ThrottleInterval": 5,
         "LimitLoadToSessionType": "Aqua", "ProcessType": "Background",
         "AbandonProcessGroup": true,
         "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null"]
    }

    func setEnabled(_ enabled: Bool) throws {
        let loaded = try launchctl(["print", service]) == 0
        if !enabled {
            if loaded, try launchctl(["bootout", service]) != 0 { throw failure("Could not stop MacToys supervision") }
            if FileManager.default.fileExists(atPath: plist.path) { try FileManager.default.removeItem(at: plist) }
            return
        }
        guard FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/MacToysWatchdog").path) else {
            throw failure("MacToysWatchdog is missing from this app")
        }
        let data = try PropertyListSerialization.data(fromPropertyList: configuration, format: .xml, options: 0)
        let previous = try? Data(contentsOf: plist)
        if loaded, let previous,
           let parsed = try? PropertyListSerialization.propertyList(from: previous, format: nil) as? [String: Any],
           NSDictionary(dictionary: parsed).isEqual(to: configuration) { return }
        if loaded, try launchctl(["bootout", service]) != 0 { throw failure("Could not update MacToys supervision") }
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        try data.write(to: plist, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plist.path)
        // Do not override a user disabling background items in System Settings.
        guard try launchctl(["bootstrap", domain, plist.path]) == 0 else {
            throw failure("Could not start MacToys supervision. Check Login Items & Extensions in System Settings.")
        }
    }

    private func failure(_ text: String) -> NSError {
        NSError(domain: Self.label, code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    private func launchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        try process.run()
        if completed.wait(timeout: .now() + 8) == .timedOut {
            process.terminate()
            throw failure("MacToys supervision update timed out")
        }
        return process.terminationStatus
    }
}
