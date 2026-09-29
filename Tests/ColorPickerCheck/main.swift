import AppKit
import Carbon
import InputStatsCore

var failures = 0
func check(_ value: Bool, _ description: String) {
    print("\(value ? "✓" : "✗") \(description)")
    if !value { failures += 1 }
}
let suite = "com.local.mactoys.color-tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
let pasteboard = NSPasteboard(name: NSPasteboard.Name(suite))
defer { defaults.removePersistentDomain(forName: suite); pasteboard.releaseGlobally() }
var nextSample: NSColor?
var sampleCalls = 0
let store = ColorPickerStore(defaults: defaults, pasteboard: pasteboard, sampler: { handler in
    sampleCalls += 1; handler(nextSample)
})
func sample() -> Bool? {
    var result: Bool?
    store.sample { result = $0 }
    let timeout = Date().addingTimeInterval(2)
    while result == nil && Date() < timeout { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return result
}
check(ScreenColor(nativeColor: NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))?.hex == "#FF8000", "原生 sRGB 转换并四舍五入到8位")
check(ScreenColor(nativeColor: NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1))?.hex == "#FF0000", "Display P3 红色转换并限制为 sRGB")
check(ScreenColor(nativeColor: NSColor(white: 0.5, alpha: 1)) != nil, "灰度色可以转换为 sRGB")
store.apply(hex: "#663399")
store.copy(.hsl)
check(pasteboard.string(forType: .string) == "hsl(270, 50%, 40%)", "HSL 复制写入独立测试剪贴板")
store.apply(hex: "invalid")
check(store.selected.hex == "#663399" && store.history.count == 1 && store.errorMessage != nil, "错误 HEX 不覆盖当前颜色或历史")
store.toggleFavorite(store.selected)
nextSample = nil
check(sample() == false, "系统取消回调结束取色")
check(!store.isSampling && store.selected.hex == "#663399" && store.history.count == 1, "取消不更改颜色或历史且释放采样状态")
check(pasteboard.string(forType: .string) == "hsl(270, 50%, 40%)", "取消不覆盖剪贴板")
nextSample = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
store.format = .rgb
check(sample() == true, "成功采样回调")
check(store.selected.hex == "#00FF00" && store.history.first == store.selected, "取色进入历史首位")
check(pasteboard.string(forType: .string) == "rgb(0, 255, 0)", "取色按所选格式自动复制")
store.autoCopy = false; nextSample = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
check(sample() == true && pasteboard.string(forType: .string) == "rgb(0, 255, 0)", "关闭自动复制后剪贴板保持不变")
var firstCompleted = false, duplicateCompleted = false
let before = sampleCalls
store.sample { _ in firstCompleted = true }; store.sample { _ in duplicateCompleted = true }
let timeout = Date().addingTimeInterval(2)
while !firstCompleted && Date() < timeout { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
check(firstCompleted && !duplicateCompleted && sampleCalls == before + 1, "快速重复触发仅启动一次取色")
let restored = ColorPickerStore(defaults: defaults, pasteboard: pasteboard)
check(restored.history == store.history && restored.selected == store.selected, "重新创建 Store 后颜色和历史保留")
check(restored.favorites.map(\.hex) == ["#663399"], "收藏独立持久化")
check(restored.format == .rgb && !restored.autoCopy, "复制偏好持久化")
store.clearHistory()
check(store.history.isEmpty && store.favorites.count == 1, "清空最近颜色保留收藏")

let one = ColorShortcutRegistration(), two = ColorShortcutRegistration()
let shortcut = ColorShortcut(keyCode: UInt32(kVK_ANSI_9), modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey))
let registered = one.register(shortcut)
check(registered == noErr, "系统全局快捷键注册")
if registered == noErr {
    check(two.register(shortcut) != noErr, "系统报告快捷键冲突而非抢占")
    one.unregister()
    check(two.register(shortcut) == noErr, "注销后快捷键可以重新注册")
    two.unregister()
}
print("Native Color Picker checks: \(failures == 0 ? "PASS" : "FAIL")")
exit(failures == 0 ? 0 : 1)
