import Foundation
import InputStatsCore
import InputStatsStorage

final class Database {
    static let directory: URL = {
        if let test = ProcessInfo.processInfo.environment["INPUTSTATS_TEST_HOME"] {
            return URL(fileURLWithPath: test, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InputStats", isDirectory: true)
    }()
    static let shared = Database()
    private let storage: Result<StatsDatabase, Error>
    struct Recovery: Codable { let id: String; let buckets: [MinuteBucket] }
    private init() {
        storage = Result {
            let db = try StatsDatabase(url: Self.directory.appendingPathComponent("stats.sqlite"))
            let recovery = Self.directory.appendingPathComponent("unsaved-counts.json")
            if FileManager.default.fileExists(atPath: recovery.path) {
                let batch = try JSONDecoder().decode(Recovery.self, from: Data(contentsOf: recovery))
                try db.add(batch.buckets, recoveryID: batch.id)
                try FileManager.default.removeItem(at: recovery)
            }
            return db
        }
    }
    func add(_ buckets: [MinuteBucket]) throws { try storage.get().add(buckets) }
    func buckets(from: Int = 0, to: Int = Int.max) throws -> [MinuteBucket] { try storage.get().buckets(from: from, to: to) }
    func clearAll() throws { try storage.get().clearAll() }
}
