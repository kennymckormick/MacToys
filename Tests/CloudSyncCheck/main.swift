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
    var allowsInteraction: [Bool] = []
    var readError: Error?
    func read(account: String, allowInteraction: Bool) throws -> String? {
        allowsInteraction.append(allowInteraction)
        if let readError { throw readError }
        return tokens[account]
    }
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
        check(BackupPreferences(defaults: defaults).scrollEnabled, "Fresh backup keeps the default-enabled scroll preference")
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
        try await automaticBackups(snapshot: original)
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

    @MainActor private static func automaticBackups(snapshot: BackupSnapshot) async throws {
        let suite = "com.local.mactoys.daily-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let iso = ISO8601DateFormatter()
        func date(_ value: String) -> Date { iso.date(from: value)! }
        var clock = date("2026-10-04T10:00:00Z")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let credentials = MemoryCredentials()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockGitHub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = GitHubBackupClient(session: session)
        var local = snapshot, remote: BackupSnapshot?
        var sha = String(repeating: "a", count: 40)
        var requests = 0, writes = 0, restores = 0, captures = 0
        var offline = false, isPrivate = true, rejectWrite = false, unauthorized = false
        var suspendCapture = false
        var pendingCapture: CheckedContinuation<Void, Never>?
        MockGitHub.handler = { request in
            requests += 1
            if offline { throw URLError(.notConnectedToInternet) }
            if unauthorized { return (401, Data()) }
            let path = request.url!.path
            if path == "/repos/test-owner/daily" {
                return (200, try JSONSerialization.data(withJSONObject: ["full_name": "test-owner/daily", "private": isPrivate]))
            }
            if request.httpMethod == "PUT" {
                writes += 1
                let body = try JSONSerialization.jsonObject(with: MockGitHub.body(of: request)) as! [String: Any]
                if rejectWrite || (body["sha"] as? String) != (remote == nil ? nil : sha) { return (409, Data()) }
                remote = try BackupSnapshot.decode(Data(base64Encoded: body["content"] as! String)!)
                sha = String(format: "%040x", writes)
                return (200, try JSONSerialization.data(withJSONObject: ["content": ["sha": sha]]))
            }
            guard let remote else { return (404, Data()) }
            let data = try remote.encoded()
            if path.hasSuffix("/contents/mactoys-backup.json") {
                return (200, try JSONSerialization.data(withJSONObject: ["sha": sha, "size": data.count, "type": "file", "path": "mactoys-backup.json"]))
            }
            return (200, try JSONSerialization.data(withJSONObject: ["sha": sha, "size": data.count, "encoding": "base64", "content": data.base64EncodedString()]))
        }
        func makeStore() -> CloudSyncStore {
            CloudSyncStore(defaults: defaults, backupsDirectory: folder, credentials: credentials, client: client,
                capture: {
                    captures += 1
                    if suspendCapture { await withCheckedContinuation { pendingCapture = $0 } }
                    var result = local; result.createdAt = clock; return result
                }, restore: { local = $0; restores += 1; return folder }, now: { clock }, calendar: { calendar })
        }
        let store = makeStore()
        await store.synchronizeAutomaticallyIfDue()
        check(requests == 0 && credentials.allowsInteraction.isEmpty, "Unconnected automatic backup never accesses network or credentials")
        store.repositoryDraft = "test-owner/daily"; store.tokenDraft = "test-fixture-token"
        store.connect(); await finish(store)
        check(store.automaticSyncEnabled, "Connected private repositories default to daily backups")
        store.setAutomaticSyncEnabled(false)
        let beforeDisabled = requests
        await store.synchronizeAutomaticallyIfDue()
        check(requests == beforeDisabled && !makeStore().automaticSyncEnabled, "Disabling automatic backup persists and prevents all requests")
        store.setAutomaticSyncEnabled(true)
        await store.synchronizeAutomaticallyIfDue()
        check(writes == 1 && remote?.hasSameContents(as: local) == true && store.lastAutomaticCheck == clock, "First automatic backup creates the snapshot in an empty private repository")
        check(credentials.allowsInteraction.last == false && restores == 0, "Background backups prohibit Keychain prompts and never restore data")
        let firstRequests = requests
        await store.synchronizeAutomaticallyIfDue()
        await makeStore().synchronizeAutomaticallyIfDue()
        check(requests == firstRequests, "Completed daily backup survives relaunch without duplicate requests")
        let relaunched = makeStore()
        relaunched.startAutomaticSync()
        check(relaunched.nextAutomaticSync == date("2026-10-05T09:00:00Z"), "A single timer schedules the next local morning")
        relaunched.stopAutomaticSync()
        check(relaunched.nextAutomaticSync == nil, "Stopping automatic sync clears the scheduled timer")
        clock = date("2026-10-05T08:59:00Z")
        await store.synchronizeAutomaticallyIfDue()
        check(requests == firstRequests, "Daily backup does not run before its deadline")
        clock = date("2026-10-05T09:00:00Z")
        await store.synchronizeAutomaticallyIfDue()
        check(writes == 1 && store.lastAutomaticCheck == clock, "Unchanged data is checked without a new commit or timestamp-only upload")
        clock = date("2026-10-06T15:00:00Z"); local.todos[0].title = "Changed after wake"
        await store.synchronizeAutomaticallyIfDue()
        check(writes == 2 && remote?.todos == local.todos, "A missed daily deadline catches up after wake with current data")

        clock = date("2026-10-07T09:00:00Z"); local.notes[0].markdown = "Pending offline edit"; offline = true
        await store.synchronizeAutomaticallyIfDue()
        let failedRequests = requests
        check(store.automaticPause == nil && store.errorMessage != nil && writes == 2, "Network failure preserves data and remains retryable")
        clock = date("2026-10-07T09:29:59Z")
        await makeStore().synchronizeAutomaticallyIfDue()
        check(requests == failedRequests, "Retry cooldown persists across relaunch")
        offline = false; clock = date("2026-10-07T09:30:00Z")
        await store.synchronizeAutomaticallyIfDue()
        check(writes == 3 && store.errorMessage == nil && remote?.notes == local.notes, "Delayed retry uploads successfully and clears the error")
        check(DailyBackupSchedule.retryDelay(failures: 1) == 1800 && DailyBackupSchedule.retryDelay(failures: 2) == 3600 && DailyBackupSchedule.retryDelay(failures: 100) == 21600, "Repeated failures back off from 30 minutes to a six-hour ceiling")

        clock = date("2026-10-08T09:00:00Z"); credentials.readError = GitHubSyncError.keychain(-25308)
        let beforeLocked = requests
        await store.synchronizeAutomaticallyIfDue()
        check(requests == beforeLocked && store.automaticPause == nil && credentials.allowsInteraction.last == false, "Locked Keychain defers backup without prompting or contacting GitHub")
        credentials.readError = nil; clock = date("2026-10-08T09:30:00Z")
        await store.synchronizeAutomaticallyIfDue()
        check(store.lastAutomaticCheck == clock && store.errorMessage == nil, "Unlocked Keychain recovers on the next retry")

        clock = date("2026-10-09T09:00:00Z")
        remote!.todos[0].title = "Edit from another Mac"; sha = String(repeating: "c", count: 40)
        await store.synchronizeAutomaticallyIfDue()
        check(store.automaticPause == .remoteChanged && writes == 3 && restores == 0 && local.todos[0].title == "Changed after wake", "Another Mac's changes pause automatic uploads without overwriting either side")
        let beforeReview = requests
        await makeStore().synchronizeAutomaticallyIfDue()
        check(requests == beforeReview, "Conflict pause survives restart without background polling")
        store.prepareDownload(); await finish(store)
        if let action = store.confirmation { store.confirm(action); await finish(store) }
        check(store.automaticPause == nil && restores == 1 && local.todos == remote?.todos, "Explicit cloud restore establishes a reviewed revision and resumes daily backups")
        clock = date("2026-10-10T09:00:00Z"); local.todos[0].title = "Edit after reviewed restore"
        await store.synchronizeAutomaticallyIfDue()
        check(writes == 4 && store.automaticPause == nil && remote?.todos == local.todos, "Daily backups continue from the explicitly restored cloud revision")

        clock = date("2026-10-11T09:00:00Z"); local.todos[0].title = "Concurrent edit"; rejectWrite = true
        await store.synchronizeAutomaticallyIfDue()
        check(writes == 5 && store.automaticPause == .remoteChanged, "A GitHub write conflict is never force-retried")
        rejectWrite = false
        store.prepareUpload(); await finish(store)
        if let action = store.confirmation { store.confirm(action); await finish(store) }
        check(writes == 6 && store.automaticPause == nil && remote?.todos == local.todos, "An explicitly reviewed upload clears the conflict pause")
        clock = date("2026-10-12T09:00:00Z"); isPrivate = false
        let beforePublic = captures
        await store.synchronizeAutomaticallyIfDue()
        check(store.automaticPause == .repository && writes == 6 && captures == beforePublic, "A repository changed to public is rejected before reading local data or uploading")
        isPrivate = true; store.retryAutomaticSync()
        await store.synchronizeAutomaticallyIfDue()
        check(store.automaticPause == nil && store.lastAutomaticCheck == clock, "Retry works after private repository access is restored")
        clock = date("2026-10-13T09:00:00Z"); unauthorized = true
        await store.synchronizeAutomaticallyIfDue()
        check(store.automaticPause == .authorization, "Expired authorization stops automatic requests until user action")
        unauthorized = false; store.tokenDraft = "test-fixture-token"
        store.connect(); await finish(store)
        await store.synchronizeAutomaticallyIfDue()
        check(store.automaticPause == nil && store.lastAutomaticCheck == clock, "Reconnecting renews authorization without losing the reviewed revision")

        clock = date("2026-10-14T09:00:00Z"); local.todos[0].title = "Local edit awaiting confirmation"
        store.startAutomaticSync()
        store.prepareUpload(); await finish(store)
        let beforeSheet = requests
        await store.synchronizeAutomaticallyIfDue()
        check(requests == beforeSheet && store.confirmation != nil, "A pending manual confirmation prevents automatic work")
        check(store.nextAutomaticSync == nil, "A sheet awaiting user input does not poll on a short timer")
        store.confirmation = nil
        check(store.nextAutomaticSync == clock.addingTimeInterval(15), "Dismissing the confirmation reschedules an overdue backup")
        store.stopAutomaticSync()
        suspendCapture = true
        let pending = Task { await store.synchronizeAutomaticallyIfDue() }
        for _ in 0..<1000 {
            if pendingCapture != nil { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        check(pendingCapture != nil, "Automatic capture can yield without holding up the app")
        let duringCapture = requests
        await store.synchronizeAutomaticallyIfDue()
        check(requests == duringCapture, "Concurrent triggers do not start duplicate uploads")
        pending.cancel(); pendingCapture?.resume(); pendingCapture = nil
        await pending.value
        check(writes == 6 && !store.busy && store.automaticPause == nil, "Cancellation before upload sends no data and releases the busy state")
        suspendCapture = false

        let deletedBackup = remote; remote = nil
        await store.synchronizeAutomaticallyIfDue()
        check(store.automaticPause == .remoteChanged && writes == 6, "Deleting the reviewed remote backup is a conflict, not permission to recreate it silently")
        remote = deletedBackup; store.retryAutomaticSync()

        defaults.removeObject(forKey: "cloud.remoteSHA"); defaults.removeObject(forKey: "cloud.auto.lastSuccess")
        let legacy = makeStore()
        await legacy.synchronizeAutomaticallyIfDue()
        check(legacy.automaticPause == .remoteChanged && writes == 6, "An existing cloud backup without a reviewed baseline is never overwritten on upgrade or a new Mac")
        local = remote!; legacy.retryAutomaticSync()
        await legacy.synchronizeAutomaticallyIfDue()
        check(legacy.automaticPause == nil && writes == 6 && defaults.string(forKey: "cloud.remoteSHA") == sha, "Identical local and remote data safely establish a baseline without a commit")
        legacy.startAutomaticSync(); legacy.disconnect()
        check(legacy.repository == nil && legacy.nextAutomaticSync == nil && defaults.string(forKey: "cloud.remoteSHA") == nil, "Disconnect cancels scheduling and removes revision history")
        let afterDisconnect = requests
        await legacy.synchronizeAutomaticallyIfDue()
        check(requests == afterDisconnect && credentials.tokens.isEmpty, "Disconnected backup cannot use stale credentials")
        legacy.stopAutomaticSync()

        var newYork = Calendar(identifier: .gregorian); newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let spring = date("2026-03-07T14:00:00Z")
        let fall = date("2026-10-31T13:00:00Z")
        check(DailyBackupSchedule.nextAttempt(now: spring, lastSuccess: spring, retryAfter: nil, calendar: newYork) == date("2026-03-08T13:00:00Z"), "Spring daylight saving keeps the backup at 09:00 local time")
        check(DailyBackupSchedule.nextAttempt(now: fall, lastSuccess: fall, retryAfter: nil, calendar: newYork) == date("2026-11-01T14:00:00Z"), "Fall daylight saving keeps the backup at 09:00 local time")
        check(DailyBackupSchedule.nextAttempt(now: spring, lastSuccess: fall, retryAfter: nil, calendar: newYork) == spring, "Moving the clock backward does not suspend backups for months")
    }
}
