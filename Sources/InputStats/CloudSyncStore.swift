import Foundation
import Combine

@MainActor
final class CloudSyncStore: ObservableObject {
    enum Confirmation {
        case upload(RemoteBackup?)
        case restore(BackupSnapshot)
        var snapshot: BackupSnapshot? {
            switch self { case .upload(let remote): return remote?.snapshot; case .restore(let snapshot): return snapshot }
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
    @Published var confirmation: Confirmation?
    let backupsDirectory: URL
    private let defaults: UserDefaults
    private let credentials: SyncCredentialStore
    private let client: GitHubBackupClient
    private let capture: () async throws -> BackupSnapshot
    private let restore: (BackupSnapshot) async throws -> URL

    init(defaults: UserDefaults, backupsDirectory: URL, credentials: SyncCredentialStore = SyncKeychain(),
         client: GitHubBackupClient = GitHubBackupClient(), capture: @escaping () async throws -> BackupSnapshot,
         restore: @escaping (BackupSnapshot) async throws -> URL) {
        self.defaults = defaults; self.backupsDirectory = backupsDirectory; self.credentials = credentials
        self.client = client; self.capture = capture; self.restore = restore
        let saved = defaults.string(forKey: "cloud.repository") ?? ""
        repository = try? GitHubRepository(saved); repositoryDraft = saved
        lastSync = defaults.object(forKey: "cloud.lastSync") as? Date
        // No network traffic or Keychain prompts on launch. All operations are explicitly requested.
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
            self.repository = target; self.repositoryDraft = target.fullName; self.tokenDraft = ""
            self.defaults.set(target.fullName, forKey: "cloud.repository")
            self.message = L("已连接私有仓库，可以上传或恢复备份。")
        }
    }

    func disconnect() {
        guard !busy else { return }
        do {
            if let repository { try credentials.remove(account: repository.credentialAccount) }
            repository = nil; tokenDraft = ""; confirmation = nil; lastSync = nil
            defaults.removeObject(forKey: "cloud.repository"); defaults.removeObject(forKey: "cloud.lastSync")
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
            self.confirmation = .restore(remote.snapshot)
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
                _ = try await self.client.upload(snapshot, to: repository, token: token, replacing: remote?.sha)
                self.message = L("备份已上传到私有仓库。")
            case .restore(let snapshot):
                _ = try await self.restore(snapshot)
                self.message = L("已恢复备份。恢复前的本机数据保存在「本地备份」中。")
            }
            let now = Date(); self.lastSync = now; self.defaults.set(now, forKey: "cloud.lastSync")
        }
    }

    private func connection() throws -> (GitHubRepository, String) {
        guard let repository, let token = try credentials.read(account: repository.credentialAccount), !token.isEmpty else {
            throw GitHubSyncError.missingToken
        }
        return (repository, token)
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; errorMessage = nil; message = nil
        Task {
            defer { busy = false }
            // Let the progress indicator render before any local disk work.
            await Task.yield()
            do { try await operation() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
