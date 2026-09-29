import AppKit
import IOKit.pwr_mgt

var failures = 0
var checks = 0
func check(_ value: Bool, _ description: String) {
    checks += 1
    print("\(value ? "✓" : "✗") \(description)")
    if !value { failures += 1 }
}

final class FakeAssertion: AwakeAssertion {
    let display: Bool
    let timeout: TimeInterval?
    var releases = 0
    init(_ display: Bool, _ timeout: TimeInterval?) { self.display = display; self.timeout = timeout }
    func release() { releases += 1 }
}
final class FakePower {
    var assertions: [FakeAssertion] = []
    var fail = false
    func create(_ display: Bool, _ timeout: TimeInterval?) throws -> AwakeAssertion {
        if fail { throw AwakeError.system(kIOReturnError) }
        let assertion = FakeAssertion(display, timeout)
        assertions.append(assertion)
        return assertion
    }
    var active: [FakeAssertion] { assertions.filter { $0.releases == 0 } }
}

let suite = "com.local.mactoys.awake-tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let power = FakePower()
var clock = Date().addingTimeInterval(3600)
let store = KeepAwakeStore(defaults: defaults, now: { clock }, makeAssertion: power.create)
check(!store.enabled && store.keepDisplayAwake && store.duration == .untilOff, "默认关闭，预选屏幕常亮和直到关闭")
store.setEnabled(true)
check(!store.enabled && power.assertions.isEmpty, "未启动的 Store 不获取系统资源")
store.start(); store.start(); store.setEnabled(true)
check(store.enabled && power.active.count == 1 && power.active[0].display, "启用时只创建一个屏幕与系统防休眠断言")
check(store.endsAt == nil && power.active[0].timeout == nil, "直到关闭不创建定时截止时间")
store.setEnabled(true)
check(power.assertions.count == 1, "重复启用不重复获取资源")
store.setEnabled(false); store.setEnabled(false)
check(!store.enabled && power.active.isEmpty && power.assertions[0].releases == 1, "重复关闭只释放一次断言")

store.setDuration(.minutes15)
check(power.active.isEmpty && !store.enabled, "关闭时调整时长不会唤醒电脑")
store.setEnabled(true)
let deadline = clock.addingTimeInterval(900)
check(store.endsAt == deadline && power.active[0].timeout == 900, "15 分钟同时设置界面截止时间和系统超时")
clock.addTimeInterval(120)
store.setKeepDisplayAwake(false)
check(!store.keepDisplayAwake && !power.active[0].display, "允许屏幕熄灭时改用系统防休眠类型")
check(store.endsAt == deadline && power.active[0].timeout == 780, "切换屏幕选项保留原截止时间")
check(power.active.count == 1 && power.assertions.dropLast().allSatisfy { $0.releases == 1 }, "替换成功后释放旧断言")

power.fail = true
let activeBeforeFailure = power.active[0]
store.setKeepDisplayAwake(true)
check(!store.keepDisplayAwake && store.enabled && power.active[0] === activeBeforeFailure,
      "切换失败保留原选项与正在运行的断言")
check(store.issue != nil && defaults.bool(forKey: "awake.display") == false, "失败显示错误且不写入未生效偏好")
store.setDuration(.hours2)
check(store.duration == .minutes15 && store.endsAt == deadline, "更改时长失败保留旧截止时间")
power.fail = false
store.setDuration(.minutes30)
check(store.endsAt == clock.addingTimeInterval(1800) && store.issue == nil, "更改时长成功后从当前时刻重新计时")
store.setDuration(.untilOff)
check(store.enabled && store.endsAt == nil && power.active[0].timeout == nil, "改为直到关闭会取消两层超时")
clock.addTimeInterval(100_000); store.expireIfNeeded()
check(store.enabled, "无期限会话不会因时钟推进自动结束")

store.setDuration(.hour1)
clock.addTimeInterval(3601); store.refreshDeadline()
check(!store.enabled && store.endsAt == nil && power.active.isEmpty, "睡眠跨过截止时间后结束并清理资源")
store.setEnabled(true)
let wakeDeadline = store.endsAt
clock.addTimeInterval(60); store.refreshDeadline()
check(store.enabled && store.endsAt == wakeDeadline && power.active[0].timeout == 3540, "未到期唤醒保留截止时间并更新系统超时")
clock.addTimeInterval(-60); store.refreshDeadline()
check(power.active[0].timeout == 3600 && store.endsAt == wakeDeadline, "时钟回拨后系统超时与显示时间一致")
power.fail = true; store.refreshDeadline()
check(!store.enabled && power.active.isEmpty && store.issue != nil, "恢复失败结束会话，避免显示虚假的开启状态")
store.setEnabled(true)
check(!store.enabled && power.active.isEmpty && store.issue != nil, "初次创建失败不会显示已开启")
power.fail = false; store.setEnabled(true)
clock.addTimeInterval(3600); store.expireIfNeeded()
check(!store.enabled && power.active.isEmpty, "到截止时刻自动释放断言")

