import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputURL = root.appendingPathComponent("assets/dmg-background.png")

let canvasSize = NSSize(width: 720, height: 440)
let arrowRect = NSRect(x: 300, y: 184, width: 120, height: 48)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = NSRect(origin: .zero, size: canvasSize)

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.93, alpha: 1.0),
    NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.90, alpha: 1.0)
])!
gradient.draw(in: bounds, angle: -12)

NSColor(calibratedRed: 0.84, green: 0.81, blue: 0.75, alpha: 0.16).setFill()
NSBezierPath(roundedRect: NSRect(x: 32, y: 34, width: 656, height: 372), xRadius: 30, yRadius: 30).fill()

NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.28).setFill()
NSBezierPath(ovalIn: NSRect(x: -24, y: 268, width: 320, height: 176)).fill()
NSBezierPath(ovalIn: NSRect(x: 466, y: -24, width: 240, height: 164)).fill()

let title = "Install Video Easy Tool"
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1.0)
]
title.draw(at: NSPoint(x: 48, y: 354), withAttributes: titleAttrs)

let subtitle = "Drag the app to Applications"
let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.32, alpha: 1.0)
]
subtitle.draw(at: NSPoint(x: 50, y: 318), withAttributes: subtitleAttrs)

let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: arrowRect.minX, y: arrowRect.midY))
arrowPath.line(to: NSPoint(x: arrowRect.maxX - 24, y: arrowRect.midY))
arrowPath.lineWidth = 12
NSColor(calibratedRed: 0.92, green: 0.52, blue: 0.24, alpha: 0.92).setStroke()
arrowPath.lineCapStyle = .round
arrowPath.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: arrowRect.maxX - 30, y: arrowRect.midY + 22))
head.line(to: NSPoint(x: arrowRect.maxX, y: arrowRect.midY))
head.line(to: NSPoint(x: arrowRect.maxX - 30, y: arrowRect.midY - 22))
head.lineWidth = 12
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

let footer = "macOS 14+  •  Apple Silicon"
let footerAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.38, alpha: 1.0)
]
footer.draw(at: NSPoint(x: 50, y: 52), withAttributes: footerAttrs)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode dmg background image\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
print("Wrote \(outputURL.path)")
