import Foundation

/// The picker exports opaque, 8-bit sRGB, so all displayed formats describe the same color.
public struct ScreenColor: Equatable, Hashable, Identifiable, Codable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public var id: String { hex }

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red; self.green = green; self.blue = blue
    }

    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard [3, 6].contains(text.count), text.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { return nil }
        if text.count == 3 { text = text.map { String(repeating: String($0), count: 2) }.joined() }
        guard let value = UInt32(text, radix: 16) else { return nil }
        red = UInt8((value >> 16) & 255); green = UInt8((value >> 8) & 255); blue = UInt8(value & 255)
    }

    public var hex: String { String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue)) }
    public var rgb: String { "rgb(\(red), \(green), \(blue))" }
    public var hsl: String {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        let lightness = (high + low) / 2
        var hue = 0.0, saturation = 0.0
        if delta > 0 {
            saturation = delta / (1 - abs(2 * lightness - 1))
            if high == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if high == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            hue *= 60
            if hue < 0 { hue += 360 }
        }
        func decimal(_ value: Double) -> String {
            let text = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        }
        // Rounding near red must not produce a spurious 360-degree hue.
        hue = (hue * 10).rounded() / 10
        if hue >= 360 { hue = 0 }
        return "hsl(\(decimal(hue)), \(decimal(saturation * 100))%, \(decimal(lightness * 100))%)"
    }

    public var prefersDarkText: Bool {
        func linear(_ byte: UInt8) -> Double {
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
    }

    public func formatted(_ format: ColorTextFormat) -> String {
        switch format { case .hex: return hex; case .rgb: return rgb; case .hsl: return hsl }
    }
}

public enum ColorTextFormat: String, CaseIterable, Identifiable {
    case hex = "HEX", rgb = "RGB", hsl = "HSL"
    public var id: String { rawValue }
}

/// A bounded, newest-first history. Re-selecting a color moves it to the front.
public struct ColorHistory {
    public static let limit = 24
    public private(set) var colors: [ScreenColor]
    public init(hexValues: [String] = []) {
        var seen = Set<ScreenColor>()
        colors = Array(hexValues.compactMap(ScreenColor.init(hex:)).filter { seen.insert($0).inserted }.prefix(Self.limit))
    }
    public mutating func record(_ color: ScreenColor) {
        colors.removeAll { $0 == color }; colors.insert(color, at: 0)
        colors = Array(colors.prefix(Self.limit))
    }
}
