import AppKit

// Construct local CGEvents only. These checks never post events or change system scrolling.
var failures = 0
var checks = 0
func check(_ value: Bool, _ description: String) {
    checks += 1
    print("\(value ? "✓" : "✗") \(description)")
    if !value { failures += 1 }
}

func wheel(continuous: Bool = false, phase: Int64 = 0, momentum: Int64 = 0, pid: Int64 = 0) -> CGEvent {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                        wheel1: 3, wheel2: -2, wheel3: 0)!
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    event.setIntegerValueField(.eventSourceUnixProcessID, value: pid)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 3.25)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -2.5)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 47)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -31)
    event.timestamp = 123_456_789
    event.flags = [.maskShift, .maskAlternate]
    return event
}

let yFields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1]
let xFields: [CGEventField] = [.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2]
func deltas(_ event: CGEvent, _ fields: [CGEventField]) -> [Double] {
    fields.map { event.getDoubleValueField($0) }
}

for (vertical, horizontal) in [(true, false), (false, true), (true, true), (false, false)] {
    let event = wheel()
    let y = deltas(event, yFields), x = deltas(event, xFields)
    let changed = MouseWheelReversal.apply(to: event,
        options: ScrollReversalOptions(enabled: true, vertical: vertical, horizontal: horizontal))
    check(changed == (vertical || horizontal), "方向开关 \(vertical)/\(horizontal) 决定是否处理")
    check(deltas(event, yFields) == y.map { vertical ? -$0 : $0 }, "垂直轴保留原有步长、精度和速度")
    check(deltas(event, xFields) == x.map { horizontal ? -$0 : $0 }, "水平轴独立反转且保留原有步长")
    check(event.timestamp == 123_456_789 && event.flags == [.maskShift, .maskAlternate], "时间戳和修饰键不变")
}

let enabled = ScrollReversalOptions(enabled: true, vertical: true, horizontal: true)
let untouched: [(String, CGEvent, ScrollReversalOptions)] = [
    ("总开关关闭", wheel(), ScrollReversalOptions()),
    ("触控板连续滚动", wheel(continuous: true, phase: 2), enabled),
    ("触控板惯性滚动", wheel(continuous: true, momentum: 1), enabled),
    ("没有 phase 的连续设备也保持原样", wheel(continuous: true), enabled),
    ("带手势阶段的非连续事件保持原样", wheel(phase: 4), enabled),
    ("带惯性阶段的非连续事件保持原样", wheel(momentum: 2), enabled),
    ("其他程序生成的滚动不再次反转", wheel(pid: Int64(getpid())), enabled)
]
for (name, event, options) in untouched {
    let before = event.copy()!
    check(!MouseWheelReversal.apply(to: event, options: options), name)
    check(deltas(event, yFields + xFields) == deltas(before, yFields + xFields)
          && event.flags == before.flags && event.timestamp == before.timestamp,
          "\(name)：原始数据不变")
}

let key = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
check(!MouseWheelReversal.apply(to: key, options: enabled) && key.type == .keyDown, "不处理键盘事件")
let pair = wheel()
let pairBefore = deltas(pair, yFields + xFields)
MouseWheelReversal.apply(to: pair, options: enabled)
MouseWheelReversal.apply(to: pair, options: enabled)
check(deltas(pair, yFields + xFields) == pairBefore, "两次反转可逆，没有累积缩放")

// Device handoffs have no remembered device state that can leak into momentum events.
let trackpad = wheel(continuous: true, phase: 2)
let mouse = wheel()
let momentum = wheel(continuous: true, momentum: 2)
check(!MouseWheelReversal.apply(to: trackpad, options: enabled)
      && MouseWheelReversal.apply(to: mouse, options: enabled)
      && !MouseWheelReversal.apply(to: momentum, options: enabled), "触控板 → 鼠标 → 触控板惯性不会混淆")

let native = wheel()
let nativeBefore = NSEvent(cgEvent: native)!
let nativeY = nativeBefore.scrollingDeltaY, nativeX = nativeBefore.scrollingDeltaX
MouseWheelReversal.apply(to: native, options: enabled)
let nativeAfter = NSEvent(cgEvent: native)!
check(nativeAfter.scrollingDeltaY == -nativeY && nativeAfter.scrollingDeltaX == -nativeX,
      "AppKit 读取到反转后的滚动值")

let suite = "com.local.mactoys.scroll-tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let store = ScrollReversalStore(defaults: defaults, allowEventTap: false)
check(!store.enabled && store.reverseVertical && !store.reverseHorizontal, "首次使用默认关闭，默认仅垂直方向")
store.start(); store.enabled = true; store.reverseHorizontal = true; store.reverseVertical = false
check(!store.running && store.issue != nil, "测试实例不安装全局滚轮监听")
let restored = ScrollReversalStore(defaults: defaults, allowEventTap: false)
check(restored.enabled && !restored.reverseVertical && restored.reverseHorizontal, "重启后保留总开关和两轴设置")
store.reverseHorizontal = false
check(store.issue == nil && !store.running && store.status == L("请选择要反转的方向"), "所有方向关闭时移除监听")
store.enabled = false
check(store.status == L("已关闭"), "关闭总开关立即恢复状态")
store.stop(); restored.stop()

defaults.set(true, forKey: "scroll.enabled"); defaults.set(true, forKey: "scroll.vertical")
var conflict: String? = "Scroll Reverser"
var accessChecks = 0
let gated = ScrollReversalStore(defaults: defaults, allowEventTap: true,
    accessAvailable: { accessChecks += 1; return false }, conflictingApp: { conflict })
gated.start()
check(!gated.running && gated.issue?.contains("Scroll Reverser") == true && accessChecks == 0,
      "检测到旧程序时不安装重复反转监听")
conflict = nil; gated.retry()
check(!gated.running && gated.issue == L("辅助功能授权未生效，请在系统设置中检查 MacToys 的权限。") && accessChecks == 1,
      "权限不足时说明原因，不弹出授权或修改系统设置")
gated.stop(); gated.enabled = false; gated.enabled = true
check(accessChecks == 1 && !gated.running, "停止后设置变化不重建全局监听")

let benchmark = wheel()
let started = ProcessInfo.processInfo.systemUptime
for _ in 0..<100_000 { MouseWheelReversal.apply(to: benchmark, options: enabled) }
let elapsed = ProcessInfo.processInfo.systemUptime - started
print("100,000 local event transforms: \(String(format: "%.3f", elapsed)) s")
print("Scroll Reversal checks: \(checks - failures)/\(checks) passed")
exit(failures == 0 ? 0 : 1)
