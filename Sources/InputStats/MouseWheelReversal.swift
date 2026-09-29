import CoreGraphics

struct ScrollReversalOptions: Equatable {
    var enabled = false
    var vertical = true
    var horizontal = false
}

enum MouseWheelReversal {
    /// Edit the original wheel event without reposting it or changing acceleration.
    @discardableResult
    static func apply(to event: CGEvent, options: ScrollReversalOptions) -> Bool {
        guard options.enabled, options.vertical || options.horizontal,
              event.type == .scrollWheel,
              event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
              event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0,
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0,
              event.getIntegerValueField(.eventSourceUnixProcessID) == 0 else { return false }

        // Read every representation before writing: changing a line delta also changes
        // its point/fixed-point fields on macOS. Restore those at their original scale.
        let y = Delta(event, line: .scrollWheelEventDeltaAxis1,
                      fixed: .scrollWheelEventFixedPtDeltaAxis1, point: .scrollWheelEventPointDeltaAxis1)
        let x = Delta(event, line: .scrollWheelEventDeltaAxis2,
                      fixed: .scrollWheelEventFixedPtDeltaAxis2, point: .scrollWheelEventPointDeltaAxis2)
        guard (!options.vertical || y.canReverse), (!options.horizontal || x.canReverse) else { return false }
        if options.vertical { y.reverse(event, line: .scrollWheelEventDeltaAxis1,
                                       fixed: .scrollWheelEventFixedPtDeltaAxis1, point: .scrollWheelEventPointDeltaAxis1) }
        if options.horizontal { x.reverse(event, line: .scrollWheelEventDeltaAxis2,
                                         fixed: .scrollWheelEventFixedPtDeltaAxis2, point: .scrollWheelEventPointDeltaAxis2) }
        return true
    }

    private struct Delta {
        let lines: Int64
        let fraction: Double
        let points: Int64
        init(_ event: CGEvent, line: CGEventField, fixed: CGEventField, point: CGEventField) {
            lines = event.getIntegerValueField(line)
            fraction = event.getDoubleValueField(fixed)
            points = event.getIntegerValueField(point)
        }
        var canReverse: Bool { lines != .min && points != .min && fraction.isFinite }
        func reverse(_ event: CGEvent, line: CGEventField, fixed: CGEventField, point: CGEventField) {
            event.setIntegerValueField(line, value: -lines)
            event.setDoubleValueField(fixed, value: -fraction)
            event.setIntegerValueField(point, value: -points)
        }
    }
}
