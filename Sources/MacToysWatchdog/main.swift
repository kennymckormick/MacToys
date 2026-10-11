import Foundation
import Darwin

// Observe process exit notifications instead of repeatedly spawning a polling
// command. A slow fallback catches a PID disappearing before observation starts.
final class Watchdog {
    let app: URL
    let directory: URL
    let executable: URL
    private var observed: DispatchSourceProcess?
    private var observedPID: pid_t?
    private var child: Process?
    private var retry: DispatchWorkItem?
    private var fallback: DispatchSourceTimer?
    private var lastLaunch = -Double.infinity
    private var failures = 0

    init(app: URL, directory: URL) {
        self.app = app.resolvingSymlinksInPath(); self.directory = directory
        executable = self.app.appendingPathComponent("Contents/MacOS/InputStats")
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(3))
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume(); fallback = timer
        check()
    }

    private func matches(_ pid: pid_t) -> Bool {
        guard pid > 1 else { return false }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
        return URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath() == executable
    }

    private func currentPID() -> pid_t? {
        if let child, child.isRunning, matches(child.processIdentifier) { return child.processIdentifier }
        guard let text = try? String(contentsOf: directory.appendingPathComponent("app.pid")),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), matches(pid) else { return nil }
        return pid
    }

    private func check() {
        guard retry == nil else { return }
        if let pid = currentPID() { watch(pid); return }
        observed?.cancel(); observed = nil; observedPID = nil
        // Another instance may hold the lock while starting/saving, before its
        // PID file is ready. Never race its data or force-kill that instance.
        let fd = Darwin.open(directory.appendingPathComponent("app.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { schedule(after: 5); return }
        let available = flock(fd, LOCK_EX | LOCK_NB) == 0
        if available { flock(fd, LOCK_UN) }
        Darwin.close(fd)
        guard available else { schedule(after: 2); return }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { schedule(after: 30); return }
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - lastLaunch >= 60 { failures = 0 }
        let delay = min(60.0, 2.0 * pow(2, Double(min(failures, 5))))
        if uptime - lastLaunch < delay { schedule(after: delay - (uptime - lastLaunch)); return }
        let process = Process()
        process.executableURL = executable; process.arguments = ["--background"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] ended in DispatchQueue.main.async {
            guard self?.child?.processIdentifier == ended.processIdentifier else { return }
            self?.child = nil; self?.check()
        } }
        lastLaunch = uptime; failures += 1
        do {
            try process.run(); child = process
            log("Started app pid=\(process.processIdentifier)")
            watch(process.processIdentifier)
        } catch {
            log("App launch failed: \(error.localizedDescription)"); schedule(after: delay)
        }
    }

    private func watch(_ pid: pid_t) {
        guard pid != observedPID else { return }
        observed?.cancel()
        observedPID = pid
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, self.observedPID == pid else { return }
            self.observed?.cancel(); self.observed = nil; self.observedPID = nil
            self.log("App exited pid=\(pid)")
            self.schedule(after: 2)
        }
        source.resume(); observed = source
    }

    private func schedule(after seconds: Double) {
        guard retry == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.retry = nil; self?.check() }
        retry = work; DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, seconds), execute: work)
    }

    private func log(_ message: String) {
        let file = directory.appendingPathComponent("watchdog.log")
        if ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 1_048_576 {
            let old = file.appendingPathExtension("1")
            try? FileManager.default.removeItem(at: old); try? FileManager.default.moveItem(at: file, to: old)
        }
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8))
        }
    }
}

let args = CommandLine.arguments
guard args.count == 5, args[1] == "--app", args[3] == "--data" else { exit(64) }
let directory = URL(fileURLWithPath: args[4], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
// Protect against a manually started second helper as well as launchd restarts.
let lock = Darwin.open(directory.appendingPathComponent("watchdog.lock").path, O_CREAT | O_RDWR, 0o600)
guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
let watchdog = Watchdog(app: URL(fileURLWithPath: args[2], isDirectory: true), directory: directory)
watchdog.start()
RunLoop.main.run()
