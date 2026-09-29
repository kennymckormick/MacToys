import Foundation

var failures = 0, checks = 0
func check(_ condition: Bool, _ name: String) {
    checks += 1
    if !condition { failures += 1; print("FAIL: \(name)") }
}
let suite = "com.local.mactoys.language-tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let language = Localization(defaults: defaults)
check(language.language == .system, "First launch follows system")
check(AppLanguage.system.resolved(preferredLanguages: ["zh-Hant-HK", "en"]) == "zh-Hans", "Chinese system")
check(AppLanguage.system.resolved(preferredLanguages: ["en-GB", "zh-Hans"]) == "en", "English system")
check(AppLanguage.system.resolved(preferredLanguages: ["de-DE"]) == "en", "Unsupported system uses English")
check(AppLanguage.system.resolved(preferredLanguages: []) == "en", "Empty language list")
check(AppLanguage.chinese.resolved(preferredLanguages: ["en-US"]) == "zh-Hans", "Explicit choice wins")
language.language = .english
check(language.text("输入统计") == "Input Stats", "English label")
check(language.text("近 %@ 天", arguments: ["7"]) == "7 days", "English interpolation")
check(language.text("Copied 100%") == "Copied 100%", "Unknown text and percent signs are preserved")
check(Localization(defaults: defaults).language == .english, "Persists selection")
language.language = .chinese
check(language.text("输入统计") == "输入统计", "Chinese fallback")
check(language.text("近 %@ 天", arguments: ["7"]) == "近 7 天", "Chinese interpolation")
check(language.locale.identifier == "zh-Hans", "Date and number locale changes")
defaults.set("obsolete", forKey: "app.language")
check(Localization(defaults: defaults).language == .system, "Invalid saved preference recovers")
let han = try! NSRegularExpression(pattern: "[\\x{3400}-\\x{9fff}]")
for (key, value) in Localization.english {
    check(!value.isEmpty && han.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) == nil, "English catalog: \(key)")
    check(key.components(separatedBy: "%@").count == value.components(separatedBy: "%@").count, "Format arguments: \(key)")
}
// Catch forgotten native strings without depending on the developer's language.
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/InputStats")
let pattern = try! NSRegularExpression(pattern: #"L\("((?:[^"\\]|\\.)*)""#)
for file in try! FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
    let source = try! String(contentsOf: file, encoding: .utf8)
    for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
        let key = String(source[Range(match.range(at: 1), in: source)!])
        check(Localization.english[key] != nil, "Catalog contains \(key)")
    }
}
print("Localization checks: \(checks - failures)/\(checks) passed")
exit(failures == 0 ? 0 : 1)
