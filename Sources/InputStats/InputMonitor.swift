import Cocoa
import CoreGraphics
import ApplicationServices
import Carbon
import InputStatsCore

/// Event tap callbacks only enqueue data. AX and persistence run on a serialized utility queue.
final class InputMonitor {
    static let shared = InputMonitor()
    private let queue = DispatchQueue(label: "mactoys.input", qos: .utility)
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var observer: AXObserver?
    private var observedElement: AXUIElement?
    private var observerApp: AXUIElement?
    private var boundPID: pid_t?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var settingsToken: NSObjectProtocol?
    private var sampleWork: DispatchWorkItem?
    private var flushWork: DispatchWorkItem?
    private var voiceWork: DispatchWorkItem?
    private var lastElement: AXUIElement?
    private var counter = InputCounter()
    private var snapshot = AXText.Snapshot(blocked: true)
    private var voice = VoiceSession()
    private var pending: [Int: MinuteBucket] = [:]
    private var lastInput = -Double.infinity
    private var suppressUntil = -Double.infinity
    private var latestEventDate = Date()
    private var cjk = false
    private var paused = false
    private var includePaste = false
    private var sourceMode = "auto"
    private var commitComposition = false
    private var compositionValue: String?
    private var sampleCount = 0
    private var eventCount = 0
    private var stopping = false
    private var fallbackInWord = false
    private var fnDown = false
    private var terminal = false

    private init() {}
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var isVoice: Bool { sourceMode == "voice" || (sourceMode == "auto" && voice.isVoice(now: now)) }