store.setKeepDisplayAwake(true); store.setDuration(.hours4); store.setEnabled(true)
let restored = KeepAwakeStore(defaults: defaults, makeAssertion: power.create)
check(!restored.enabled && restored.keepDisplayAwake && restored.duration == .hours4,
      "重新创建实例只恢复偏好，不自动延续开启状态")
restored.stop(); store.stop()
check(power.active.isEmpty && power.assertions.allSatisfy { $0.releases == 1 }, "停止释放全部资源，没有重复释放")
store.setEnabled(true)
check(!store.enabled && power.active.isEmpty, "停止后不会意外重新启用")
store.start(); store.setEnabled(true); store.stop()
check(power.active.isEmpty, "显式重新启动后仍能完整清理")
defaults.set(999, forKey: "awake.duration")
let invalidPrefs = KeepAwakeStore(defaults: defaults, makeAssertion: power.create)
check(invalidPrefs.duration == .untilOff && !invalidPrefs.enabled, "异常偏好回退且保持关闭")
do {
    let scoped = KeepAwakeStore(defaults: defaults, makeAssertion: power.create)
    scoped.start(); scoped.setEnabled(true)
}
check(power.active.isEmpty, "Store 销毁时释放防休眠状态")

// Native assertions are short-lived and process-owned. No sleep settings are changed.
func properties(_ id: IOPMAssertionID) -> [String: Any]? {
    IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any]
}
func ownActiveAssertions() -> [[String: Any]]? {
    var result: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess,
          let dictionary = result?.takeRetainedValue() as NSDictionary? else { return nil }
    let own = dictionary[NSNumber(value: getpid())] as? [[String: Any]] ?? []
    return own.filter { $0[kIOPMAssertionNameKey] as? String == "MacToys Keep Awake" }
}
for bad in [0.0, -1.0, .infinity, .nan] {
    do {
        let assertion = try SystemAwakeAssertion(keepDisplayAwake: false, timeout: bad)
        assertion.release(); check(false, "拒绝无效超时 \(bad)")
    } catch { check(true, "拒绝无效超时 \(bad)") }
}
do {
    let display = try SystemAwakeAssertion(keepDisplayAwake: true, timeout: 10)
    let displayID = display.id
    let info = properties(displayID)
    check(info?[kIOPMAssertionTypeKey] as? String == kIOPMAssertPreventUserIdleDisplaySleep,
          "系统实际注册 PreventUserIdleDisplaySleep")
    check((info?[kIOPMAssertionLevelKey] as? NSNumber)?.intValue == kIOPMAssertionLevelOn,
          "系统确认屏幕防休眠处于开启状态")
    display.release(); display.release()
    check(properties(displayID) == nil && display.id == 0, "关闭后系统断言消失，重复释放无副作用")

    let system = try SystemAwakeAssertion(keepDisplayAwake: false, timeout: 1)
    let systemID = system.id
    let systemInfo = properties(systemID)
    check(systemInfo?[kIOPMAssertionTypeKey] as? String == kIOPMAssertPreventUserIdleSystemSleep,
          "仅保持 Mac 唤醒使用独立的系统休眠类型")
    check(systemInfo?[kIOPMAssertionTimeoutActionKey] as? String == kIOPMAssertionTimeoutActionTurnOff,
          "系统持有独立超时兜底")
    check(ownActiveAssertions()?.count == 1, "系统活动断言列表包含当前会话")
    // Do not run the app's Timer: powerd must turn the assertion off independently.
    // A timed-out record can retain its originally requested AssertLevel; use the
    // system's active list rather than that stored creation property as the oracle.
    let timeoutLimit = Date().addingTimeInterval(5)
    repeat { Thread.sleep(forTimeInterval: 0.1) }
    while ownActiveAssertions()?.isEmpty == false && Date() < timeoutLimit
    check(ownActiveAssertions()?.isEmpty == true,
          "应用不处理计时回调时，系统也会自动关闭到期断言")
    system.release()
    check(properties(systemID) == nil, "到期断言仍可正常释放")

    var scopedID: IOPMAssertionID = 0
    do {
        let scoped = try SystemAwakeAssertion(keepDisplayAwake: false, timeout: nil)
        scopedID = scoped.id
        check(properties(scopedID) != nil, "无期限断言实际创建成功")
        withExtendedLifetime(scoped) {}
    }
    check(properties(scopedID) == nil, "断言对象销毁后由 RAII 释放")
} catch { check(false, "原生电源断言检查：\(error.localizedDescription)") }

print("Keep Awake checks: \(checks - failures)/\(checks) passed")
exit(failures == 0 ? 0 : 1)
