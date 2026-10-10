// Draws Resources/AppIcon.icns: a padlock in the lock screen's style on a black tile.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let cream = NSColor(srgbRed: 0xEB / 255, green: 0xDB / 255, blue: 0xB2 / 255, alpha: 1)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt tile centred on a 1024pt canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSColor.black.setFill()
    shape.fill()
    cream.withAlphaComponent(0.12).setStroke()
    shape.lineWidth = 4
    shape.stroke()

    // A padlock drawn with the lock screen's thin cream strokes.
    let stroke: CGFloat = 26
    cream.setStroke()

    let body = NSRect(x: 342, y: 257, width: 340, height: 264)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 36, yRadius: 36)
    bodyPath.lineWidth = stroke
    bodyPath.stroke()

    // Shackle: two legs rising from the body, joined by a half circle.
    let radius: CGFloat = 108
    let shackleTop: CGFloat = 647
    let shackle = NSBezierPath()
    shackle.move(to: NSPoint(x: 512 - radius, y: body.maxY))
    shackle.line(to: NSPoint(x: 512 - radius, y: shackleTop))
    shackle.appendArc(withCenter: NSPoint(x: 512, y: shackleTop), radius: radius,
                      startAngle: 180, endAngle: 0, clockwise: true)
    shackle.line(to: NSPoint(x: 512 + radius, y: body.maxY))
    shackle.lineWidth = stroke
    shackle.lineCapStyle = .butt
    shackle.stroke()

    // Keyhole: one solid shape, a circle over a short rounded bar.
    let keyhole = NSBezierPath(ovalIn: NSRect(x: 512 - 26, y: body.midY - 4, width: 52, height: 52))
    keyhole.append(NSBezierPath(roundedRect: NSRect(x: 512 - 11, y: body.midY - 52, width: 22, height: 70),
                                xRadius: 11, yRadius: 11))
    keyhole.windingRule = .nonZero
    cream.setFill()
    keyhole.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
