import SwiftUI
import Charts
import InputStatsCore

struct StatsView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var monitor = MonitorStatus.shared
    @ObservedObject private var language = Localization.shared
    var compact = false
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 24) {
            if compact {
                compactHeader
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("输入统计")).font(.largeTitle.bold())
                        Text(L("统计视图每 5 分钟刷新，输入持续记录。")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(L("统计单位"), selection: $store.metric) {
                        ForEach(StatsStore.Metric.allCases) { Text(L($0.rawValue)).tag($0) }
                    }.id(language.code).pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
                HStack(spacing: 7) {
                    Circle().fill(settings.paused ? .orange : monitor.running ? .green : .red).frame(width: 7, height: 7)
                    Text(settings.paused ? L("统计已暂停") : L(monitor.detail)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !monitor.running { Button(L("重试连接")) { InputMonitor.shared.start() }.font(.caption) }
                    Button(settings.paused ? L("继续") : L("暂停")) { settings.paused.toggle() }.font(.caption)
                }
            }
            if let error = monitor.storageError ?? store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            summary
            HStack {
                Picker(L("时间范围"), selection: $store.mode) {
                    Text(L("今天")).tag(StatsStore.Mode.today)
                    Text(L("近 %@ 天", String(describing: settings.weekDays))).tag(StatsStore.Mode.week)
                    Text(L("近一年")).tag(StatsStore.Mode.year)
                }.id(language.code).pickerStyle(.segmented).labelsHidden()
                    .controlSize(compact ? .small : .regular)
                    .frame(width: compact ? 190 : 340, alignment: .leading)
                Spacer(minLength: 8)
                if compact {
                    if store.mode == .year {
                        Text(L("每日合计")).font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 10) {
                            legendItem(L("键盘"), color: .blue)
                            legendItem(L("语音"), color: .green)
                        }
                    }
                } else {
                    Picker(L("输入来源"), selection: $settings.sourceMode) {
                        Text(L("自动 · Fn")).tag("auto")
                        Text(L("键盘")).tag("keyboard")
                        Text(L("语音")).tag("voice")
                    }.frame(width: 180)
                }
            }
            if store.mode == .year {
                if compact {
                    GeometryReader { geometry in
                        HeatmapView(points: store.points, useWords: store.metric == .words, fittingWidth: geometry.size.width)
                    }.frame(height: 86)
                } else {
                    ScrollView(.horizontal) {
                        HeatmapView(points: store.points, useWords: store.metric == .words).padding(.vertical, 12)
                    }.frame(height: 260, alignment: .center)
                }
            } else { chart }
            if store.containsLegacyCorrections && !compact {
                Text(legacyExplanation)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if compact {
                compactFooter
            } else {
                HStack {
                    Text(L("一个汉字计一词 · 字母 / 数字连续串计一词 · 密码区域跳过"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { onOpenSettings() } label: { Image(systemName: "gearshape") }.help(L("设置"))
                }
            }
        }
        .padding(.horizontal, compact ? 12 : 30)
        .padding(.vertical, compact ? 8 : 30)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .environment(\.locale, language.locale)
        .onAppear { store.activate() }
        .onDisappear { store.deactivate() }
    }

    private var statusDescription: String { settings.paused ? L("统计已暂停") : L(monitor.detail) }
    private var legacyExplanation: String { L("此范围包含旧版的删除倒扣记录；历史数据保留原值，新版只累计新增输入。") }

    private var compactHeader: some View {
        HStack(spacing: 9) {
            HStack(spacing: 5) {
                Circle().fill(settings.paused ? .orange : monitor.running ? .green : .red).frame(width: 6, height: 6)
                Text(statusDescription).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }.help(statusDescription).accessibilityElement(children: .ignore).accessibilityLabel(statusDescription)
                .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(-1)
            Picker(L("统计单位"), selection: $store.metric) {
                ForEach(StatsStore.Metric.allCases) { Text(L($0.rawValue)).tag($0) }
            }.id(language.code).pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: language.code == "en" ? 144 : 106)
            if !monitor.running {
                Button { InputMonitor.shared.start() } label: { Image(systemName: "arrow.clockwise").frame(width: 20, height: 22) }
                    .buttonStyle(.plain).help(L("重试连接")).accessibilityLabel(L("重试连接"))
            }
            Button { settings.paused.toggle() } label: {
                Image(systemName: settings.paused ? "play.fill" : "pause.fill").font(.system(size: 11)).frame(width: 22, height: 22)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .help(settings.paused ? L("继续统计") : L("暂停统计")).accessibilityLabel(settings.paused ? L("继续统计") : L("暂停统计"))
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }.fixedSize()
    }

    private var compactFooter: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(L("5 分钟刷新 · 本机计数")).font(.system(size: 10)).foregroundStyle(.secondary)
                if store.containsLegacyCorrections {
                    Label(L("旧版记录"), systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(.secondary)
                        .help(legacyExplanation).accessibilityLabel(legacyExplanation)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var summary: some View {
        let keyboard = max(0, store.points.reduce(0) { $0 + (store.metric == .chars ? $1.keyboardChars : $1.keyboardWords) })
        let voice = max(0, store.points.reduce(0) { $0 + (store.metric == .chars ? $1.voiceChars : $1.voiceWords) })
        return HStack(spacing: compact ? 6 : 16) {
            stat(L("键盘"), keyboard, "keyboard", .blue)
            stat(L("语音"), voice, "waveform", .green)
            stat(L("合计"), keyboard + voice, "sum", .primary)
        }
    }
    private func stat(_ title: String, _ value: Int, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 12) {
            Label(title, systemImage: symbol).font(compact ? .system(size: 10) : .caption).foregroundStyle(.secondary)
            Text(value.formatted(.number.grouping(.automatic)))
                .font(.system(size: compact ? 20 : 36, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.35)
                .allowsTightening(true).accessibilityLabel("\(title) \(value) \(store.metric == .chars ? L("字符") : L("单词"))")
                .help("\(title)：\(value) \(store.metric == .chars ? L("字符") : L("单词"))")
            if !compact { Text(store.metric == .chars ? L("字符") : L("单词")).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 34 : 110, alignment: .leading)
        .padding(.horizontal, compact ? 9 : 20).padding(.vertical, compact ? 6 : 20)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: compact ? 8 : 12))
    }
    private var chart: some View {
        let isWords = store.metric == .words
        let maximum = store.points.map { max(0, isWords ? $0.keyboardWords : $0.keyboardChars) + max(0, isWords ? $0.voiceWords : $0.voiceChars) }.max() ?? 0
        let unit: Calendar.Component = store.mode == .today ? .hour : .day
        let hour = DateFormatter()
        hour.locale = language.locale
        hour.dateFormat = settings.use24Hour ? (language.code == "en" ? "H" : "H'时'") : (language.code == "en" ? "h a" : "ah'时'")
        return Chart {
            ForEach(store.points) { p in
                BarMark(x: .value(L("时间"), p.date, unit: unit), y: .value(L("数量"), max(0, isWords ? p.keyboardWords : p.keyboardChars)))
                    .foregroundStyle(by: .value(L("来源"), L("键盘")))
                BarMark(x: .value(L("时间"), p.date, unit: unit), y: .value(L("数量"), max(0, isWords ? p.voiceWords : p.voiceChars)))
                    .foregroundStyle(by: .value(L("来源"), L("语音")))
            }
        }
        .id(language.code)
        .chartForegroundStyleScale([L("键盘"): Color.blue, L("语音"): Color.green])
        .chartYScale(domain: 0...max(10, Double(maximum) * 1.15))
        .chartXAxis {
            if store.mode == .today {
                AxisMarks(values: .stride(by: .hour, count: compact ? 6 : 3)) { value in
                    AxisGridLine(); AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(hour.string(from: date))
                        }
                    }
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: store.mode == .week ? max(1, settings.weekDays / 7) : 30)) {
                    AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                }
            }
        }
         .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: compact ? 3 : 5)) { value in
                AxisGridLine(); AxisTick()
                AxisValueLabel {
                    if let n = value.as(Double.self) {
                        Text(n.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(language.locale)))
                    }
                }
            }
        }
        .chartLegend(position: .top, alignment: .trailing)
        .chartLegend(compact ? .hidden : .visible)
        .frame(height: compact ? 100 : 260)
        .overlay {
            if maximum == 0 { Text(L("开始输入后，这里会显示统计趋势")).foregroundStyle(.secondary).font(.callout) }
        }
    }
}
