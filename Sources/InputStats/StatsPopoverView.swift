import SwiftUI

private struct StatsContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Fit the document's height while keeping a scrollable viewport within the display.
struct StatsPopoverView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var settings: AppSettings
    let size: NSSize
    var onOpenSettings: () -> Void
    var onOpenTools: () -> Void
    var onHeightChange: (CGFloat) -> Void
    @State private var contentHeight: CGFloat = Self.initialHeight
    static let initialHeight: CGFloat = 360

    static func contentSize(in visibleFrame: NSRect) -> NSSize {
        // Leave room for the popover's arrow, border and screen edges. visibleFrame
        // already excludes the menu bar and Dock, and uses points, not pixels.
        NSSize(width: min(460, max(1, visibleFrame.width - 32)),
               height: min(600, max(1, visibleFrame.height - 40)))
    }

    var body: some View {
        ScrollView(.vertical) {
            StatsView(store: store, settings: settings, compact: true,
                      onOpenSettings: onOpenSettings, onOpenTools: onOpenTools)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: StatsContentHeightKey.self, value: geometry.size.height)
                })
        }
        .defaultScrollAnchor(.top)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: size.width, height: min(size.height, contentHeight), alignment: .topLeading)
        .onPreferenceChange(StatsContentHeightKey.self) { measuredHeight in
            let height = ceil(measuredHeight)
            guard height.isFinite, height > 0, abs(height - contentHeight) >= 1 else { return }
            contentHeight = height
            onHeightChange(min(size.height, height))
        }
    }
}
