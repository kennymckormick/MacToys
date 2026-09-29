import Foundation
import InputStatsCore
import InputStatsStorage

// 轻量断言自检（替代 XCTest，命令行环境无 Xcode 也能跑）。
var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✓ \(msg)") }
    else { print("  ✗ \(msg)"); failures += 1 }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String) { check(a == b, "\(msg)  (得到 \(a), 期望 \(b))") }

// MARK: TextCount
print("[TextCount]")
eq(TextCount.words("hello world"), 2, "英文两词")
eq(TextCount.words("what can i SAY"), 4, "英文四词")
eq(TextCount.words("测试"), 2, "中文两字=两词")
eq(TextCount.words("测试一下"), 4, "中文四字=四词")
eq(TextCount.words("hi你好"), 3, "混合 hi+你+好=3")
eq(TextCount.words("测试 hello world"), 4, "混合 测 试 + hello + world = 4")
eq(TextCount.chars(Array("测试一下")), 4, "字数=4")

// MARK: InputCounter
func run(_ snaps: [String], base: String? = "", dictating: Bool = false) -> InputCounter.Delta {
    let c = InputCounter(); c.reset(to: base)
    var t = InputCounter.Delta()
    for s in snaps {
        let provisional = s == "ce" || s == "ceshi" || s == "ceshiyixia"
        let d = c.step(content: s, dictating: dictating, provisional: provisional)
        t.keyboardChars += d.keyboardChars; t.keyboardWords += d.keyboardWords
        t.voiceChars += d.voiceChars; t.voiceWords += d.voiceWords
    }
    return t
}

print("[InputCounter]")
var t = run(["h", "he", "hel", "hell", "hello"])
eq(t.keyboardChars, 5, "英文逐字=5字"); eq(t.keyboardWords, 1, "英文=1词")

t = run(["ce", "ceshi", "ceshiyixia", "测试一下"])
eq(t.keyboardChars, 4, "拼音上屏净计4字（不含拼音字母）"); eq(t.keyboardWords, 4, "中文4词")

t = run(["你", "你好", "你好世", "你好世界"])
eq(t.keyboardChars, 4, "中文直接输入4字"); eq(t.keyboardWords, 4, "4词")

t = run(["ceshiyixia", "测试一下", "测试一下 ", "测试一下 hello", "测试一下 hello world"])
eq(t.keyboardChars, "测试一下 hello world".count, "混合句字数")
eq(t.keyboardWords, 6, "混合句词数 测试一下+hello+world=6")

t = run(["hello", "hell", "hel", "he"])
eq(t.keyboardChars, 5, "删除不倒扣已输入的5字"); eq(t.keyboardWords, 1, "1词")

do {
    let c = InputCounter(); c.reset(to: "")
    _ = c.step(content: "hello", dictating: false)
    check(c.step(content: "hello", dictating: false).isZero, "相同快照不重复计数")
}
do {
    let c = InputCounter(); c.reset(to: "")
    _ = c.step(content: "hi", dictating: false)
    c.reset(to: "已有很多文字的另一个输入框")
    let d = c.step(content: "已有很多文字的另一个输入框!", dictating: false)
    eq(d.keyboardChars, 1, "切焦点后只计新增1字")
}
t = run([String(repeating: "x", count: 100)])
eq(t.keyboardChars, 100, "完整上屏长句无任意40字上限")

t = run(["你好"], dictating: true)
eq(t.voiceChars, 2, "语音2字"); eq(t.voiceWords, 2, "语音2词"); eq(t.keyboardChars, 0, "键盘0")

// MARK: Aggregator
print("[Aggregator]")
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
let now = Date()
let sod = cal.startOfDay(for: now)
let nine = Int(cal.date(byAdding: .hour, value: 9, to: sod)!.timeIntervalSince1970)
let ten = Int(cal.date(byAdding: .hour, value: 10, to: sod)!.timeIntervalSince1970)
let hb = [
    MinuteBucket(start: nine, keyboardChars: 10, keyboardWords: 3, voiceChars: 0, voiceWords: 0),
    MinuteBucket(start: nine + 60, keyboardChars: 5, keyboardWords: 2, voiceChars: 1, voiceWords: 1),
    MinuteBucket(start: ten, keyboardChars: 7, keyboardWords: 1, voiceChars: 0, voiceWords: 0),
]
let hp = Aggregator.hourly(buckets: hb, now: now, calendar: cal)
eq(hp.count, 24, "24个小时点")
eq(hp[9].keyboardChars, 15, "9点合并=15"); eq(hp[9].voiceChars, 1, "9点语音=1")
eq(hp[10].keyboardChars, 7, "10点=7"); eq(hp[0].keyboardChars, 0, "0点=0")
eq(hp[9].label, "9", "标签为小时数")

