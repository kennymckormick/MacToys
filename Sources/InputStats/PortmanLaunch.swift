import Foundation

/// Distribution builds always use their bundled CLI. Source builds keep the
/// existing external CLI / Python fallback for local development.
struct PortmanLaunch {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]

    static func resolve(bundle: URL, home: URL, environment: [String: String],
                        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) throws -> Self {
        var environment = environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        if let test = environment["INPUTSTATS_TEST_HOME"] {
            environment["PORTMAN_HOME"] = URL(fileURLWithPath: test).appendingPathComponent("portman").path
        }
        let bundled = bundle.appendingPathComponent("Contents/MacOS/portman")
        if isExecutable(bundled.path) {
            return Self(executable: bundled, arguments: ["gui", "--no-open", "--json"], environment: environment)
        }
        if FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/Resources/distribution.json").path) {
            throw LaunchError.message(L("内置 Portman 缺失，请重新下载并安装 MacToys。"))
        }
        let candidates = [home.appendingPathComponent(".local/bin/portman").path, "/opt/homebrew/bin/portman", "/usr/local/bin/portman"]
        if let launcher = candidates.first(where: isExecutable) {
            return Self(executable: URL(fileURLWithPath: launcher), arguments: ["gui", "--no-open", "--json"], environment: environment)
        }
        let entry = bundle.appendingPathComponent("Contents/Resources/Portman/portman/_entry.py")
        guard FileManager.default.fileExists(atPath: entry.path) else {
            throw LaunchError.message(L("未找到 Portman，请先安装或检查 ~/.local/bin/portman。"))
        }
        guard let python = ["/Library/Developer/CommandLineTools/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/bin/python3"].first(where: isExecutable) else {
            throw LaunchError.message(L("未找到 Python 3，请安装 Portman 的运行环境。"))
        }
        return Self(executable: URL(fileURLWithPath: python),
                    arguments: ["-I", "-B", entry.path, "portman", "gui", "--no-open", "--json"], environment: environment)
    }

    enum LaunchError: Error, LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
    }
}
