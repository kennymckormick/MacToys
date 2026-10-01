import Foundation
import Security

struct GitHubRepository: Equatable {
    let owner: String
    let name: String
    var fullName: String { "\(owner)/\(name)" }
    var credentialAccount: String { fullName.lowercased() }
    var webURL: URL { URL(string: "https://github.com/\(fullName)")! }

    init(_ input: String) throws {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("https://") {
            guard let url = URL(string: value), url.host == "github.com", url.user == nil, url.password == nil,
                  url.port == nil, url.query == nil, url.fragment == nil else { throw GitHubSyncError.invalidRepository }
            value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if value.hasSuffix(".git") { value = String(value.dropLast(4)) }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              parts[0].range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{0,38}$"#, options: .regularExpression) != nil,
              parts[1].range(of: #"^[A-Za-z0-9_.-]{1,100}$"#, options: .regularExpression) != nil,
              parts[1] != ".", parts[1] != ".." else { throw GitHubSyncError.invalidRepository }
        owner = parts[0]; name = parts[1]
    }
}

enum GitHubSyncError: Error, LocalizedError {
    case invalidRepository, missingToken, publicRepository, authentication, forbidden, missingRepository
    case conflict, noBackup, badResponse, network, server(Int), keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidRepository: return L("请输入 GitHub 仓库，格式为 用户名/仓库名。")
        case .missingToken: return L("请先粘贴 GitHub 访问令牌并连接仓库。")
        case .publicRepository: return L("这个仓库不是私有仓库。同步已停止，请选择 Private 仓库。")
        case .authentication: return L("GitHub 授权已失效。请断开连接后使用新的令牌授权。")
        case .forbidden: return L("GitHub 拒绝访问或请求过于频繁。请确认令牌具有该仓库的 Contents 读写权限，稍后重试。")
        case .missingRepository: return L("无法访问仓库。请确认仓库已创建，且令牌已获准访问它。")
        case .conflict: return L("云端备份已发生变化，未覆盖它。请重新检查云端备份后再操作。")
        case .noBackup: return L("仓库中还没有 MacToys 备份，请先在原来的机器上上传。")
        case .badResponse: return L("GitHub 返回的备份信息无效，未修改本机数据。")
        case .network: return L("无法连接 GitHub，请检查网络后重试。")
        case .server(let status): return L("GitHub 请求失败（%@），请稍后重试。", String(status))
        case .keychain(let status): return L("无法访问本机钥匙串（%@），授权信息未能保存或读取。", String(status))
        }
    }
}

struct RemoteBackup {
    let sha: String
    let snapshot: BackupSnapshot
}

/// Credentials only travel to api.github.com; redirects and HTTP caching are disabled.
private final class NoGitHubRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class GitHubBackupClient {
    static let fileName = "mactoys-backup.json"
    private let session: URLSession
    private let ownsSession: Bool

    init(session: URLSession? = nil) {
        ownsSession = session == nil
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil; config.httpCookieStorage = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 120
            self.session = URLSession(configuration: config, delegate: NoGitHubRedirects(), delegateQueue: nil)
        }
    }
    deinit { if ownsSession { session.invalidateAndCancel() } }

    func verify(_ repository: GitHubRepository, token: String) async throws {
        struct Info: Decodable { let full_name: String; let visibility: String?; let `private`: Bool; let archived: Bool? }
        let result = try await request("/repos/\(repository.fullName)", token: token)
        guard let info = try? JSONDecoder().decode(Info.self, from: result),
              info.full_name.lowercased() == repository.fullName.lowercased() else { throw GitHubSyncError.badResponse }
        guard info.private, info.visibility == nil || info.visibility == "private" else { throw GitHubSyncError.publicRepository }
        if info.archived == true { throw GitHubSyncError.forbidden }
    }

    func download(_ repository: GitHubRepository, token: String) async throws -> RemoteBackup? {
        try await verify(repository, token: token)
        struct FileInfo: Decodable { let sha: String; let size: Int; let type: String; let path: String }
        let metadata: Data
        do { metadata = try await request("/repos/\(repository.fullName)/contents/\(Self.fileName)", token: token,
                                          accept: "application/vnd.github.object+json") }
        catch GitHubSyncError.missingRepository { return nil }
        guard let file = try? JSONDecoder().decode(FileInfo.self, from: metadata), file.type == "file", file.path == Self.fileName,
              Self.validSHA(file.sha), file.size >= 0 else { throw GitHubSyncError.badResponse }
        guard file.size <= BackupSnapshot.maximumBytes else { throw BackupError.tooLarge }
        // Fetch this exact blob: a simultaneous upload must not mix one revision's content and another's SHA.
        struct Blob: Decodable { let sha: String; let size: Int; let encoding: String; let content: String }
        let data = try await request("/repos/\(repository.fullName)/git/blobs/\(file.sha)", token: token,
                                     maximumBytes: BackupSnapshot.maximumBytes * 2)
        guard let blob = try? JSONDecoder().decode(Blob.self, from: data), blob.sha == file.sha,
              blob.size == file.size, blob.encoding == "base64",
              let content = Data(base64Encoded: blob.content.components(separatedBy: .whitespacesAndNewlines).joined()),
              content.count == file.size else { throw GitHubSyncError.badResponse }
        return RemoteBackup(sha: file.sha, snapshot: try BackupSnapshot.decode(content))
    }

    @discardableResult func upload(_ snapshot: BackupSnapshot, to repository: GitHubRepository,
                                   token: String, replacing sha: String?) async throws -> String {
        let content = try snapshot.encoded()
        if let sha, !Self.validSHA(sha) { throw GitHubSyncError.badResponse }
        try await verify(repository, token: token)
        var payload: [String: Any] = ["message": "Update MacToys backup", "content": content.base64EncodedString()]
        if let sha { payload["sha"] = sha }
        let response = try await request("/repos/\(repository.fullName)/contents/\(Self.fileName)", token: token,
                                         method: "PUT", body: JSONSerialization.data(withJSONObject: payload))
        struct Saved: Decodable { struct Content: Decodable { let sha: String }; let content: Content }
        guard let saved = try? JSONDecoder().decode(Saved.self, from: response), Self.validSHA(saved.content.sha) else {
            throw GitHubSyncError.badResponse
        }
        return saved.content.sha
    }

    private static func validSHA(_ value: String) -> Bool {
        value.range(of: #"^(?:[0-9a-f]{40}|[0-9a-f]{64})$"#, options: .regularExpression) != nil
    }

    private func request(_ path: String, token: String, method: String = "GET", body: Data? = nil,
                         maximumBytes: Int = 2 * 1024 * 1024, accept: String = "application/vnd.github+json") async throws -> Data {
        guard !token.isEmpty, !token.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw GitHubSyncError.missingToken }
        let url = URL(string: "https://api.github.com\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MacToys", forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw GitHubSyncError.network }
        guard let http = response as? HTTPURLResponse else { throw GitHubSyncError.badResponse }
        switch http.statusCode {
        case 200, 201: break
        case 401: throw GitHubSyncError.authentication
        case 403, 429: throw GitHubSyncError.forbidden
        case 404: throw GitHubSyncError.missingRepository
        case 409, 422: throw GitHubSyncError.conflict
        default: throw GitHubSyncError.server(http.statusCode)
        }
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        return data
    }
}
