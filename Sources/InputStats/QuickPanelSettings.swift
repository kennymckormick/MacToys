import Foundation
import Combine

enum QuickTool: String, CaseIterable, Identifiable {
    case todo, notes, goals, input, colors, scroll, awake
    var id: String { rawValue }
}

/// Stores the list and its default together so the default always belongs to the list.
final class QuickPanelSettings: ObservableObject {
    static let limit = 4
    static let defaultTools: [QuickTool] = [.todo, .notes, .input, .colors]
    private static let key = "quickPanel.configuration"
    struct Configuration: Equatable {
        let tools: [QuickTool]
        let preferred: QuickTool
    }
    @Published private(set) var configuration: Configuration
    @Published private(set) var selection: QuickTool
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.key)
        var tools: [QuickTool] = []
        for raw in saved?["tools"] as? [String] ?? Self.defaultTools.map(\.rawValue) {
            if let tool = QuickTool(rawValue: raw), !tools.contains(tool), tools.count < Self.limit { tools.append(tool) }
        }
        if tools.isEmpty { tools = Self.defaultTools }
        let preferred = (saved?["preferred"] as? String).flatMap(QuickTool.init(rawValue:)) ?? .todo
        // Notes is always pinned. Preserve the user's preferred tool when migrating a full panel.
        if !tools.contains(.notes) {
            if tools.count == Self.limit, let index = tools.lastIndex(where: { $0 != preferred }) { tools.remove(at: index) }
            tools.insert(.notes, at: min(tools.firstIndex(of: .todo).map { $0 + 1 } ?? tools.count, tools.count))
        }
        let configuration = Configuration(tools: tools, preferred: tools.contains(preferred) ? preferred : tools[0])
        self.configuration = configuration
        selection = configuration.preferred
        persist()
    }

    func beginPresentation(selecting tool: QuickTool? = nil) {
        selection = tool.flatMap { configuration.tools.contains($0) ? $0 : nil } ?? configuration.preferred
    }

    func select(_ tool: QuickTool) {
        guard configuration.tools.contains(tool) else { return }
        selection = tool
    }

    @discardableResult func setIncluded(_ included: Bool, tool: QuickTool) -> Bool {
        var tools = configuration.tools
        if included {
            if tools.contains(tool) { return true }
            guard tools.count < Self.limit else { return false }
            tools.append(tool)
        } else {
            if tool == .notes { return false }
            if !tools.contains(tool) { return true }
            guard tools.count > 1 else { return false }
            tools.removeAll { $0 == tool }
        }
        let preferred = tools.contains(configuration.preferred) ? configuration.preferred : tools[0]
        configuration = Configuration(tools: tools, preferred: preferred)
        if !tools.contains(selection) { selection = preferred }
        persist()
        return true
    }

    func setPreferred(_ tool: QuickTool) {
        guard configuration.tools.contains(tool) else { return }
        configuration = Configuration(tools: configuration.tools, preferred: tool)
        persist()
    }

    func reload() {
        let restored = QuickPanelSettings(defaults: defaults)
        configuration = restored.configuration
        selection = configuration.preferred
    }

    private func persist() {
        defaults.set(["tools": configuration.tools.map(\.rawValue), "preferred": configuration.preferred.rawValue], forKey: Self.key)
    }
}
