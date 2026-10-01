import Foundation
import InputStatsCore
import InputStatsStorage
import SQLite3

private var checks = 0, failures = 0
private func check(_ value: Bool, _ name: String) {
    checks += 1
    if !value { failures += 1; print("FAIL: \(name)") }
}
private func rejects(_ name: String, _ operation: () throws -> Void) {
    do { try operation(); check(false, name) } catch { check(true, name) }
}
private final class MockGitHub: URLProtocol {
    static var handler: (URLRequest) throws -> (Int, Data) = { _ in throw URLError(.notConnectedToInternet) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
    static func body(of request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { throw URLError(.badServerResponse) }
        stream.open(); defer { stream.close() }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count == 0 { return result }
            guard count > 0 else { throw URLError(.cannotDecodeRawData) }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}
private final class MemoryCredentials: SyncCredentialStore {
    var tokens: [String: String] = [:]
    func read(account: String) throws -> String? { tokens[account] }
    func save(_ token: String, account: String) throws { tokens[account] = token }
    func remove(account: String) throws { tokens.removeValue(forKey: account) }
}

@main
struct CloudSyncChecks {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("mactoys-sync-\(UUID())")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "com.local.mactoys.sync-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? fm.removeItem(at: folder) }
        let db = try StatsDatabase(url: folder.appendingPathComponent("stats.sqlite"))
        let todos = TodoStore(url: folder.appendingPathComponent("todos.json"))
        let notes = NotesStore(url: folder.appendingPathComponent("notes.json"))
        notes.add(); notes.update(notes.items[0].id, title: "会议", markdown: "# Meeting\n\n- [ ] 下一步 ☕️"); try notes.flush()
        let goals = GoalStore(url: folder.appendingPathComponent("goals.json"))
        _ = todos.add("Local task ☕️"); _ = goals.add(goal: "读书", status: "3 / 12\n继续阅读")
        defaults.set("secret-never-exported", forKey: "cloud.token")
        defaults.set("must-stay-local", forKey: "cloud.repository")
        defaults.set(true, forKey: "launchAtLogin")
        defaults.set("zh-Hans", forKey: "app.language")
        defaults.set(["#FF8800"], forKey: "color.favorites")
        let bucket = MinuteBucket(start: 1_700_000_040, keyboardChars: 45, keyboardWords: 8, voiceChars: 10, voiceWords: 2)
        try db.add([bucket])
        let local = LocalBackupStore(directory: folder, defaults: defaults, readStatistics: { try db.buckets() }, replaceStatistics: { try db.replaceAll($0) })
        let original = try local.capture()
        let encoded = try original.encoded()
        check(try BackupSnapshot.decode(encoded) == original, "Snapshot round trip preserves data and preference types")
        let serialized = String(decoding: encoded, as: UTF8.self)
        check(!serialized.contains("secret-never-exported") && !serialized.contains("must-stay-local") && !serialized.contains("launchAtLogin"), "Credentials, repository and login items never leave the Mac")
        var invalid = original; invalid.version = 2
        rejects("Reject future format before restore") { _ = try invalid.encoded() }
        invalid = original; invalid.format = "Unrelated backup"
        rejects("Reject unrelated document") { try invalid.validate() }
        invalid = original; invalid.preferences.weekDays = 99
        rejects("Validate preference ranges") { try invalid.validate() }
        invalid = original; invalid.preferences.quickTools = ["todo", "todo"]
        rejects("Reject duplicate Quick Panel tabs") { try invalid.validate() }
        invalid = original; invalid.preferences.quickDefault = "unknown"
        rejects("Require default to be an included tab") { try invalid.validate() }
        invalid = original; invalid.todos += invalid.todos
        rejects("Reject duplicate Todo IDs") { try invalid.validate() }
        invalid = original; invalid.goals += invalid.goals
        rejects("Reject duplicate Goal IDs") { try invalid.validate() }
        invalid = original; invalid.notes += invalid.notes
        rejects("Reject duplicate Note IDs") { try invalid.validate() }
        invalid = original; invalid.statistics += invalid.statistics
        rejects("Reject duplicate statistic buckets") { try invalid.validate() }
        invalid = original; invalid.statistics[0].keyboardChars = Int.max
        rejects("Reject counters that can overflow aggregates") { try invalid.validate() }
        rejects("Reject corrupted JSON") { _ = try BackupSnapshot.decode(Data("invalid".utf8)) }
        rejects("Reject oversized payload") { _ = try BackupSnapshot.decode(Data(count: BackupSnapshot.maximumBytes + 1)) }
        var remote = original
        remote.notes[0].markdown = "# Remote note\n\n**Saved**"; remote.todos[0].title = "Remote task"; remote.goals[0].status = "5 / 12"
        remote.preferences.language = "en"; remote.preferences.quickTools = ["goals", "todo"]; remote.preferences.quickDefault = "goals"
        remote.statistics[0].keyboardChars = -3 // Preserve old-version deletion corrections.
        let beforeURL = try local.restore(remote)
        let before = try BackupSnapshot.decode(Data(contentsOf: beforeURL))
        check(before.notes == original.notes && before.todos == original.todos && before.statistics == original.statistics, "Create complete local backup before replacement")
        let restored = try local.capture()
        check(restored.notes == remote.notes && restored.todos == remote.todos && restored.goals == remote.goals && restored.statistics == remote.statistics, "Restore tasks, goal status and exact historical counts")
        check(restored.preferences == remote.preferences, "Restore settings including new Goals tab")
        check(defaults.string(forKey: "cloud.token") == "secret-never-exported" && defaults.bool(forKey: "launchAtLogin"), "Restore never replaces local credentials or login settings")
        _ = try local.restore(remote)
        check(try db.buckets() == remote.statistics, "Repeated restores do not double-count statistics")
        check(!fm.fileExists(atPath: folder.appendingPathComponent("sync-rollback.json").path), "Successful restore removes rollback journal")
        let attrs = try fm.attributesOfItem(atPath: beforeURL.path)
        check((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Local backup is owner-readable only")
        try original.encoded().write(to: folder.appendingPathComponent("sync-rollback.json"))
        try local.recoverInterruptedRestore()
        check(try local.capture().todos == original.todos && db.buckets() == original.statistics, "Restart recovers interrupted multi-file restore")
        check(defaults.string(forKey: "app.language") == "zh-Hans", "Recovery includes preferences")

        var failNextWrite = true
        let failing = LocalBackupStore(directory: folder, defaults: defaults, readStatistics: { try db.buckets() }, replaceStatistics: {
            if failNextWrite { failNextWrite = false; throw CocoaError(.fileWriteOutOfSpace) }
            try db.replaceAll($0)
        })
        rejects("Surface storage failure") { _ = try failing.restore(remote) }
        let afterFailure = try local.capture()
        check(afterFailure.notes == original.notes && afterFailure.todos == original.todos && afterFailure.goals == original.goals && afterFailure.statistics == original.statistics, "Rollback restores every data type after a write failure")
        check(afterFailure.preferences == original.preferences, "Rollback preserves preferences")
        check(!fm.fileExists(atPath: folder.appendingPathComponent("sync-rollback.json").path), "Successful rollback clears recovery marker")
        let permanentlyFailing = LocalBackupStore(directory: folder, defaults: defaults, readStatistics: { try db.buckets() }, replaceStatistics: { _ in throw CocoaError(.fileWriteOutOfSpace) })
        rejects("Permanent failure retains recovery marker") { _ = try permanentlyFailing.restore(remote) }
        check(permanentlyFailing.requiresRecovery, "Failed rollback is distinguishable from a rolled-back error")
        rejects("Incomplete restore cannot be uploaded as a good backup") { _ = try permanentlyFailing.capture() }
        rejects("Incomplete restore cannot be overwritten by another restore") { _ = try permanentlyFailing.restore(remote) }
        try local.recoverInterruptedRestore()
        check(try local.capture().notes == original.notes && !local.requiresRecovery, "Recovery restores Notes after a permanent write failure is fixed")

        var connection: OpaquePointer?
        sqlite3_open(folder.appendingPathComponent("stats.sqlite").path, &connection)
        sqlite3_exec(connection, "CREATE TRIGGER fail_restore BEFORE INSERT ON minute_stats BEGIN SELECT RAISE(ABORT, 'test failure'); END;", nil, nil, nil)
        rejects("SQLite restore fails transactionally") { try db.replaceAll(remote.statistics) }
        check(try db.buckets() == original.statistics, "SQLite failure does not clear original history")
        sqlite3_exec(connection, "DROP TRIGGER fail_restore;", nil, nil, nil)
        sqlite3_close(connection)

        let repository = try GitHubRepository("test-owner/mactoys-data")
        check(try GitHubRepository("https://github.com/test-owner/mactoys-data.git") == repository, "Accept GitHub URL and git suffix")
        for input in ["owner/../repo", "https://evil.test/owner/repo", "https://token@github.com/owner/repo", "owner/repo?x=y", "owner/repo/extra", "owner/..", "owner/repo\nX:token"] {
            rejects("Reject invalid repository: \(input.replacingOccurrences(of: "\n", with: " "))") { _ = try GitHubRepository(input) }
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockGitHub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = GitHubBackupClient(session: session)
        let sha = String(repeating: "a", count: 40)
        let newSHA = String(repeating: "b", count: 40)
        let privateInfo = Data(#"{"full_name":"test-owner/mactoys-data","private":true,"visibility":"private","archived":false}"#.utf8)
        let publicInfo = Data(#"{"full_name":"test-owner/mactoys-data","private":false,"visibility":"public"}"#.utf8)
        let remoteBytes = try remote.encoded()
        var paths: [String] = []
        var writes = 0
        var writeSHA: String?
        var uploaded: BackupSnapshot?
        var exists = true, isPrivate = true, writeStatus = 200
        MockGitHub.handler = { request in
            check(request.url?.host == "api.github.com" && request.url?.scheme == "https", "Token destination is GitHub HTTPS only")
            check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-fixture-token", "Authenticate request without including token in URL")
            let path = request.url!.path; paths.append(path)
            if path == "/repos/test-owner/mactoys-data" { return (200, isPrivate ? privateInfo : publicInfo) }
            if request.httpMethod == "PUT" {
                writes += 1
                let body = try JSONSerialization.jsonObject(with: MockGitHub.body(of: request)) as! [String: Any]
                writeSHA = body["sha"] as? String
                uploaded = try BackupSnapshot.decode(Data(base64Encoded: body["content"] as! String)!)
                return (writeStatus, try JSONSerialization.data(withJSONObject: ["content": ["sha": newSHA]]))
            }
            if path.hasSuffix("/contents/mactoys-backup.json") {
                check(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.object+json", "Use media type that supports backups over 1 MB")
                if !exists { return (404, Data()) }
                return (200, try JSONSerialization.data(withJSONObject: ["sha": sha, "size": remoteBytes.count, "type": "file", "path": "mactoys-backup.json"]))
            }
            if path.hasSuffix("/git/blobs/\(sha)") {
                return (200, try JSONSerialization.data(withJSONObject: ["sha": sha, "size": remoteBytes.count, "encoding": "base64", "content": remoteBytes.base64EncodedString()]))
            }
            throw URLError(.badURL)
        }
        let download = try await client.download(repository, token: "test-fixture-token")
        check(download?.snapshot == remote && download?.sha == sha, "Download an exact validated revision")
        check(paths.last?.hasSuffix("/git/blobs/\(sha)") == true, "Fetch content by immutable SHA, not download_url")
        _ = try await client.upload(original, to: repository, token: "test-fixture-token", replacing: sha)
        check(writeSHA == sha && uploaded == original, "Upload carries expected revision and complete snapshot")
        exists = false
        check(try await client.download(repository, token: "test-fixture-token") == nil, "Empty private repository is ready for first backup")
        _ = try await client.upload(original, to: repository, token: "test-fixture-token", replacing: nil)
        check(writeSHA == nil, "First upload creates the file without a fake SHA")
        isPrivate = false; let writesBefore = writes
        do { _ = try await client.upload(original, to: repository, token: "test-fixture-token", replacing: nil); check(false, "Reject public upload") }
        catch GitHubSyncError.publicRepository { check(writes == writesBefore, "No data sent to public repository") }
        isPrivate = true; writeStatus = 409
        do { _ = try await client.upload(original, to: repository, token: "test-fixture-token", replacing: sha); check(false, "Reject concurrent update") }
        catch GitHubSyncError.conflict { check(writes == writesBefore + 1, "Conflict never retries with a newer SHA or forces overwrite") }
        writeStatus = 200

        let credentials = MemoryCredentials()
        defaults.removeObject(forKey: "cloud.repository")
        let store = CloudSyncStore(defaults: defaults, backupsDirectory: local.backupsDirectory, credentials: credentials,
                                   client: client, capture: { try local.capture() }, restore: { try local.restore($0) })
        let priorRequests = paths.count
        check(store.repository == nil && paths.count == priorRequests, "Initializing sync never contacts GitHub")
        store.repositoryDraft = repository.fullName; store.tokenDraft = "test-fixture-token"
        check(store.authorizationURL.query?.contains("contents=write") == true && store.authorizationURL.query?.contains("repo=") != true, "Authorization link requests only content permission")
        store.connect(); await finish(store)
        check(store.repository == repository && store.tokenDraft.isEmpty && credentials.tokens[repository.credentialAccount] == "test-fixture-token", "Connect validates repo, stores credentials separately and clears token field")
        store.prepareUpload(); await finish(store)
        check(store.confirmation != nil && writes == writesBefore + 1, "Preparing upload does not write before confirmation")
        if let action = store.confirmation { store.confirm(action); await finish(store) }
        check(store.errorMessage == nil && store.lastSync != nil && writes == writesBefore + 2, "Confirmed upload finishes and records success")
        exists = true
        store.prepareDownload(); await finish(store)
        check(try local.capture().todos == original.todos, "Downloading never changes local tasks before confirmation")
        if let action = store.confirmation { store.confirm(action); await finish(store) }
        check(try local.capture().todos == remote.todos && store.errorMessage == nil, "Confirmed restore changes data after backup")
        store.disconnect()
        check(store.repository == nil && credentials.tokens.isEmpty && defaults.string(forKey: "cloud.repository") == nil, "Disconnect deletes only local credentials")
        for status in [401, 403, 404, 429, 500] {
            MockGitHub.handler = { _ in (status, Data("do-not-show-secret-token".utf8)) }
            do { try await client.verify(repository, token: "test-fixture-token"); check(false, "HTTP \(status) error") }
            catch { check(!error.localizedDescription.contains("do-not-show-secret-token"), "HTTP \(status) never echoes response bodies") }
        }
        MockGitHub.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { try await client.verify(repository, token: "test-fixture-token"); check(false, "Offline error") }
        catch GitHubSyncError.network { check(true, "Offline error is actionable") }
        print("Cloud Sync checks: \(checks - failures)/\(checks) passed")
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor private static func finish(_ store: CloudSyncStore) async {
        for _ in 0..<1000 {
            if !store.busy { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        check(false, "Sync operation completed before test timeout")
    }
}
