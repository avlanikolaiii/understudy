// Draws the app icon: the glowing dot from the website header (`.bulb` in web/src/assets/site.css)
// on a dark rounded square, placed on Apple's macOS icon grid (824-point square in a 1024 canvas).
// The page draws the dot as three layers, in units of its 6-px radius:
//   dot r=6 · ring r=10 at 30% (box-shadow 0 0 0 4px) · glow spread to r=12, blurred 22 px, at 55%.
//   swift app/scripts/make-icon.swift app/Resources/AppIcon.iconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let ground = NSColor(srgbRed: 0x10 / 255.0, green: 0x12 / 255.0, blue: 0x17 / 255.0, alpha: 1)   // --ground #101217
let hl = NSColor(srgbRed: 0xE0 / 255.0, green: 0xB2 / 255.0, blue: 0x2A / 255.0, alpha: 1)       // dark --hl #E0B22A

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let scale = CGFloat(pixels) / 1024
    let side = 824 * scale
    let square = NSRect(x: 100 * scale, y: 100 * scale, width: side, height: side)
    let shape = NSBezierPath(roundedRect: square, xRadius: side * 7 / 32, yRadius: side * 7 / 32)
    ground.setFill()
    shape.fill()
    shape.addClip()

    let center = CGPoint(x: square.midX, y: square.midY)
    let unit = side * 0.0185            // one "px" of the page's 12-px bulb
    // Glow: strongest at the center, about half strength at r=12, gone by r=34 (spread 6 + blur 22).
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        hl.withAlphaComponent(0.55).cgColor, hl.withAlphaComponent(0.42).cgColor,
        hl.withAlphaComponent(0.26).cgColor, hl.withAlphaComponent(0.08).cgColor, hl.withAlphaComponent(0).cgColor,
    ] as CFArray, locations: [0, 0.22, 0.38, 0.66, 1])!
    cg.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 34 * unit, options: [])
    // Ring, then the dot itself.
    hl.withAlphaComponent(0.30).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 10 * unit, y: center.y - 10 * unit, width: 20 * unit, height: 20 * unit)).fill()
    hl.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 6 * unit, y: center.y - 6 * unit, width: 12 * unit, height: 12 * unit)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: out.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2).write(to: out.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
print("Wrote \(out.path)")
