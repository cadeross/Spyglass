import AppKit

// Renders the Spyglass app icon: a white spyglass over a sunset sea.
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: 100, dy: 100)
    let shape = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.40, alpha: 1),
        NSColor(srgbRed: 0.85, green: 0.36, blue: 0.48, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.22, blue: 0.55, alpha: 1),
    ])!.draw(in: shape, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // A soft highlight across the top, for the glassy look.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), .clear])!
        .draw(in: NSRect(x: inset.minX, y: inset.midY, width: inset.width, height: inset.height / 2), angle: -90)
    // The sea along the bottom.
    NSGradient(colors: [
        NSColor(srgbRed: 0.10, green: 0.45, blue: 0.70, alpha: 0.9),
        NSColor(srgbRed: 0.05, green: 0.20, blue: 0.45, alpha: 1),
    ])!.draw(in: NSRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height * 0.3), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // The spyglass: a telescoping tube with rings, tilted up toward the horizon (same shape as the menu bar icon).
    let unit = 40.0
    let segments: [(Double, Double, Double)] = [
        (-8.6, -4.4, 2.4), (-5.0, 0.6, 3.2), (0.0, 8.0, 4.2), // eyepiece, draw tube, barrel
        (-5.3, -4.5, 3.6), (-0.3, 0.7, 4.6), (7.6, 8.6, 5.0), // rings at the joints and the lens
    ]
    let path = NSBezierPath()
    for (start, end, thickness) in segments {
        let segment = CGRect(x: start * unit, y: -thickness * unit / 2, width: (end - start) * unit, height: thickness * unit)
        path.append(NSBezierPath(roundedRect: segment, xRadius: 0.5 * unit, yRadius: 0.5 * unit))
    }
    var transform = AffineTransform(translationByX: rect.midX, byY: rect.midY + 30)
    transform.rotate(byDegrees: 28)
    path.transform(using: transform)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
