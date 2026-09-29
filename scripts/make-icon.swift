import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, side) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let size = CGFloat(side)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let box = NSRect(x: size * 0.07, y: size * 0.07, width: size * 0.86, height: size * 0.86)
    let bg = NSBezierPath(roundedRect: box, xRadius: size * 0.19, yRadius: size * 0.19)
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.49, blue: 0.97, alpha: 1),
               ending: NSColor(srgbRed: 0.10, green: 0.25, blue: 0.72, alpha: 1))!.draw(in: bg, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    guard let tool = NSImage(systemSymbolName: "wrench.and.screwdriver.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
        fatalError("Tool symbol is unavailable")
    }
    let scale = size * 0.57 / max(tool.size.width, tool.size.height)
    let symbolSize = NSSize(width: tool.size.width * scale, height: tool.size.height * scale)
    tool.draw(in: NSRect(x: (size - symbolSize.width) / 2, y: (size - symbolSize.height) / 2,
                        width: symbolSize.width, height: symbolSize.height))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
}
