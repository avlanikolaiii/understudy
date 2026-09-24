// Draws the app icon: the same mark as the website's favicon (web/src/static/favicon.svg),
// a dark rounded square with the yellow dot, placed on Apple's macOS icon grid
// (an 824-point square inside a 1024-point canvas).
//   swift app/scripts/make-icon.swift app/Resources/AppIcon.iconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let ground = NSColor(srgbRed: 0x10 / 255.0, green: 0x12 / 255.0, blue: 0x17 / 255.0, alpha: 1)   // #101217
let dot = NSColor(srgbRed: 0xF4 / 255.0, green: 0xC5 / 255.0, blue: 0x34 / 255.0, alpha: 1)      // #F4C534

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    // Favicon proportions on a 32-unit square: corner radius 7, dot radius 6.
    let side = 824 * scale
    let square = NSRect(x: 100 * scale, y: 100 * scale, width: side, height: side)
    ground.setFill()
    NSBezierPath(roundedRect: square, xRadius: side * 7 / 32, yRadius: side * 7 / 32).fill()
    let r = side * 6 / 32
    dot.setFill()
    NSBezierPath(ovalIn: NSRect(x: square.midX - r, y: square.midY - r, width: r * 2, height: r * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: out.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2).write(to: out.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
print("Wrote \(out.path)")