let today0 = Int(sod.timeIntervalSince1970)
let db = [
    MinuteBucket(start: today0, keyboardChars: 4, keyboardWords: 4, voiceChars: 0, voiceWords: 0),
    MinuteBucket(start: today0 + 120, keyboardChars: 6, keyboardWords: 2, voiceChars: 0, voiceWords: 0),
]
let dp = Aggregator.daily(buckets: db, days: 7, now: now, calendar: cal)
eq(dp.count, 7, "7天")
eq(dp.last!.keyboardChars, 10, "今天(最后)=10"); eq(dp.first!.keyboardChars, 0, "首日=0")

// groupByDay（导出用）
let gb = Aggregator.groupByDay(buckets: db, calendar: cal)
eq(gb.count, 1, "同日两桶合并为1天")
eq(gb.first!.keyboardChars, 10, "当日合计=10")
eq(gb.first!.keyboardWords, 6, "当日词=6")

print("[Regression]")
eq(run(["cat", "dog"]).keyboardChars, 6, "等长替换也记录新输入")
eq(run(["", "x"], base: "已有内容").keyboardChars, 1, "清空已有文本不产生负数")
eq(run(["hello", "", "hello"]).keyboardWords, 2, "发送后清空再输入不会抵消上一句")
eq(run(["hello", "hello world"]).keyboardWords, 2, "分批输入单词不重复计数")
eq(run(["hello", "helloo"]).keyboardWords, 1, "扩展一个单词只计一次")
eq(run(["👨‍👩‍👧‍👦", "👨‍👩‍👧‍👦é"]).keyboardChars, 2, "组合emoji和重音按字素计数")
eq(run([String(repeating: "中", count: 12_345)], dictating: true).voiceWords, 12_345, "一万以上中文语音完整计数")
do {
    let c = InputCounter()
    check(c.step(content: "existing", dictating: false).isZero, "没有基线不统计既有内容")
    c.reset(to: "")
    let start = Date()
    for _ in 0..<10_000 { _ = c.step(content: "", dictating: false) }
    check(Date().timeIntervalSince(start) < 1, "重复快照快速跳过")
}
do {
    var voice = VoiceSession()
    check(!voice.isVoice(now: 10), "尚未按Fn不是语音")
    voice.change(down: true, now: 10)
    check(voice.isVoice(now: 10.1), "Fn按住启用语音")
    voice.change(down: false, now: 11)
    check(voice.isVoice(now: 13), "松开后的延迟上屏归为语音")
    check(!voice.isVoice(now: 15), "延迟窗口结束后回到键盘")
    voice.change(down: true, now: 20); voice.change(down: false, now: 20.1)
    voice.change(down: true, now: 20.2); voice.change(down: false, now: 20.3)
    check(voice.isVoice(now: 30), "双击Fn锁定语音")
    check(!voice.isVoice(now: 200), "不完整Fn事件不会永久卡在语音")
    voice.keyboardActivity()
    check(!voice.isVoice(now: 31), "键盘输入清除语音尾部")
}
do {
    var dst = Calendar(identifier: .gregorian)
    dst.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let spring = dst.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
    let autumn = dst.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
    eq(Aggregator.hourly(buckets: [], now: spring, calendar: dst).count, 23, "夏令时开始有23小时")
    let repeated = Aggregator.hourly(buckets: [], now: autumn, calendar: dst)
    eq(repeated.count, 25, "夏令时结束有25小时")
    eq(Set(repeated.map(\.id)).count, 25, "重复小时身份不冲突")
    eq(Aggregator.daily(buckets: [], days: 0, now: now, calendar: cal).count, 0, "零天范围不崩溃")
    eq(hp.map(\.id), Aggregator.hourly(buckets: hb, now: now, calendar: cal).map(\.id), "图表刷新保留稳定身份")
}
do {
    let c = InputCounter()
    var text = String(repeating: "word ", count: 12_000)
    c.reset(to: text)
    var chars = 0
    let started = Date()
    for _ in 0..<200 {
        text.append("x")
        chars += c.step(content: text, dictating: false).keyboardChars
    }
    eq(chars, 200, "六万字符文档的连续增量准确")
    print("  长文档200次更新用时：\(Date().timeIntervalSince(started)) 秒")
}
print("[Storage]")
do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mactoys-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("stats.sqlite")
    let db = try StatsDatabase(url: url)
    let before = MinuteBucket(start: 60, keyboardChars: 12_345, keyboardWords: 11_111, voiceChars: 30, voiceWords: 20)
    let after = MinuteBucket(start: 120, keyboardChars: 1, keyboardWords: 1, voiceChars: 4, voiceWords: 4)
    try db.add([before, after]); try db.add([before])
    let rows = try db.buckets()
    eq(rows.count, 2, "多个分钟桶原子保存，不全部塞进落盘分钟")
    eq(rows[0].keyboardChars, 24_690, "大于一万的计数正确落库并累加")
    eq(try db.buckets(from: 120, to: 180), [after], "时间查询采用半开区间")
    let reopened = try StatsDatabase(url: url)
    eq(try reopened.buckets(), rows, "重启后计数保持")
    do {
        try db.add([MinuteBucket(start: 180, keyboardChars: -1, keyboardWords: 0, voiceChars: 0, voiceWords: 0)])
        check(false, "拒绝负数增量")
    } catch { check(true, "拒绝负数增量") }
    try db.add([after], recoveryID: "test-recovery")
    let recovered = try db.buckets()
    try db.add([after], recoveryID: "test-recovery")
    eq(try db.buckets(), recovered, "退出恢复批次幂等，删除恢复文件失败也不重复计数")
    try db.clearAll()
    eq(try db.buckets().count, 0, "重置成功")
} catch { check(false, "数据库测试失败：\(error)") }

