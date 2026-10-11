import AppKit

enum AwakeDuration: Int, CaseIterable, Identifiable {
    case untilOff = 0, minutes15 = 15, minutes30 = 30, hour1 = 60, hours2 = 120, hours4 = 240
    var id: Int { rawValue }
    var seconds: TimeInterval? { self == .untilOff ? nil : TimeInterval(rawValue * 60) }
    var label: String {
        switch self {
        case .untilOff: return L("直到关闭")
        case .minutes15: return L("15 分钟")
        case .minutes30: return L("30 分钟")
        case .hour1: return L("1 小时")
        case .hours2: return L("2 小时")
        case .hours4: return L("4 小时")
        }
    }
}

final class KeepAwakeStore: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var keepDisplayAwake: Bool
    @Published private(set) var duration: AwakeDuration
    @Published private(set) var endsAt: Date?
    @Published private(set) var issue: String?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let makeAssertion: (Bool, TimeInterval?) throws -> AwakeAssertion
    private let canRestoreSession: Bool
    private var assertion: AwakeAssertion?
    private var expiryTimer: Timer?
    private var wakeToken: NSObjectProtocol?
    private var clockToken: NSObjectProtocol?
    private var started = false

    init(defaults: UserDefaults? = nil, now: @escaping () -> Date = Date.init,
         makeAssertion: ((Bool, TimeInterval?) throws -> AwakeAssertion)? = nil) {
        let isTest = ProcessInfo.processInfo.environment["INPUTSTATS_TEST_HOME"] != nil
        let defaults = defaults ?? (isTest ? UserDefaults(suiteName: "com.local.inputstats.tests")! : .standard)
        self.defaults = defaults; self.now = now
        canRestoreSession = !isTest || makeAssertion != nil
        self.makeAssertion = makeAssertion ?? { display, timeout in
            guard !isTest else { throw AwakeError.testMode }
            return try SystemAwakeAssertion(keepDisplayAwake: display, timeout: timeout)
        }
        keepDisplayAwake = defaults.object(forKey: "awake.display") as? Bool ?? true
        duration = AwakeDuration(rawValue: defaults.integer(forKey: "awake.duration")) ?? .untilOff
        // Restore only when start() acquires ownership of system resources.
    }

    func start() {
        guard !started else { return }
        started = true
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refreshDeadline() }
        clockToken = NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange,
            object: nil, queue: .main) { [weak self] _ in self?.refreshDeadline() }
        guard canRestoreSession, defaults.object(forKey: "awake.enabled") as? Bool ?? true else { return }
        if let timestamp = defaults.object(forKey: "awake.endsAt") as? Double {
            guard timestamp.isFinite else { endSession(); return }
            _ = replaceAssertion(display: keepDisplayAwake, deadline: Date(timeIntervalSince1970: timestamp))
        } else {
            _ = replaceAssertion(display: keepDisplayAwake, deadline: duration.seconds.map { now().addingTimeInterval($0) })
        }
    }

    func setEnabled(_ value: Bool) {
        if !value { endSession(); return }
        guard started, !enabled else { return }
        let deadline = duration.seconds.map { now().addingTimeInterval($0) }
        _ = replaceAssertion(display: keepDisplayAwake, deadline: deadline)
    }

    func setDuration(_ value: AwakeDuration) {
        guard value != duration else { return }
        expireIfNeeded()
        if enabled {
            let deadline = value.seconds.map { now().addingTimeInterval($0) }
            guard replaceAssertion(display: keepDisplayAwake, deadline: deadline) else { return }
        }
        duration = value; defaults.set(value.rawValue, forKey: "awake.duration")
    }

    func setKeepDisplayAwake(_ value: Bool) {
        guard value != keepDisplayAwake else { return }
        expireIfNeeded()
        if enabled {
            // Changing the display option must not restart a timed session.
            guard replaceAssertion(display: value, deadline: endsAt) else { return }
        }
        keepDisplayAwake = value; defaults.set(value, forKey: "awake.display")
    }

    @discardableResult
    private func replaceAssertion(display: Bool, deadline: Date?) -> Bool {
        let remaining = deadline.map { $0.timeIntervalSince(now()) }
        if let remaining, remaining <= 0 { endSession(); return false }
        do {
            let replacement = try makeAssertion(display, remaining)
            // Acquire first so failed changes leave the previous session intact.
            assertion?.release(); assertion = replacement
            endsAt = deadline; issue = nil; enabled = true
            defaults.set(true, forKey: "awake.enabled")
            if let deadline { defaults.set(deadline.timeIntervalSince1970, forKey: "awake.endsAt") }
            else { defaults.removeObject(forKey: "awake.endsAt") }
            scheduleExpiry()
            return true
        } catch {
            issue = error.localizedDescription
            return false
        }
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate(); expiryTimer = nil
        guard let endsAt else { return }
        let timer = Timer(fire: endsAt, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.expireIfNeeded()
            if self.enabled { self.scheduleExpiry() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    func expireIfNeeded() {
        if enabled, let endsAt, now() >= endsAt { endSession() }
    }

    func refreshDeadline() {
        guard started, enabled else { return }
        expireIfNeeded()
        guard enabled else { return }
        // Reconcile powerd's relative timeout after sleep or a wall-clock change.
        if !replaceAssertion(display: keepDisplayAwake, deadline: endsAt) {
            let error = issue
            endSession(persist: false); issue = error
        }
    }

    private func endSession(persist: Bool = true) {
        expiryTimer?.invalidate(); expiryTimer = nil
        assertion?.release(); assertion = nil
        endsAt = nil; issue = nil; enabled = false
        if persist {
            defaults.set(false, forKey: "awake.enabled")
            defaults.removeObject(forKey: "awake.endsAt")
        }
    }

    func stop() {
        started = false; endSession(persist: false)
        if let wakeToken { NSWorkspace.shared.notificationCenter.removeObserver(wakeToken) }
        if let clockToken { NotificationCenter.default.removeObserver(clockToken) }
        wakeToken = nil; clockToken = nil
    }
    deinit { stop() }
}
