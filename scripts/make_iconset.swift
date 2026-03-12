import AppKit
import Foundation

struct IconSpec {
    let filename: String
    let size: CGFloat
}

let fm = FileManager.default
let root = URL(fileURLWithPath: "/Volumes/SSD/data/src_code/codexproj/ytd")
let sourceURL = root.appendingPathComponent("assets/VideoEasyTool-icon-1024.png")
let iconsetURL = root.appendingPathComponent("assets/AppIcon.iconset")

let specs: [IconSpec] = [
    .init(filename: "icon_16x16.png", size: 16),
    .init(filename: "icon_16x16@2x.png", size: 32),
    .init(filename: "icon_32x32.png", size: 32),
    .init(filename: "icon_32x32@2x.png", size: 64),
    .init(filename: "icon_128x128.png", size: 128),
    .init(filename: "icon_128x128@2x.png", size: 256),
    .init(filename: "icon_256x256.png", size: 256),
    .init(filename: "icon_256x256@2x.png", size: 512),
    .init(filename: "icon_512x512.png", size: 512),
    .init(filename: "icon_512x512@2x.png", size: 1024)
]

guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Failed to load source image at \(sourceURL.path)\n", stderr)
    exit(1)
}

try? fm.removeItem(at: iconsetURL)
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for spec in specs {
    let outputURL = iconsetURL.appendingPathComponent(spec.filename)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(spec.size),
        pixelsHigh: Int(spec.size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )

    guard let rep else {
        fputs("Failed to create bitmap rep for \(spec.filename)\n", stderr)
        exit(1)
    }

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current = context
    context?.imageInterpolation = .high
    source.draw(
        in: NSRect(x: 0, y: 0, width: spec.size, height: spec.size),
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode PNG for \(spec.filename)\n", stderr)
        exit(1)
    }

    try png.write(to: outputURL)
    print("Wrote \(spec.filename)")
}
