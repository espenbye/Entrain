import AppKit

/// Renders the app icon set: a waveform on an indigo-to-teal gradient.
///
///     swift Tools/icon.swift
///
/// Writes every macOS size into Resources/Assets.xcassets/AppIcon.appiconset.
let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
let directory = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    // Draw into an explicit bitmap so the pixel size does not follow the screen's scale.
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let side = CGFloat(pixels)
    // macOS icons leave a margin inside the canvas; the rounded square fills 80%.
    let inset = side * 0.1
    let rect = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.29, green: 0.25, blue: 0.75, alpha: 1),
        ending: NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.66, alpha: 1)
    )!
    gradient.draw(in: path, angle: -60)

    let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.5, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let symbolRect = NSRect(
        x: rect.midX - symbol.size.width / 2,
        y: rect.midY - symbol.size.height / 2,
        width: symbol.size.width,
        height: symbol.size.height
    )
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (points, scale) in sizes {
    let filename = "icon_\(points)x\(points)@\(scale)x.png"
    try render(pixels: points * scale).write(to: directory.appendingPathComponent(filename))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: directory.appendingPathComponent("Contents.json"))
print("wrote \(sizes.count) icons to \(directory.path)")
