import Foundation

/// 一分钟粒度的统计桶。
public struct MinuteBucket: Equatable, Codable {
    public var start: Int          // 该分钟起始的 epoch 秒（UTC）
    public var keyboardChars: Int
    public var keyboardWords: Int
    public var voiceChars: Int
    public var voiceWords: Int

    public init(start: Int, keyboardChars: Int, keyboardWords: Int, voiceChars: Int, voiceWords: Int) {
        self.start = start
        self.keyboardChars = keyboardChars
        self.keyboardWords = keyboardWords
        self.voiceChars = voiceChars
        self.voiceWords = voiceWords
    }
}

/// 聚合后用于图表的一个数据点。
public struct StatPoint: Identifiable, Equatable {
    public var id: Date { date }
    public let label: String
    public let date: Date
    public let keyboardChars: Int
    public let keyboardWords: Int
    public let voiceChars: Int
    public let voiceWords: Int

    public init(label: String, date: Date, keyboardChars: Int, keyboardWords: Int, voiceChars: Int, voiceWords: Int) {
        self.label = label
        self.date = date
        self.keyboardChars = keyboardChars
        self.keyboardWords = keyboardWords
        self.voiceChars = voiceChars
        self.voiceWords = voiceWords
    }
}
