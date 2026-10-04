import Foundation
import Combine
import AppKit

@MainActor
final class CloudSyncStore: ObservableObject {
    enum Confirmation {
        case upload(RemoteBackup?)
        case restore(BackupSnapshot, remoteSHA: String? = nil)
        var snapshot: BackupSnapshot? {
            switch self { case .upload(let remote): return remote?.snapshot; case .restore(let snapshot, _): return snapshot }
        }
        var isRestore: Bool { if case .restore = self { return true }; return false }
    }
    @Published var repositoryDraft = ""
    @Published var tokenDraft = ""
    @Published private(set) var repository: GitHubRepository?
    @Published private(set) var busy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var message: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var automaticSyncEnabled: Bool
    @Published private(set) var lastAutomaticCheck: Date?
    @Published private(set) var nextAutomaticSync: Date?
    @Published private(set) var automaticPause: AutomaticBackupPause?
    @Published var confirmation: Confirmation? { didSet { scheduleAutomaticSync() } }
    let backupsDirectory: URL
    private let defaults: UserDefaults
    private let credentials: SyncCredentialStore
    private let client: GitHubBackupClient
    private let capture: () async throws -> BackupSnapshot
    private let restore: (BackupSnapshot) async throws -> URL
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var knownRemoteSHA: String?
    private var retryAfter: Date?
    private var failures: Int
    private var started = false
    private var timer: Timer?
    private var automaticTask: Task<Void, Never>?
    private var wakeToken: NSObjectProtocol?
    private var clockTokens: [NSObjectProtocol] = []

