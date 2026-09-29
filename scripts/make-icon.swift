import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, side) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let size = CGFloat(side)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let box = NSRect(x: size * 0.07, y: size * 0.07, width: size * 0.86, height: size * 0.86)
    let bg = NSBezierPath(roundedRect: box, xRadius: size * 0.19, yRadius: size * 0.19)
    NSGradient(starting: NSColor(calibratedWhite: 0.98, alpha: 1), ending: NSColor(calibratedWhite: 0.86, alpha: 1))!.draw(in: bg, angle: -90)
    let colors: [NSColor] = [.systemBlue, .systemTeal, .systemIndigo, .systemGreen]
    for i in 0..<4 {
        let x = size * (i % 2 == 0 ? 0.22 : 0.52)
        let y = size * (i < 2 ? 0.52 : 0.22)
        colors[i].setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: size * 0.26, height: size * 0.26), xRadius: size * 0.065, yRadius: size * 0.065).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
}
