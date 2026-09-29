import Foundation

/// 字数/单词数计算。
public enum TextCount {
    /// 字数：每个字符（含每个汉字、每个 emoji）计 1。
    public static func chars(_ text: [Character]) -> Int { text.count }

    /// 单词数：每个 CJK 表意文字（中文/日文汉字等）计 1；连续字母/数字串计 1 个英文单词。
    public static func words(_ text: [Character]) -> Int {
        var count = 0
        var inLatinRun = false
        for ch in text {
            guard let scalar = ch.unicodeScalars.first else { continue }
            if isCJK(scalar) {
                count += 1
                inLatinRun = false
            } else if ch.isLetter || ch.isNumber {
                if !inLatinRun { count += 1; inLatinRun = true }
            } else {
                inLatinRun = false
            }
        }
        return count
    }

    public static func words(_ text: String) -> Int { words(Array(text)) }

    private static func isCJK(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3400...0x4DBF,     // 扩展 A
             0x4E00...0x9FFF,     // CJK 统一表意文字
             0xF900...0xFAFF,     // 兼容表意文字
             0x20000...0x2A6DF,   // 扩展 B
             0x2A700...0x2EE5F,   // 扩展 C-F / I
             0x30000...0x323AF,   // 扩展 G-H
             0x3040...0x30FF,     // 平假名/片假名
             0xAC00...0xD7AF:     // 谚文音节
            return true
        default:
            return false
        }
    }
}