    init(defaults: UserDefaults, backupsDirectory: URL, credentials: SyncCredentialStore = SyncKeychain(),
         client: GitHubBackupClient = GitHubBackupClient(), capture: @escaping () async throws -> BackupSnapshot,
         restore: @escaping (BackupSnapshot) async throws -> URL,
         now: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .autoupdatingCurrent }) {
        self.defaults = defaults; self.backupsDirectory = backupsDirectory; self.credentials = credentials
        self.client = client; self.capture = capture; self.restore = restore
        self.now = now; self.calendar = calendar
        let saved = defaults.string(forKey: "cloud.repository") ?? ""
        repository = try? GitHubRepository(saved); repositoryDraft = saved
        lastSync = defaults.object(forKey: "cloud.lastSync") as? Date
        automaticSyncEnabled = defaults.object(forKey: "cloud.auto.enabled") as? Bool ?? true
        lastAutomaticCheck = defaults.object(forKey: "cloud.auto.lastSuccess") as? Date
        knownRemoteSHA = defaults.string(forKey: "cloud.remoteSHA")
        retryAfter = defaults.object(forKey: "cloud.auto.retryAfter") as? Date
        failures = max(0, defaults.integer(forKey: "cloud.auto.failures"))
        automaticPause = defaults.string(forKey: "cloud.auto.pause").flatMap(AutomaticBackupPause.init(rawValue:))
        // Initialization is inert. The app starts scheduling only after storage recovery and startup.
    }

    func startAutomaticSync() {
        guard !started else { return }
        started = true
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleAutomaticSync() }
            }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            clockTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleAutomaticSync() }
            })
        }
        scheduleAutomaticSync()
    }

    func stopAutomaticSync() {
        started = false
        timer?.invalidate(); timer = nil; nextAutomaticSync = nil
        automaticTask?.cancel()
        if let wakeToken { NSWorkspace.shared.notificationCenter.removeObserver(wakeToken) }
        wakeToken = nil
        for token in clockTokens { NotificationCenter.default.removeObserver(token) }
        clockTokens.removeAll()
    }

    func setAutomaticSyncEnabled(_ enabled: Bool) {
        guard !busy else { return }
        automaticSyncEnabled = enabled; defaults.set(enabled, forKey: "cloud.auto.enabled")
        scheduleAutomaticSync()
    }

    func retryAutomaticSync() {
        guard !busy else { return }
        clearAutomaticFailure()
        scheduleAutomaticSync()
    }

    private func scheduleAutomaticSync() {
        timer?.invalidate(); timer = nil; nextAutomaticSync = nil
        guard started, automaticSyncEnabled, repository != nil, automaticPause == nil, !busy, confirmation == nil else { return }
        let current = now()
        let date = max(current.addingTimeInterval(15), automaticDueDate(at: current))
        nextAutomaticSync = date
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.automaticTask == nil else { return }
                self.automaticTask = Task { [weak self] in
                    await self?.synchronizeAutomaticallyIfDue()
                    self?.automaticTask = nil
                }
            }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func automaticDueDate(at date: Date) -> Date {
        DailyBackupSchedule.nextAttempt(now: date, lastSuccess: lastAutomaticCheck,
                                       retryAfter: retryAfter, calendar: calendar())
    }

    func synchronizeAutomaticallyIfDue() async {
        guard automaticSyncEnabled, repository != nil, automaticPause == nil else { return }
        // Pending confirmations protect the version the user is reviewing, even while the sheet is idle.
        let current = now()
        guard !busy, confirmation == nil, current >= automaticDueDate(at: current) else { scheduleAutomaticSync(); return }
        busy = true; errorMessage = nil; message = nil
        defer { busy = false; scheduleAutomaticSync() }
        do {
            try Task.checkCancellation()
            let (repository, token) = try connection(allowInteraction: false)
            let remote = try await client.download(repository, token: token)
            try Task.checkCancellation()
            let snapshot = try await capture()
            try Task.checkCancellation()
            if let remote, snapshot.hasSameContents(as: remote.snapshot) {
                // A legacy install or another Mac may have uploaded the same data. No write is needed.
                recordCloudSuccess(sha: remote.sha)
                message = L("云端备份已是最新，无需上传。")
                return
            }
            guard remote?.sha == knownRemoteSHA else { throw GitHubSyncError.conflict }
            let sha = try await client.upload(snapshot, to: repository, token: token, replacing: remote?.sha)
            recordCloudSuccess(sha: sha)
            lastSync = now(); defaults.set(lastSync, forKey: "cloud.lastSync")
            message = L("每日备份已上传到私有仓库。")
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            switch error {
            case GitHubSyncError.conflict: pauseAutomaticSync(.remoteChanged)
            case GitHubSyncError.authentication, GitHubSyncError.missingToken: pauseAutomaticSync(.authorization)
            case GitHubSyncError.publicRepository, GitHubSyncError.missingRepository: pauseAutomaticSync(.repository)
            case is BackupError, GitHubSyncError.badResponse: pauseAutomaticSync(.invalidBackup)
            default:
                failures = min(failures + 1, 5)
                retryAfter = now().addingTimeInterval(DailyBackupSchedule.retryDelay(failures: failures))
                defaults.set(failures, forKey: "cloud.auto.failures")
                defaults.set(retryAfter, forKey: "cloud.auto.retryAfter")
            }
        }
    }

    private func pauseAutomaticSync(_ reason: AutomaticBackupPause) {
        automaticPause = reason; defaults.set(reason.rawValue, forKey: "cloud.auto.pause")
    }

    private func clearAutomaticFailure() {
        automaticPause = nil; retryAfter = nil; failures = 0; errorMessage = nil
        for key in ["cloud.auto.pause", "cloud.auto.retryAfter", "cloud.auto.failures"] { defaults.removeObject(forKey: key) }
    }

    private func recordCloudSuccess(sha: String) {
        knownRemoteSHA = sha; defaults.set(sha, forKey: "cloud.remoteSHA")
        lastAutomaticCheck = now(); defaults.set(lastAutomaticCheck, forKey: "cloud.auto.lastSuccess")
        clearAutomaticFailure()
    }

    private func resetConnectionHistory() {
        knownRemoteSHA = nil; lastAutomaticCheck = nil; lastSync = nil
        for key in ["cloud.remoteSHA", "cloud.auto.lastSuccess", "cloud.lastSync"] { defaults.removeObject(forKey: key) }
        clearAutomaticFailure()
    }

    var authorizationURL: URL {
        var url = URLComponents(string: "https://github.com/settings/personal-access-tokens/new")!
        url.queryItems = [URLQueryItem(name: "name", value: "MacToys Sync"),
                         URLQueryItem(name: "description", value: "Back up MacToys to a private repository"),
                         URLQueryItem(name: "contents", value: "write"), URLQueryItem(name: "expires_in", value: "90")]
        if let target = try? GitHubRepository(repositoryDraft) { url.queryItems?.append(URLQueryItem(name: "target_name", value: target.owner)) }
        return url.url!
    }

    func connect() {
        guard !busy else { return }
        run {
            let target = try GitHubRepository(self.repositoryDraft)
            let token = self.tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            try await self.client.verify(target, token: token)
            try self.credentials.save(token, account: target.credentialAccount)
            if self.repository?.credentialAccount != target.credentialAccount { self.resetConnectionHistory() }
            else { self.clearAutomaticFailure() }
            self.repository = target; self.repositoryDraft = target.fullName; self.tokenDraft = ""
            self.defaults.set(target.fullName, forKey: "cloud.repository")
            self.message = L("已连接私有仓库，可以上传或恢复备份。")
        }
    }

    func disconnect() {
        guard !busy else { return }
        do {
            if let repository { try credentials.remove(account: repository.credentialAccount) }
            repository = nil; tokenDraft = ""; confirmation = nil
            defaults.removeObject(forKey: "cloud.repository"); resetConnectionHistory(); scheduleAutomaticSync()
            errorMessage = nil; message = L("已移除本机授权，云端备份仍保留。")
        } catch { errorMessage = error.localizedDescription }
    }

    func prepareUpload() {
        run {
            let (repository, token) = try self.connection()
            self.confirmation = .upload(try await self.client.download(repository, token: token))
        }
    }

    func prepareDownload() {
        run {
            let (repository, token) = try self.connection()
            guard let remote = try await self.client.download(repository, token: token) else { throw GitHubSyncError.noBackup }
            self.confirmation = .restore(remote.snapshot, remoteSHA: remote.sha)
        }
    }

    func prepareLocalRestore(_ url: URL) {
        run {
            let snapshot = try await Task.detached(priority: .utility) {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= BackupSnapshot.maximumBytes else { throw BackupError.tooLarge }
                return try BackupSnapshot.decode(Data(contentsOf: url))
            }.value
            self.confirmation = .restore(snapshot)
        }
    }

    func confirm(_ action: Confirmation) {
        confirmation = nil
        run {
            switch action {
            case .upload(let remote):
                let (repository, token) = try self.connection()
                let snapshot = try await self.capture()
                let sha = try await self.client.upload(snapshot, to: repository, token: token, replacing: remote?.sha)
                self.recordCloudSuccess(sha: sha)
                self.message = L("备份已上传到私有仓库。")
            case .restore(let snapshot, let remoteSHA):
                _ = try await self.restore(snapshot)
                if let remoteSHA { self.recordCloudSuccess(sha: remoteSHA) }
                self.message = L("已恢复备份。恢复前的本机数据保存在「本地备份」中。")
            }
            let now = self.now(); self.lastSync = now; self.defaults.set(now, forKey: "cloud.lastSync")
        }
    }

    private func connection(allowInteraction: Bool = true) throws -> (GitHubRepository, String) {
        guard let repository, let token = try credentials.read(account: repository.credentialAccount, allowInteraction: allowInteraction), !token.isEmpty else {
            throw GitHubSyncError.missingToken
        }
        return (repository, token)
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; errorMessage = nil; message = nil
        Task {
            defer { busy = false; scheduleAutomaticSync() }
            // Let the progress indicator render before any local disk work.
            await Task.yield()
            do { try await operation() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