print("[ScreenColor]")
for (hex, hsl) in [("#FF0000", "hsl(0, 100%, 50%)"), ("#00FF00", "hsl(120, 100%, 50%)"),
    ("#0000FF", "hsl(240, 100%, 50%)"), ("#000000", "hsl(0, 0%, 0%)"),
    ("#FFFFFF", "hsl(0, 0%, 100%)"), ("#808080", "hsl(0, 0%, 50.2%)"), ("#663399", "hsl(270, 50%, 40%)")] {
    eq(ScreenColor(hex: hex)?.hsl, hsl, "\(hex) 转 HSL")
}
eq(ScreenColor(hex: "  #f80\n")?.hex, "#FF8800", "短 HEX 展开并接受空白、小写")
eq(ScreenColor(hex: "663399")?.rgb, "rgb(102, 51, 153)", "无井号 HEX 转 CSS RGB")
for invalid in ["", "#12", "#1234", "#12345678", "#GGGGGG", "+FF000", "#１２３"] {
    check(ScreenColor(hex: invalid) == nil, "无效 HEX 不被当成黑色：\(invalid)")
}
check(ScreenColor(hex: "#FFFFFF")!.prefersDarkText && !ScreenColor(hex: "#000000")!.prefersDarkText, "黑白预览文字保持对比")
do {
    var history = ColorHistory(hexValues: ["#F00", "invalid", "#ff0000", "#00FF00"])
    eq(history.colors.map(\.hex), ["#FF0000", "#00FF00"], "历史清理无效值并按颜色去重")
    for byte in 0..<30 { history.record(ScreenColor(red: UInt8(byte), green: 0, blue: 0)) }
    eq(history.colors.count, 24, "历史最多保留24个颜色")
    let oldest = history.colors.last!
    history.record(oldest)
    eq(history.colors.first, oldest, "重复取色提升到最前")
    eq(Set(history.colors).count, 24, "提升已有颜色不会挤掉其他记录")
    let restored = ColorHistory(hexValues: history.colors.map(\.hex))
    eq(restored.colors, history.colors, "保存与恢复历史保持顺序与颜色")
}

print(failures == 0 ? "\n全部通过 ✅" : "\n失败 \(failures) 项 ❌")
exit(failures == 0 ? 0 : 1)
