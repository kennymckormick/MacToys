import SwiftUI
import InputStatsCore

/// GitHub 式全年热力图：列=周，行=星期，颜色越深输入越多。
struct HeatmapView: View {
    let points: [StatPoint]      // 升序的每日数据（约 371 天）
    let useWords: Bool

    var fittingWidth: CGFloat? = nil
    private let gap: CGFloat = 2
    private let calendar = Calendar.current
    private var leading: Int { points.first.map { calendar.component(.weekday, from: $0.date) - 1 } ?? 0 }
    private var weeks: Int { max(1, Int(ceil(Double(leading + points.count) / 7.0))) }
    private var cell: CGFloat {
        guard let fittingWidth else { return 9 }
        return max(1, min(9, (fittingWidth - CGFloat(weeks - 1) * gap) / CGFloat(weeks)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            grid
            legend
        }
    }

    private func value(_ p: StatPoint) -> Int {
        useWords ? (p.keyboardWords + p.voiceWords) : (p.keyboardChars + p.voiceChars)
    }

    private var maxValue: Int { max(1, points.map(value).max() ?? 1) }

    private var grid: some View {
        // 首日对齐到星期（周日=1）。
        let maximum = maxValue
        let leading = self.leading, weeks = self.weeks, cell = self.cell

        return HStack(alignment: .top, spacing: gap) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { d in
                        let idx = w * 7 + d - leading
                        if idx >= 0 && idx < points.count {
                            let p = points[idx]
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: value(p), maximum: maximum))
                                .frame(width: cell, height: cell)
                                .help("\(p.label)：\(value(p)) \(useWords ? "词" : "字")")
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }

    private func color(for v: Int, maximum: Int) -> Color {
        guard v > 0 else { return Color.secondary.opacity(0.15) }
        let ratio = min(1, Double(v) / Double(maximum))
        return Color.green.opacity(0.25 + 0.75 * ratio)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("近一年 · 颜色越深输入越多").font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text("少").font(.caption2).foregroundStyle(.secondary)
            ForEach([0.0, 0.35, 0.6, 0.85, 1.0], id: \.self) { r in
                RoundedRectangle(cornerRadius: 2)
                    .fill(r == 0 ? Color.secondary.opacity(0.15) : Color.green.opacity(0.25 + 0.75 * r))
                    .frame(width: cell, height: cell)
            }
            Text("多").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
