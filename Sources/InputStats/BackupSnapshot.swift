import Foundation
import InputStatsCore

enum BackupError: Error, LocalizedError {
    case invalid, tooLarge, newerVersion, recoveryFailed
    var errorDescription: String? {
        switch self {
        case .invalid: return L("备份内容无效，未修改本机数据。")
        case .tooLarge: return L("备份超过 25 MB，无法同步。请先导出并整理历史数据。")
        case .newerVersion: return L("备份来自更新版本的 MacToys，请先升级应用。")
        case .recoveryFailed: return L("恢复未能完成。本地备份和恢复记录已保留，请检查磁盘空间与文件权限后重试。")
        }
    }
}

/// Explicitly allowlisted preferences. Credentials, paths, login items and active sessions never enter a backup.
struct BackupPreferences: Codable, Equatable {
    var language: String
    var use24Hour: Bool
    var weekDays: Int
    var paused: Bool
    var includePaste: Bool
    var sourceMode: String
    var quickTools: [String]
    var quickDefault: String
    var colorSelected: String
    var colorHistory: [String]
    var colorFavorites: [String]
    var colorFormat: String
    var colorAutoCopy: Bool
    var colorShowAfterPicking: Bool
    var colorShortcutEnabled: Bool
    var colorShortcut: ColorShortcut
    var scrollEnabled: Bool
    var scrollVertical: Bool
    var scrollHorizontal: Bool
    var awakeDisplay: Bool
    var awakeDuration: Int

    init(defaults d: UserDefaults) {
        language = d.string(forKey: "app.language") ?? "system"
        use24Hour = d.object(forKey: "use24Hour") as? Bool ?? true
        weekDays = d.object(forKey: "weekDays") as? Int ?? 7
        paused = d.bool(forKey: "paused"); includePaste = d.bool(forKey: "includePaste")
        sourceMode = d.string(forKey: "sourceMode") ?? "auto"
        let panel = d.dictionary(forKey: "quickPanel.configuration")
        quickTools = panel?["tools"] as? [String] ?? QuickPanelSettings.defaultTools.map(\.rawValue)
        quickDefault = panel?["preferred"] as? String ?? "todo"
        colorSelected = d.string(forKey: "color.selected") ?? "#3B82F6"
        colorHistory = d.stringArray(forKey: "color.history") ?? []
        colorFavorites = d.stringArray(forKey: "color.favorites") ?? []
        colorFormat = d.string(forKey: "color.format") ?? ColorTextFormat.hex.rawValue
        colorAutoCopy = d.object(forKey: "color.autoCopy") as? Bool ?? true
        colorShowAfterPicking = d.object(forKey: "color.showAfterPicking") as? Bool ?? true
        colorShortcutEnabled = d.object(forKey: "color.shortcutEnabled") as? Bool ?? true
        colorShortcut = d.data(forKey: "color.shortcut").flatMap { try? JSONDecoder().decode(ColorShortcut.self, from: $0) } ?? .standard
        scrollEnabled = d.bool(forKey: "scroll.enabled")
        scrollVertical = d.object(forKey: "scroll.vertical") as? Bool ?? true
        scrollHorizontal = d.bool(forKey: "scroll.horizontal")
        awakeDisplay = d.object(forKey: "awake.display") as? Bool ?? true
        awakeDuration = d.integer(forKey: "awake.duration")
    }

    func validate() throws {
        let toolNames = Set(QuickTool.allCases.map(\.rawValue))
        guard ["system", "en", "zh-Hans"].contains(language), (3...30).contains(weekDays),
              ["auto", "keyboard", "voice"].contains(sourceMode), (1...4).contains(quickTools.count),
              Set(quickTools).count == quickTools.count, Set(quickTools).isSubset(of: toolNames), quickTools.contains(quickDefault),
              ScreenColor(hex: colorSelected) != nil, colorHistory.count <= 24, colorFavorites.count <= 64,
              (colorHistory + colorFavorites).allSatisfy({ ScreenColor(hex: $0) != nil }),
              ColorTextFormat(rawValue: colorFormat) != nil, colorShortcut.isValid,
              [0, 15, 30, 60, 120, 240].contains(awakeDuration) else { throw BackupError.invalid }
    }

    func apply(to d: UserDefaults) throws {
        try validate()
        let values: [String: Any] = [
            "app.language": language, "use24Hour": use24Hour, "weekDays": weekDays, "paused": paused,
            "includePaste": includePaste, "sourceMode": sourceMode,
            "quickPanel.configuration": ["tools": quickTools, "preferred": quickDefault],
            "color.selected": colorSelected, "color.history": colorHistory, "color.favorites": colorFavorites,
            "color.format": colorFormat, "color.autoCopy": colorAutoCopy, "color.showAfterPicking": colorShowAfterPicking,
            "color.shortcutEnabled": colorShortcutEnabled, "color.shortcut": try JSONEncoder().encode(colorShortcut),
            "scroll.enabled": scrollEnabled, "scroll.vertical": scrollVertical, "scroll.horizontal": scrollHorizontal,
            "awake.display": awakeDisplay, "awake.duration": awakeDuration
        ]
        for (key, value) in values { d.set(value, forKey: key) }
    }
}

struct BackupSnapshot: Codable, Equatable {
    static let maximumBytes = 25 * 1024 * 1024
    var format = "MacToys Backup"
    var version = 1
    var createdAt = Date()
    var preferences: BackupPreferences
    var todos: [TodoItem]
    var goals: [LongTermGoal]
    var notes: [NoteItem] = []
    var statistics: [MinuteBucket]

    func validate() throws {
        guard format == "MacToys Backup" else { throw BackupError.invalid }
        if version > 1 { throw BackupError.newerVersion }
        guard version == 1, createdAt.timeIntervalSince1970.isFinite,
              statistics.count <= 250_000, Set(statistics.map(\.start)).count == statistics.count,
              statistics.allSatisfy({ b in
                  b.start >= 0 && b.start <= 32_503_680_000 && b.start % 60 == 0 &&
                  [b.keyboardChars, b.keyboardWords, b.voiceChars, b.voiceWords].allSatisfy { (-1_000_000_000...1_000_000_000).contains($0) }
              }) else { throw BackupError.invalid }
        try preferences.validate()
        do { try TodoStore.validate(todos); try GoalStore.validate(goals); try NotesStore.validate(notes) }
        catch { throw BackupError.invalid }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> BackupSnapshot {
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        let snapshot: BackupSnapshot
        do { snapshot = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw BackupError.invalid }
        try snapshot.validate()
        return snapshot
    }
}
