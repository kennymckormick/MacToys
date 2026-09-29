import Foundation
import Cocoa

/// 调试日志：仅当环境变量 INPUTSTATS_DEBUG=1 时写入 debug.log，用于诊断计数问题。
enum DebugLog {
    static let enabled = ProcessInfo.processInfo.environment["INPUTSTATS_DEBUG"] == "1"

    private static let url: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InputStats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    static func log(_ msg: String) {
        guard enabled else { return }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let line = "\(fmt.string(from: Date())) [\(app)] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
