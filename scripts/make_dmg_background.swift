import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputURL = root.appendingPathComponent("assets/dmg-background.png")
let iconURL = root.appendingPathComponent("assets/VideoEasyTool-icon-1024.png")

let canvasSize = NSSize(width: 720, height: 440)
let arrowRect = NSRect(x: 304, y: 170, width: 112, height: 64)
let iconRect = NSRect(x: 96, y: 146, width: 160, height: 160)
let appsRect = NSRect(x: 476, y: 146, width: 160, height: 160)

guard let icon = NSImage(contentsOf: iconURL) else {
    fputs("Failed to load icon at \(iconURL.path)\n", stderr)
    exit(1)
}

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
    NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.90, alpha: 1.0),
    NSColor(calibratedRed: 0.93, green: 0.91, blue: 0.85, alpha: 1.0)
])!
gradient.draw(in: bounds, angle: -18)

NSColor(calibratedRed: 0.86, green: 0.82, blue: 0.74, alpha: 0.22).setFill()
NSBezierPath(roundedRect: NSRect(x: 28, y: 30, width: 664, height: 380), xRadius: 28, yRadius: 28).fill()

NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.55).setFill()
NSBezierPath(ovalIn: NSRect(x: -36, y: 252, width: 344, height: 210)).fill()
NSBezierPath(ovalIn: NSRect(x: 410, y: -18, width: 280, height: 190)).fill()

let title = "Install Video Easy Tool"
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1.0)
]
title.draw(at: NSPoint(x: 48, y: 362), withAttributes: titleAttrs)

let subtitle = "Drag the app to Applications"
let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.32, alpha: 1.0)
]
subtitle.draw(at: NSPoint(x: 50, y: 326), withAttributes: subtitleAttrs)

let shadow = NSShadow()
shadow.shadowBlurRadius = 18
shadow.shadowOffset = NSSize(width: 0, height: -6)
shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.16)

NSGraphicsContext.saveGraphicsState()
shadow.set()
icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

let appBadgePath = NSBezierPath(roundedRect: NSRect(x: 104, y: 118, width: 144, height: 28), xRadius: 14, yRadius: 14)
NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 0.88).setFill()
appBadgePath.fill()
let appBadgeAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
    .foregroundColor: NSColor.white
]
"Video Easy Tool".draw(in: NSRect(x: 118, y: 124, width: 118, height: 18), withAttributes: appBadgeAttrs)

let folderPath = NSBezierPath(roundedRect: appsRect, xRadius: 28, yRadius: 28)
NSColor(calibratedRed: 0.22, green: 0.52, blue: 0.96, alpha: 0.14).setFill()
folderPath.fill()

let folderBody = NSBezierPath(roundedRect: NSRect(x: appsRect.minX + 18, y: appsRect.minY + 34, width: 124, height: 88), xRadius: 18, yRadius: 18)
NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.98, alpha: 1.0).setFill()
folderBody.fill()

let folderTab = NSBezierPath(roundedRect: NSRect(x: appsRect.minX + 32, y: appsRect.minY + 102, width: 52, height: 24), xRadius: 10, yRadius: 10)
NSColor(calibratedRed: 0.31, green: 0.62, blue: 1.0, alpha: 1.0).setFill()
folderTab.fill()

let appsLabelAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1.0)
]
"Applications".draw(in: NSRect(x: appsRect.minX + 24, y: appsRect.minY + 8, width: 120, height: 22), withAttributes: appsLabelAttrs)

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