    @discardableResult func start() -> Bool {
        if ProcessInfo.processInfo.environment["INPUTSTATS_TEST_HOME"] != nil && ProcessInfo.processInfo.environment["INPUTSTATS_ENABLE_TEST_MONITOR"] != "1" {
            MonitorStatus.shared.detail = "界面测试 · 监听已关闭"
            return false
        }
        guard tap == nil else { return true }
        updateSettings()
        let trusted = AXIsProcessTrusted()
        if trusted {
            let mask = [CGEventType.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]
                .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
                    return Unmanaged.passUnretained(event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
            if let tap {
                tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        if workspaceTokens.isEmpty {
            let nc = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification] {
                workspaceTokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.bindFrontmost(force: name == NSWorkspace.didWakeNotification)
                })
            }
            workspaceTokens.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.queue.async { self?.flush(); self?.resetFocus() }
            })
            settingsToken = NotificationCenter.default.addObserver(forName: .monitorSettingsDidChange, object: nil, queue: .main) { [weak self] _ in self?.updateSettings() }
        }
        let running = trusted && tap != nil
        MonitorStatus.shared.running = running
        MonitorStatus.shared.detail = running ? "等待输入" : (trusted ? "输入监听未连接，请点重试" : "现有辅助功能授权未生效")
        if running { bindFrontmost() }
        return running
    }

    private func updateSettings() {
        let settings = AppSettings.shared
        let p = settings.paused, paste = settings.includePaste, mode = settings.sourceMode
        queue.async {
            self.paused = p; self.includePaste = paste; self.sourceMode = mode
            self.flush(); self.resetFocus()
            self.publish(p ? "统计已暂停" : "等待输入")
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            queue.async { self.resetFocus() }
            return
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            queue.async { self.commitComposition = true; self.scheduleSample(after: 0.06) }
            return
        }
        if type == .flagsChanged {
            let down = event.flags.contains(.maskSecondaryFn)
            queue.async {
                guard down != self.fnDown else { return }
                self.fnDown = down
                self.voice.change(down: down, now: self.now)
                self.lastInput = self.now; self.latestEventDate = Date()
                self.scheduleSample(after: 0.1)
                self.scheduleVoiceSample()
            }
            return
        }
        guard type == .keyDown else { return }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let shortcut = event.flags.contains(.maskCommand) || event.flags.contains(.maskControl)
        let paste = event.flags.contains(.maskCommand) && code == 9
        let secure = IsSecureEventInputEnabled()
        let inputCJK = InputSource.isCJK()
        var length = 0
        var characters = [UniChar](repeating: 0, count: 64)
        event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
        let text = String(utf16CodeUnits: characters, count: min(length, characters.count))
        let date = Date()
        queue.async {
            guard !self.paused, !self.stopping else { return }
            self.eventCount += 1
            self.cjk = inputCJK; self.latestEventDate = date
            // IMEs may deliver a voice transcript as a synthetic Unicode key or paste.
            let voiceCommit = self.isVoice && (paste || text.unicodeScalars.contains { !$0.isASCII })
            if !voiceCommit {
                self.voice.keyboardActivity()
                self.voiceWork?.cancel(); self.voiceWork = nil
            }
            self.lastInput = self.now
            self.commitComposition = [36, 48, 49, 76].contains(code)
            if shortcut {
                self.fallbackInWord = false
                // Rebase paste / undo / cut / document switches; never read the clipboard.
                if !voiceCommit && (paste ? !self.includePaste : ![0, 8, 1, 3, 12, 4, 46, 13, 36].contains(code)) {
                    self.suppressUntil = self.now + 0.6
                }
                self.scheduleSample(after: 0.12)
                return
            }
            if code == 53 { self.compositionValue = nil; self.suppressUntil = self.now + 0.3 }
            if self.lastElement == nil { self.sample() }
            if secure || self.snapshot.blocked {
                self.resetFocus(); self.publish("安全输入区域 · 已跳过"); return
            }
            if self.snapshot.content == nil, ![51, 117, 53].contains(code) {
                let visible = String(text.filter { ch in
                    !ch.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || $0.properties.isDefaultIgnorableCodePoint || $0.properties.generalCategory == .privateUse }
                })
                // CJK keystrokes are not committed characters. Do not fabricate /3 estimates.
                if !inputCJK, !visible.isEmpty {
                    var delta = InputCounter.Delta()
                    delta.keyboardChars = visible.count
                    for ch in visible {
                        if ch.isLetter || ch.isNumber {
                            if !self.fallbackInWord { delta.keyboardWords += 1 }
                            self.fallbackInWord = true
                        } else { self.fallbackInWord = false }
                    }
                    if self.isVoice {
                        delta.voiceChars = delta.keyboardChars; delta.voiceWords = delta.keyboardWords
                        delta.keyboardChars = 0; delta.keyboardWords = 0
                    }
                    self.record(delta, at: date)
                }
            }
            self.scheduleSample(after: inputCJK && !self.commitComposition ? 0.3 : 0.10)
        }
    }

    private func bindFrontmost(force: Bool = false) {
        guard tap != nil else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let pid = app?.processIdentifier
        let isTerminal = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "org.alacritty"].contains(app?.bundleIdentifier ?? "")
        queue.async {
            if !force && self.boundPID == pid { self.scheduleSample(after: 0.05); return }
            self.boundPID = pid
            self.removeObserver()
            self.terminal = isTerminal
            self.resetFocus()
            AXText.configure()
            if let pid {
                var created: AXObserver?
                if AXObserverCreate(pid, { _, _, notification, refcon in
                    guard let refcon else { return }
                    let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    let focus = (notification as String) == kAXFocusedUIElementChangedNotification
                    monitor.queue.async {
                        if focus { monitor.scheduleSample(after: 0.02) }
                        else {
                            // Rebase unsolicited document changes too, so the next key cannot count an entire loaded document.
                            let active = monitor.now - monitor.lastInput < 3 || monitor.isVoice
                            monitor.scheduleSample(after: active ? 0.1 : 0.4)
                        }
                    }
                }, &created) == .success, let created {
                    self.observer = created
                    let app = AXUIElementCreateApplication(pid)
                    self.observerApp = app
                    AXObserverAddNotification(created, app, kAXFocusedUIElementChangedNotification as CFString,
                                              Unmanaged.passUnretained(self).toOpaque())
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
                }
            }
            self.scheduleSample(after: 0.05)
        }
    }

    private func observe(_ element: AXUIElement?) {
        guard let observer else { return }
        if let previous = observedElement { AXObserverRemoveNotification(observer, previous, kAXValueChangedNotification as CFString) }
        observedElement = element
        if let element {
            AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
        }
    }
    private func removeObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil; observerApp = nil; observedElement = nil
    }
    private func resetFocus() {
        lastElement = nil; snapshot = AXText.Snapshot(blocked: true)
        counter.reset(to: nil); compositionValue = nil; fallbackInWord = false
    }
    private func scheduleSample(after delay: TimeInterval) {
        guard !paused, !stopping, sampleWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.sampleWork = nil; self.sample()
        }
        sampleWork = work; queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func scheduleVoiceSample() {
        voiceWork?.cancel(); voiceWork = nil
        guard isVoice, !paused, !stopping else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.sample(); self.scheduleVoiceSample()
        }
        voiceWork = work; queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func sample() {
        guard !paused, !stopping else { return }
        sampleCount += 1
        let element = AXText.focusedElement()
        let current = AXText.read(element, secureInput: IsSecureEventInputEnabled(), forceFallback: terminal)
        let same = lastElement != nil && element != nil && CFEqual(lastElement!, element!)
        snapshot = current
        if !same {
            lastElement = element; counter.reset(to: current.content); compositionValue = nil
            fallbackInWord = false; observe(element)
        } else if let content = current.content {
            if now < suppressUntil || (now - lastInput >= 3 && !isVoice) {
                counter.reset(to: content); compositionValue = nil
            } else {
                // Some IMEs expose selected romanization as provisional AX text.
                let selectedPinyin = cjk && !commitComposition && !isVoice && !(current.selected ?? "").isEmpty &&
                    (current.selected ?? "").unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) && $0.isASCII || $0 == "'" }
                if selectedPinyin { compositionValue = content }
                else {
                    let delta = counter.step(content: content, dictating: isVoice)
                    record(delta, at: isVoice ? Date() : latestEventDate)
                    if !delta.isZero && isVoice { voice.touch(now: now) }
                    compositionValue = nil
                }
            }
        } else { counter.reset(to: nil) }
        let detail: String
        if current.blocked { detail = current.secure ? "安全输入区域 · 已跳过" : "等待可编辑输入区域" }
        else if current.content != nil { detail = isVoice ? "语音输入 · 按上屏文字统计" : "键盘输入 · 按新增文字统计" }
        else if cjk { detail = "此应用未提供文本 · 中文不估算" }
        else { detail = current.tooLarge ? "长文档 · 按键估算" : "此应用未提供文本 · 按键估算" }
        publish(detail)
    }
    private func record(_ delta: InputCounter.Delta, at date: Date) {
        guard !delta.isZero else { return }
        let minute = Int(date.timeIntervalSince1970) / 60 * 60
        var b = pending[minute] ?? MinuteBucket(start: minute, keyboardChars: 0, keyboardWords: 0, voiceChars: 0, voiceWords: 0)
        b.keyboardChars += delta.keyboardChars; b.keyboardWords += delta.keyboardWords
        b.voiceChars += delta.voiceChars; b.voiceWords += delta.voiceWords
        pending[minute] = b
        scheduleFlush(after: 2)
    }
    private func scheduleFlush(after delay: TimeInterval) {
        guard flushWork == nil, !stopping else { return }
        let work = DispatchWorkItem { [weak self] in self?.flushWork = nil; self?.flush() }
        flushWork = work; queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func flush() {
        guard !pending.isEmpty else { return }
        do {
            try Database.shared.add(Array(pending.values))
            pending.removeAll()
            DispatchQueue.main.async {
                MonitorStatus.shared.storageError = nil
                NotificationCenter.default.post(name: .statsDidChange, object: nil)
            }
        } catch {
            DispatchQueue.main.async { MonitorStatus.shared.storageError = error.localizedDescription }
            scheduleFlush(after: 5)
        }
    }
    private func publish(_ detail: String) {
        if ProcessInfo.processInfo.environment["INPUTSTATS_ENABLE_TEST_MONITOR"] == "1" {
            let diagnostic: [String: Any] = ["events": eventCount, "samples": sampleCount, "status": detail,
                "contentLength": snapshot.content?.count ?? -1, "blocked": snapshot.blocked, "cjk": cjk,
                "lastInputAge": min(9999, now - lastInput), "suppressed": now < suppressUntil]
            if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: Database.directory.appendingPathComponent("monitor-diagnostics.json"), options: .atomic)
            }
        }
        let voice = isVoice, reads = sampleCount
        DispatchQueue.main.async {
            let status = MonitorStatus.shared
            guard status.running else { return }
            if status.detail != detail { status.detail = detail }
            if status.voiceActive != voice { status.voiceActive = voice }
            status.sampleCount = reads
        }
    }
    func armInputTest() {
        guard ProcessInfo.processInfo.environment["INPUTSTATS_ENABLE_TEST_MONITOR"] == "1" else { return }
        queue.async { self.sample(); self.lastInput = self.now + 30; self.latestEventDate = Date(); self.scheduleSample(after: 0.1) }
    }
    func flushNow() throws {
        try queue.sync {
            guard !pending.isEmpty else { return }
            try Database.shared.add(Array(pending.values))
            pending.removeAll()
            DispatchQueue.main.async {
                MonitorStatus.shared.storageError = nil
                NotificationCenter.default.post(name: .statsDidChange, object: nil)
            }
        }
    }
    func resetAll(completion: @escaping (Error?) -> Void) {
        queue.async {
            do {
                try Database.shared.clearAll()
                self.pending.removeAll(); self.resetFocus()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .statsDidReset, object: nil); completion(nil)
                }
            } catch { DispatchQueue.main.async { completion(error) } }
        }
    }
    func prepareForTermination(completion: @escaping (Error?) -> Void) {
        guard let tap else { DispatchQueue.main.async { completion(nil) }; return }
        CGEvent.tapEnable(tap: tap, enable: false)
        // Keep the main run loop available while AX reads the final focused value.
        queue.async {
            self.sample()
            do {
                if !self.pending.isEmpty { try Database.shared.add(Array(self.pending.values)); self.pending.removeAll() }
                self.stopping = true
                self.sampleWork?.cancel(); self.voiceWork?.cancel(); self.flushWork?.cancel()
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { CGEvent.tapEnable(tap: tap, enable: true); completion(error) }
            }
        }
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil; tapSource = nil
        queue.sync {
            self.sample(); stopping = true
            sampleWork?.cancel(); voiceWork?.cancel(); flushWork?.cancel()
            removeObserver(); flush(); resetFocus()
            // A failed final save is recoverable on next launch, with no typed text on disk.
            if !pending.isEmpty, let data = try? JSONEncoder().encode(Database.Recovery(id: UUID().uuidString, buckets: Array(pending.values))) {
                try? data.write(to: Database.directory.appendingPathComponent("unsaved-counts.json"), options: .atomic)
            }
        }
    }
}
