import SwiftUI
import Charts
import InputStatsCore

struct StatsView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var monitor = MonitorStatus.shared
    var compact = false
    var onOpenSettings: () -> Void
    var onOpenTools: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 24) {
            if compact {
                compactHeader
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("输入统计").font(.largeTitle.bold())
                        Text("统计视图每 5 分钟刷新，输入持续记录。").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("统计单位", selection: $store.metric) {
                        ForEach(StatsStore.Metric.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
                HStack(spacing: 7) {
                    Circle().fill(settings.paused ? .orange : monitor.running ? .green : .red).frame(width: 7, height: 7)
                    Text(settings.paused ? "统计已暂停" : monitor.detail).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !monitor.running { Button("重试连接") { InputMonitor.shared.start() }.font(.caption) }
                    Button(settings.paused ? "继续" : "暂停") { settings.paused.toggle() }.font(.caption)
                }
            }
            if let error = monitor.storageError ?? store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            summary
            HStack {
                Picker("时间范围", selection: $store.mode) {
                    Text("今天").tag(StatsStore.Mode.today)
                    Text("近 \(settings.weekDays) 天").tag(StatsStore.Mode.week)
                    Text("近一年").tag(StatsStore.Mode.year)
                }.pickerStyle(.segmented).labelsHidden()
                    .controlSize(compact ? .small : .regular)
                    .frame(width: compact ? 190 : 340, alignment: .leading)
                Spacer(minLength: 8)
                if compact {
                    if store.mode == .year {
                        Text("每日合计").font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 10) {
                            legendItem("键盘", color: .blue)
                            legendItem("语音", color: .green)
                        }
                    }
                } else {
                    Picker("输入来源", selection: $settings.sourceMode) {
                        Text("自动 · Fn").tag("auto")
                        Text("键盘").tag("keyboard")
                        Text("语音").tag("voice")
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
                    Text("一个汉字计一词 · 字母 / 数字连续串计一词 · 密码区域跳过")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { onOpenSettings() } label: { Image(systemName: "gearshape") }.help("设置")
                }
            }
        }
        .padding(compact ? 14 : 30)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { store.activate() }
        .onDisappear { store.deactivate() }
    }

    private var statusDescription: String { settings.paused ? "统计已暂停" : monitor.detail }
    private var legacyExplanation: String { "此范围包含旧版的删除倒扣记录；历史数据保留原值，新版只累计新增输入。" }

    private var compactHeader: some View {
        HStack(spacing: 9) {
            Text("输入统计").font(.system(size: 13, weight: .semibold)).fixedSize()
            HStack(spacing: 5) {
                Circle().fill(settings.paused ? .orange : monitor.running ? .green : .red).frame(width: 6, height: 6)
                Text(statusDescription).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }.help(statusDescription).accessibilityElement(children: .ignore).accessibilityLabel(statusDescription)
                .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(-1)
            Picker("统计单位", selection: $store.metric) {
                ForEach(StatsStore.Metric.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 106)
            if !monitor.running {
                Button { InputMonitor.shared.start() } label: { Image(systemName: "arrow.clockwise").frame(width: 20, height: 22) }
                    .buttonStyle(.plain).help("重试连接").accessibilityLabel("重试连接")
            }
            Button { settings.paused.toggle() } label: {
                Image(systemName: settings.paused ? "play.fill" : "pause.fill").font(.system(size: 11)).frame(width: 22, height: 22)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .help(settings.paused ? "继续统计" : "暂停统计").accessibilityLabel(settings.paused ? "继续统计" : "暂停统计")
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
            Divider()
            HStack(spacing: 8) {
                Text("5 分钟刷新 · 本机计数").font(.system(size: 10)).foregroundStyle(.secondary)
                if store.containsLegacyCorrections {
                    Label("旧版记录", systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(.secondary)
                        .help(legacyExplanation).accessibilityLabel(legacyExplanation)
                }
                Spacer(minLength: 0)
                Button(action: onOpenTools) { Label("MacToys", systemImage: "arrow.up.right.square") }
                    .font(.system(size: 11)).buttonStyle(.plain).help("打开 MacToys 主窗口").accessibilityLabel("打开 MacToys")
                Button(action: onOpenSettings) { Image(systemName: "gearshape").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help("设置").accessibilityLabel("设置")
            }
        }
    }

    private var summary: some View {
        let keyboard = max(0, store.points.reduce(0) { $0 + (store.metric == .chars ? $1.keyboardChars : $1.keyboardWords) })
        let voice = max(0, store.points.reduce(0) { $0 + (store.metric == .chars ? $1.voiceChars : $1.voiceWords) })
        return HStack(spacing: compact ? 8 : 16) {
            stat("键盘", keyboard, "keyboard", .blue)
            stat("语音", voice, "waveform", .green)
            stat("合计", keyboard + voice, "sum", .primary)
        }
    }
    private func stat(_ title: String, _ value: Int, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 12) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted(.number.grouping(.automatic)))
                .font(.system(size: compact ? 23 : 36, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.35)
                .allowsTightening(true).accessibilityLabel("\(title) \(value) \(store.metric == .chars ? "字符" : "单词")")
                .help("\(title)：\(value) \(store.metric == .chars ? "字符" : "单词")")
            if !compact { Text(store.metric == .chars ? "字符" : "单词").font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 46 : 110, alignment: .leading).padding(compact ? 10 : 20)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: compact ? 8 : 12))
    }
    private var chart: some View {
        let isWords = store.metric == .words
        let maximum = store.points.map { max(0, isWords ? $0.keyboardWords : $0.keyboardChars) + max(0, isWords ? $0.voiceWords : $0.voiceChars) }.max() ?? 0
        let unit: Calendar.Component = store.mode == .today ? .hour : .day
        return Chart {
            ForEach(store.points) { p in
                BarMark(x: .value("时间", p.date, unit: unit), y: .value("数量", max(0, isWords ? p.keyboardWords : p.keyboardChars)))
                    .foregroundStyle(by: .value("来源", "键盘"))
                BarMark(x: .value("时间", p.date, unit: unit), y: .value("数量", max(0, isWords ? p.voiceWords : p.voiceChars)))
                    .foregroundStyle(by: .value("来源", "语音"))
            }
        }
        .chartForegroundStyleScale(["键盘": Color.blue, "语音": Color.green])
        .chartYScale(domain: 0...max(10, Double(maximum) * 1.15))
        .chartXAxis {
            if store.mode == .today {
                AxisMarks(values: .stride(by: .hour, count: compact ? 6 : 3)) { value in
                    AxisGridLine(); AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.hour(settings.use24Hour ? .defaultDigits(amPM: .omitted) : .defaultDigits(amPM: .abbreviated))))
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
                        Text(n >= 100_000_000 ? "\((n / 100_000_000).formatted(.number.precision(.fractionLength(0...1))))亿" :
                             n >= 10_000 ? "\((n / 10_000).formatted(.number.precision(.fractionLength(0...1))))万" :
                             n.formatted(.number.precision(.fractionLength(0))))
                    }
                }
            }
        }
        .chartLegend(position: .top, alignment: .trailing)
        .chartLegend(compact ? .hidden : .visible)
        .frame(height: compact ? 144 : 260)
        .overlay {
            if maximum == 0 { Text("开始输入后，这里会显示统计趋势").foregroundStyle(.secondary).font(.callout) }
        }
    }
}
