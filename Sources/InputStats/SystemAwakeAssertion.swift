import Foundation
import IOKit.pwr_mgt

protocol AwakeAssertion: AnyObject {
    func release()
}

enum AwakeError: LocalizedError {
    case invalidDuration, system(IOReturn), testMode
    var errorDescription: String? {
        switch self {
        case .invalidDuration: return L("防休眠时长无效。")
        case .system(let code): return L("无法启用防止休眠（系统错误 %@），请重试。", String(describing: code))
        case .testMode: return L("界面测试 · 系统防休眠已关闭")
        }
    }
}

/// One process-owned assertion; macOS also cleans it up if the process exits.
final class SystemAwakeAssertion: AwakeAssertion {
    private(set) var id: IOPMAssertionID = 0

    init(keepDisplayAwake: Bool, timeout: TimeInterval?) throws {
        if let timeout, !timeout.isFinite || timeout <= 0 { throw AwakeError.invalidDuration }
        let type = keepDisplayAwake ? kIOPMAssertPreventUserIdleDisplaySleep : kIOPMAssertPreventUserIdleSystemSleep
        var properties: [String: Any] = [
            kIOPMAssertionTypeKey: type,
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
            kIOPMAssertionNameKey: "MacToys Keep Awake",
            kIOPMAssertionDetailsKey: keepDisplayAwake ? "Keep the display and Mac awake" : "Keep the Mac awake; allow display sleep"
        ]
        if let timeout {
            // Let powerd turn it off even if the app's main run loop is blocked.
            // Retain the ID until release(), avoiding a second release of a reused ID.
            properties[kIOPMAssertionTimeoutKey] = timeout
            properties[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionTurnOff
        }
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id)
        guard result == kIOReturnSuccess else { id = 0; throw AwakeError.system(result) }
    }

    func release() {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
    }
    deinit { release() }
}
