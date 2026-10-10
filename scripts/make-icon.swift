// Draws Resources/AppIcon.icns: the lock screen itself, shrunk onto a black tile.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let cream = NSColor(srgbRed: 0xEB / 255, green: 0xDB / 255, blue: 0xB2 / 255, alpha: 1)

func font(_ size: CGFloat) -> NSFont {
    NSFont(name: "Cousine Nerd Font Mono", size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: .light)
}

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

    let center = NSMutableParagraphStyle()
    center.alignment = .center
    let label = NSAttributedString(string: "locked", attributes: [
        .font: font(112), .foregroundColor: cream, .paragraphStyle: center,
    ])
    let labelHeight = label.size().height
    label.draw(in: NSRect(x: 100, y: 512 + 24, width: 824, height: labelHeight))

    let field = NSRect(x: 262, y: 512 - 24 - 96, width: 500, height: 96)
    let fieldPath = NSBezierPath(roundedRect: field.insetBy(dx: 3, dy: 3), xRadius: 18, yRadius: 18)
    cream.withAlphaComponent(0.3).setStroke()
    fieldPath.lineWidth = 6
    fieldPath.stroke()
    let dots = NSAttributedString(string: "••••", attributes: [
        .font: font(72), .foregroundColor: cream.withAlphaComponent(0.85), .paragraphStyle: center,
    ])
    let dotsHeight = dots.size().height
    dots.draw(in: NSRect(x: field.minX, y: field.midY - dotsHeight / 2, width: field.width, height: dotsHeight))

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
