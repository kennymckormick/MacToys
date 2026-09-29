import Foundation

/// 把分钟桶聚合为按小时/按天的图表数据点（纯逻辑，可单元测试）。
public enum Aggregator {
    private struct Agg { var kc = 0, kw = 0, vc = 0, vw = 0 }

    /// 今天 0–23 点，每小时一个点。label 为小时数（"0".."23"）。
    public static func hourly(buckets: [MinuteBucket], now: Date, calendar: Calendar) -> [StatPoint] {
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        var byHour: [Date: Agg] = [:]
        for b in buckets {
            let date = Date(timeIntervalSince1970: TimeInterval(b.start))
            guard calendar.isDate(date, inSameDayAs: startOfDay) else { continue }
            guard let hour = calendar.dateInterval(of: .hour, for: date)?.start else { continue }
            var a = byHour[hour] ?? Agg()
            a.kc += b.keyboardChars; a.kw += b.keyboardWords
            a.vc += b.voiceChars; a.vw += b.voiceWords
            byHour[hour] = a
        }
        // DST days contain 23 or 25 real hours. Repeated clock hours stay distinct.
        return stride(from: startOfDay.timeIntervalSince1970, to: endOfDay.timeIntervalSince1970, by: 3600).map { epoch in
            let date = Date(timeIntervalSince1970: epoch)
            let a = byHour[date] ?? Agg()
            return StatPoint(label: "\(calendar.component(.hour, from: date))", date: date,
                             keyboardChars: a.kc, keyboardWords: a.kw,
                             voiceChars: a.vc, voiceWords: a.vw)
        }
    }

    /// 最近 N 天，每天一个点。label 为 "M/d"。
    public static func daily(buckets: [MinuteBucket], days: Int, now: Date, calendar: Calendar) -> [StatPoint] {
        guard days > 0 else { return [] }
        let startOfToday = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) else { return [] }
        var byDay: [Date: Agg] = [:]
        for b in buckets {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(b.start)))
            var a = byDay[day] ?? Agg()
            a.kc += b.keyboardChars; a.kw += b.keyboardWords
            a.vc += b.voiceChars; a.vw += b.voiceWords
            byDay[day] = a
        }
        let fmt = DateFormatter(); fmt.calendar = calendar; fmt.timeZone = calendar.timeZone; fmt.dateFormat = "M/d"
        return (0..<days).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let a = byDay[date] ?? Agg()
            return StatPoint(label: fmt.string(from: date), date: date,
                             keyboardChars: a.kc, keyboardWords: a.kw,
                             voiceChars: a.vc, voiceWords: a.vw)
        }
    }

    /// 把全部桶按天分组，升序返回（用于导出/热力图）。label 为 "yyyy-MM-dd"。
    public static func groupByDay(buckets: [MinuteBucket], calendar: Calendar) -> [StatPoint] {
        var byDay: [Date: Agg] = [:]
        for b in buckets {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(b.start)))
            var a = byDay[day] ?? Agg()
            a.kc += b.keyboardChars; a.kw += b.keyboardWords
            a.vc += b.voiceChars; a.vw += b.voiceWords
            byDay[day] = a
        }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = calendar.timeZone
        return byDay.keys.sorted().map { day in
            let a = byDay[day]!
            return StatPoint(label: fmt.string(from: day), date: day,
                             keyboardChars: a.kc, keyboardWords: a.kw,
                             voiceChars: a.vc, voiceWords: a.vw)
        }
    }
}
