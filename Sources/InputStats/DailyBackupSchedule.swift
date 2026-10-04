import Foundation

enum DailyBackupSchedule {
    /// First backup is due immediately; subsequent backups are due at 09:00 local time.
    /// Calendar arithmetic keeps the local time stable across daylight-saving changes.
    static func nextAttempt(now: Date, lastSuccess: Date?, retryAfter: Date?, calendar: Calendar) -> Date {
        var due = now
        if let lastSuccess, lastSuccess <= now,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastSuccess)),
           let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
            due = max(now, morning)
        }
        return max(due, retryAfter ?? due)
    }

    static func retryDelay(failures: Int) -> TimeInterval {
        min(6 * 60 * 60, 30 * 60 * pow(2, Double(min(4, max(0, failures - 1)))))
    }
}

enum AutomaticBackupPause: String {
    case remoteChanged, authorization, repository, invalidBackup

    var message: String {
        switch self {
        case .remoteChanged:
            return L("云端备份已变化或尚未确认。请先手动上传或从云端恢复，确认要保留的数据。")
        case .authorization:
            return L("自动备份已暂停，请重新连接 GitHub 授权。")
        case .repository:
            return L("自动备份已暂停，请检查私有仓库和访问权限后重试。")
        case .invalidBackup:
            return L("自动备份已暂停，请检查备份内容或升级应用后重试。")
        }
    }
}
