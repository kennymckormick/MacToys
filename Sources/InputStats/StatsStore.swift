import Foundation
import InputStatsCore

/// Coalesces data changes into five-minute refreshes while the view is visible.
final class StatsStore: ObservableObject {
    @Published var points: [StatPoint] = []
    @Published var mode: Mode = .today { didSet { reload() } }
    @Published var metric: Metric = .chars
    @Published var errorMessage: String?
    @Published var containsLegacyCorrections = false
    private var tokens: [NSObjectProtocol] = []
    private var generation = 0
    private let queue = DispatchQueue(label: "mactoys.charts", qos: .utility)
    private var active = false
    private var needsReload = false
    private var refreshTimer: Timer?
    enum Mode: String, CaseIterable, Identifiable {
        case today = "今天", week = "近 N 天", year = "近一年"
        var id: String { rawValue }
    }
    enum Metric: String, CaseIterable, Identifiable {
        case chars = "字符", words = "单词"
        var id: String { rawValue }
    }
    func activate() {
        guard !active else { return }
        active = true
        tokens.append(NotificationCenter.default.addObserver(forName: .statsDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.needsReload = true
        })
        for name in [Notification.Name.statsDidReset, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reload() })
        }
        let timer = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in
            guard let self, self.needsReload else { return }
            self.reload()
        }
        timer.tolerance = 15
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        reload()
    }
    func deactivate() {
        active = false; generation += 1
        refreshTimer?.invalidate(); refreshTimer = nil
        needsReload = false
        tokens.forEach(NotificationCenter.default.removeObserver); tokens.removeAll()
    }
    deinit {
        refreshTimer?.invalidate()
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
    func reload() {
        guard active else { return }
        // Clear before starting the query so changes arriving during it stay pending.
        needsReload = false
        generation += 1
        let version = generation, mode = mode, days = AppSettings.shared.weekDays
        queue.async { [weak self] in
            let calendar = Calendar.current, now = Date()
            let today = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: today)!
            let count = mode == .today ? 1 : mode == .week ? days : 371
            let start = calendar.date(byAdding: .day, value: -(count - 1), to: today)!
            do {
                let buckets = try Database.shared.buckets(from: Int(start.timeIntervalSince1970), to: Int(end.timeIntervalSince1970))
                let result = mode == .today ? Aggregator.hourly(buckets: buckets, now: now, calendar: calendar) :
                    Aggregator.daily(buckets: buckets, days: count, now: now, calendar: calendar)
                let legacy = buckets.contains { $0.keyboardChars < 0 || $0.keyboardWords < 0 || $0.voiceChars < 0 || $0.voiceWords < 0 }
                DispatchQueue.main.async {
                    guard let self, self.active, self.generation == version else { return }
                    if self.points != result { self.points = result }
                    self.errorMessage = nil; self.containsLegacyCorrections = legacy
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.active, self.generation == version else { return }
                    self.needsReload = true
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
