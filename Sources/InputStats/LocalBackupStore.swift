import Foundation
import InputStatsCore

/// Called while the input monitor's storage queue is exclusively held.
/// A rollback journal makes an interrupted multi-file restore recoverable on the next launch.
final class LocalBackupStore {
    let directory: URL
    let defaults: UserDefaults
    private let readStatistics: () throws -> [MinuteBucket]
    private let replaceStatistics: ([MinuteBucket]) throws -> Void
    private var todoURL: URL { directory.appendingPathComponent("todos.json") }
    private var noteURL: URL { directory.appendingPathComponent("notes.json") }
    private var goalURL: URL { directory.appendingPathComponent("goals.json") }
    private var journalURL: URL { directory.appendingPathComponent("sync-rollback.json") }
    var requiresRecovery: Bool { FileManager.default.fileExists(atPath: journalURL.path) }
    var backupsDirectory: URL { directory.appendingPathComponent("SyncBackups", isDirectory: true) }

    init(directory: URL, defaults: UserDefaults, readStatistics: @escaping () throws -> [MinuteBucket],
         replaceStatistics: @escaping ([MinuteBucket]) throws -> Void) {
        self.directory = directory; self.defaults = defaults
        self.readStatistics = readStatistics; self.replaceStatistics = replaceStatistics
    }

    func capture() throws -> BackupSnapshot {
        guard !FileManager.default.fileExists(atPath: journalURL.path) else { throw BackupError.recoveryFailed }
        let snapshot = BackupSnapshot(preferences: BackupPreferences(defaults: defaults),
            todos: try TodoStore.read(from: todoURL), goals: try GoalStore.read(from: goalURL), notes: try NotesStore.read(from: noteURL), statistics: try readStatistics())
        try snapshot.validate()
        return snapshot
    }

    @discardableResult func restore(_ snapshot: BackupSnapshot) throws -> URL {
        try snapshot.validate()
        guard !FileManager.default.fileExists(atPath: journalURL.path) else { throw BackupError.recoveryFailed }
        let previous = try capture()
        let saved = backupsDirectory.appendingPathComponent("before-restore-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        let backupData = try previous.encoded()
        try writePrivate(backupData, to: saved)
        try writePrivate(backupData, to: journalURL)
        do {
            try apply(snapshot)
            try FileManager.default.removeItem(at: journalURL)
            return saved
        } catch {
            let originalError = error
            do {
                try apply(previous)
                try FileManager.default.removeItem(at: journalURL)
            } catch { throw BackupError.recoveryFailed }
            throw originalError
        }
    }

    func recoverInterruptedRestore() throws {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
        let previous = try BackupSnapshot.decode(Data(contentsOf: journalURL))
        try apply(previous)
        try FileManager.default.removeItem(at: journalURL)
    }

    private func apply(_ snapshot: BackupSnapshot) throws {
        try snapshot.validate()
        try writePrivate(JSONEncoder().encode(TodoStore.Document(items: snapshot.todos)), to: todoURL)
        try writePrivate(JSONEncoder().encode(GoalStore.Document(items: snapshot.goals)), to: goalURL)
        try writePrivate(JSONEncoder().encode(NotesStore.Document(items: snapshot.notes)), to: noteURL)
        try replaceStatistics(snapshot.statistics)
        try snapshot.preferences.apply(to: defaults)
        // The restore journal must outlive any preferences that have not reached disk yet.
        guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
