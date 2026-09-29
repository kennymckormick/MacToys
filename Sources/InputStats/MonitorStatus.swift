import Foundation

final class MonitorStatus: ObservableObject {
    static let shared = MonitorStatus()
    @Published var running = false
    @Published var detail = "正在启动"
    @Published var storageError: String?
    @Published var voiceActive = false
    var sampleCount = 0
}

extension Notification.Name {
    static let statsDidChange = Notification.Name("InputStats.statsDidChange")
    static let monitorSettingsDidChange = Notification.Name("InputStats.monitorSettingsDidChange")
}
