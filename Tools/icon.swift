import AppKit

/// Renders the app icon set: an amplitude-modulated wave on a night gradient.
///
///     swift Tools/icon.swift
///
/// The wave is what the app does: a carrier tone whose loudness swells and
/// fades at the entrainment rate. Writes every macOS size, plus the single
/// full-bleed 1024 px icon iOS and watchOS mask themselves, into
/// Resources/Assets.xcassets/AppIcon.appiconset.
let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
let directory = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func render(pixels: Int, fullBleed: Bool = false) -> Data {
    // Draw into an explicit bitmap so the pixel size does not follow the screen's scale.
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    let side = CGFloat(pixels)
    // macOS icons leave a margin inside the canvas; the rounded square fills 80%.
    // iOS and watchOS want the whole canvas and round the corners themselves.
    let inset = fullBleed ? 0 : side * 0.1
    let rect = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let radius = fullBleed ? 0 : rect.width * 0.225
    let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Night sky: deep indigo at the top into a dark teal at the bottom.
    NSGradient(
        starting: NSColor(calibratedRed: 0.13, green: 0.10, blue: 0.36, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.28, blue: 0.36, alpha: 1)
    )!.draw(in: tile, angle: -75)

    // A soft pulse of light behind the wave, so the icon glows rather than sits flat.
    tile.addClip()
    let glow = NSGradient(colors: [
        NSColor(calibratedRed: 0.35, green: 0.75, blue: 0.85, alpha: 0.55),
        NSColor(calibratedRed: 0.35, green: 0.75, blue: 0.85, alpha: 0),
    ])!
    glow.draw(
        fromCenter: NSPoint(x: rect.midX, y: rect.midY), radius: 0,
        toCenter: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width * 0.55,
        options: []
    )

    // The carrier: a sine of a few cycles whose amplitude follows a slow envelope,
    // one swell across the tile. Both are sampled sparsely and joined with
    // Catmull-Rom curves, which stroke cleanly at every size.
    let width = rect.width * 0.68
    let amplitude = rect.height * 0.24
    let cycles = 3.0
    func curve(_ f: (CGFloat) -> CGFloat, samples: Int = 96) -> CGPath {
        let points = (0...samples).map { step -> CGPoint in
            let t = CGFloat(step) / CGFloat(samples)
            return CGPoint(x: rect.midX - width / 2 + t * width, y: rect.midY + f(t))
        }
        let path = CGMutablePath()
        path.move(to: points[0])
        for i in 0..<points.count - 1 {
            let p0 = points[max(i - 1, 0)], p1 = points[i]
            let p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        return path
    }
    let carrier = curve { t in amplitude * sin(t * .pi) * sin(t * cycles * 2 * .pi) }
    let envelope = CGMutablePath()
    envelope.addPath(curve { t in amplitude * sin(t * .pi) })
    envelope.addPath(curve { t in -amplitude * sin(t * .pi) })
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // Envelope first, faint, so the swell reads as a shape even where the carrier is thin.
    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.28).cgColor)
    context.setLineWidth(rect.width * 0.018)
    context.addPath(envelope)
    context.strokePath()

    // A dark stroke offset below the carrier lifts it off the glow.
    context.saveGState()
    context.translateBy(x: 0, y: -rect.width * 0.012)
    context.setStrokeColor(NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.2, alpha: 0.35).cgColor)
    context.setLineWidth(rect.width * 0.07)
    context.addPath(carrier)
    context.strokePath()
    context.restoreGState()

    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(rect.width * 0.06)
    context.addPath(carrier)
    context.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (points, scale) in sizes {
    let filename = "icon_\(points)x\(points)@\(scale)x.png"
    try render(pixels: points * scale).write(to: directory.appendingPathComponent(filename))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
}
try render(pixels: 1024, fullBleed: true).write(to: directory.appendingPathComponent("icon_1024.png"))
for idiom in ["ios", "watchos"] {
    images.append(["idiom": "universal", "platform": idiom, "size": "1024x1024", "filename": "icon_1024.png"])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: directory.appendingPathComponent("Contents.json"))
print("wrote \(sizes.count) icons to \(directory.path)")
