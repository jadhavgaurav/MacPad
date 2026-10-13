import AppKit

// Draws the MacPad app icon at every size macOS needs and writes an .iconset folder.
// Usage: swift Scripts/make-icon.swift <output.iconset>

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }

    // Squircle tile
    let tile = NSBezierPath(roundedRect: rect(100, 100, 824, 824), xRadius: 184 * s, yRadius: 184 * s)
    NSGradient(colors: [NSColor(srgbRed: 0.86, green: 0.91, blue: 0.97, alpha: 1), NSColor(srgbRed: 0.72, green: 0.80, blue: 0.92, alpha: 1)])!
        .draw(in: tile, angle: -90)

    // Paper sheet with a soft shadow
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 28 * s
    shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(srgbRed: 0.99, green: 0.99, blue: 1, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect(262, 190, 500, 644), xRadius: 44 * s, yRadius: 44 * s).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Text lines and caret
    NSColor(srgbRed: 0.66, green: 0.70, blue: 0.77, alpha: 1).setFill()
    for (index, width) in [360.0, 300.0, 340.0, 220.0].enumerated() {
        NSBezierPath(roundedRect: rect(322, 690 - CGFloat(index) * 96, CGFloat(width), 36), xRadius: 18 * s, yRadius: 18 * s).fill()
    }
    NSColor(srgbRed: 0.04, green: 0.48, blue: 1, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect(560, 306, 18, 74), xRadius: 9 * s, yRadius: 9 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift make-icon.swift <output.iconset>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let files: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, size) in files { try render(size: size).write(to: output.appendingPathComponent(name)) }
print("Wrote \(files.count) images to \(output.path)")
