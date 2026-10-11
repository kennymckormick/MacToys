import ApplicationServices
import Foundation

/// AXObserver notifications are delivered on the main run loop. Registration,
/// removal and final release must stay on that same thread to avoid tearing
/// down its notification dictionary while a callback is using it.
final class AXFocusObserver {
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var element: AXUIElement?
    private(set) var generation: UInt64 = 0
    private var onChange: ((Bool, UInt64) -> Void)?

    @discardableResult
    func bind(pid: pid_t?, onChange: @escaping (Bool, UInt64) -> Void) -> UInt64 {
        precondition(Thread.isMainThread)
        stop()
        self.onChange = onChange
        guard let pid else { return generation }
        var created: AXObserver?
        let result = AXObserverCreate(pid, { callbackObserver, _, notification, context in
            guard let context else { return }
            let owner = Unmanaged<AXFocusObserver>.fromOpaque(context).takeUnretainedValue()
            precondition(Thread.isMainThread)
            guard let current = owner.observer, CFEqual(current, callbackObserver) else { return }
            owner.onChange?((notification as String) == kAXFocusedUIElementChangedNotification, owner.generation)
        }, &created)
        if result == .success, let created {
            observer = created
            let app = AXUIElementCreateApplication(pid); application = app
            AXUIElementSetMessagingTimeout(app, 0.12)
            AXObserverAddNotification(created, app, kAXFocusedUIElementChangedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
        return generation
    }

    func observe(_ next: AXUIElement?, generation expected: UInt64) {
        precondition(Thread.isMainThread)
        guard generation == expected, let observer else { return }
        if let element { AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString) }
        element = next
        if let next {
            AXUIElementSetMessagingTimeout(next, 0.12)
            AXObserverAddNotification(observer, next, kAXValueChangedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
        }
    }

    func stop() {
        precondition(Thread.isMainThread)
        generation &+= 1
        onChange = nil
        if let observer {
            if let element { AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString) }
            if let application { AXObserverRemoveNotification(observer, application, kAXFocusedUIElementChangedNotification as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        element = nil; application = nil; observer = nil
    }

    deinit { stop() }
}
