import AppKit
import UniformTypeIdentifiers
import InputStatsCore

enum Exporter {
    enum Format { case csv, json }
    static func export(_ format: Format) {
        do {
            try InputMonitor.shared.flushNow()
            let points = Aggregator.groupByDay(buckets: try Database.shared.buckets(), calendar: .current)
            let data: Data
            let ext: String
            let type: UTType
            switch format {
            case .csv:
                var text = "date,keyboard_chars,keyboard_words,voice_chars,voice_words\n"
                for p in points { text += "\(p.label),\(p.keyboardChars),\(p.keyboardWords),\(p.voiceChars),\(p.voiceWords)\n" }
                data = Data(text.utf8); ext = "csv"; type = .commaSeparatedText
            case .json:
                let rows: [[String: Any]] = points.map { ["date": $0.label, "keyboard_chars": $0.keyboardChars,
                    "keyboard_words": $0.keyboardWords, "voice_chars": $0.voiceChars, "voice_words": $0.voiceWords] }
                data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
                ext = "json"; type = .json
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [type]
            panel.nameFieldStringValue = "inputstats-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.omitted))).\(ext)"
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url { try data.write(to: url, options: .atomic) }
        } catch {
            let alert = NSAlert(); alert.messageText = L("导出失败"); alert.informativeText = Database.errorDescription(error)
            alert.runModal()
        }
    }
}
