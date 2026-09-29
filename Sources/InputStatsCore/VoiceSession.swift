import Foundation

/// Fn hold / double-tap lock, with a short tail for asynchronous dictation commits.
public struct VoiceSession {
    public private(set) var held = false
    public private(set) var locked = false
    private var lastUp = -Double.infinity
    private var graceUntil = -Double.infinity
    private var lastActivity = -Double.infinity
    public init() {}
    public mutating func change(down: Bool, now: TimeInterval) {
        guard down != held else { return }
        held = down
        lastActivity = now
        if down {
            if locked { locked = false; graceUntil = now + 3 }
            else if now - lastUp <= 0.4 { locked = true }
        } else {
            lastUp = now
            graceUntil = now + 3
        }
    }
    public mutating func keyboardActivity() {
        // Fn navigation shortcuts and ordinary typing end a stale dictation tail.
        held = false; locked = false; graceUntil = -Double.infinity
    }
    public mutating func touch(now: TimeInterval) { lastActivity = now }
    public func isVoice(now: TimeInterval) -> Bool {
        ((held || locked) && now - lastActivity < 120) || now < graceUntil
    }
    public func isListening(now: TimeInterval) -> Bool { (held || locked) && now - lastActivity < 120 }
}
