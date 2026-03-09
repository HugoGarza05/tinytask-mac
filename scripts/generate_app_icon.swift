import AppKit
import Foundation

let outputRoot = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
let appIconSetURL = outputRoot.appendingPathComponent("packaging/macos/AppHost/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let iconSetURL = outputRoot.appendingPathComponent("packaging/macos/AppHost/Resources/AppIcon.iconset", isDirectory: true)

let sizes: [(filename: String, points: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

try FileManager.default.createDirectory(at: appIconSetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)

for size in sizes {
    let image = renderIcon(size: NSSize(width: size.points, height: size.points))
    let data = try pngData(for: image, size: NSSize(width: size.points, height: size.points))
    try data.write(to: appIconSetURL.appendingPathComponent(size.filename))
    try data.write(to: iconSetURL.appendingPathComponent(size.filename))
}

func renderIcon(size: NSSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()

    let bounds = NSRect(origin: .zero, size: size)
    let background = NSBezierPath(roundedRect: bounds, xRadius: size.width * 0.22, yRadius: size.height * 0.22)
    NSColor(calibratedRed: 0.012, green: 0.066, blue: 0.082, alpha: 1.0).setFill()
    background.fill()

    let inset = size.width * 0.18
    let cardRect = bounds.insetBy(dx: inset, dy: inset)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.341, green: 0.961, blue: 1.0, alpha: 1.0),
        NSColor(calibratedRed: 0.071, green: 0.722, blue: 0.769, alpha: 1.0)
    ])!
    let strokePath = NSBezierPath(roundedRect: cardRect, xRadius: size.width * 0.12, yRadius: size.height * 0.12)
    gradient.draw(in: strokePath, angle: 135)

    let innerRect = cardRect.insetBy(dx: size.width * 0.034, dy: size.height * 0.034)
    let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: size.width * 0.09, yRadius: size.height * 0.09)
    NSColor(calibratedRed: 0.02, green: 0.114, blue: 0.137, alpha: 0.96).setFill()
    innerPath.fill()

    let letterRect = NSRect(
        x: size.width * 0.26,
        y: size.height * 0.27,
        width: size.width * 0.48,
        height: size.height * 0.46
    )
    let barWidth = letterRect.width * 0.24
    let topBarHeight = letterRect.height * 0.18
    let stemPath = NSBezierPath(roundedRect: NSRect(x: letterRect.minX, y: letterRect.minY, width: barWidth, height: letterRect.height), xRadius: barWidth * 0.48, yRadius: barWidth * 0.48)
    let topPath = NSBezierPath(roundedRect: NSRect(x: letterRect.minX, y: letterRect.maxY - topBarHeight, width: letterRect.width, height: topBarHeight), xRadius: topBarHeight * 0.48, yRadius: topBarHeight * 0.48)
    gradient.draw(in: stemPath, angle: 135)
    gradient.draw(in: topPath, angle: 135)

    let accentDiameter = size.width * 0.18
    let accentRect = NSRect(
        x: size.width * 0.66,
        y: size.height * 0.18,
        width: accentDiameter,
        height: accentDiameter
    )
    let accentPath = NSBezierPath(ovalIn: accentRect)
    NSColor(calibratedRed: 1.0, green: 0.518, blue: 0.443, alpha: 0.96).setFill()
    accentPath.fill()

    image.unlockFocus()
    return image
}

func pngData(for image: NSImage, size: NSSize) throws -> Data {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )

    guard let representation else {
        throw CocoaError(.fileWriteUnknown)
    }

    representation.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }

    return data
}
