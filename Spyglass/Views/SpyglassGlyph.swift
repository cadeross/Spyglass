import AppKit

/// The spyglass drawn by hand (SF Symbols has no telescope): a telescoping tube with rings, tilted up.
enum SpyglassGlyph {
    static func path(in rect: CGRect) -> NSBezierPath {
        let unit = min(rect.width, rect.height) / 18
        // Pieces along the tube, from the eyepiece out: (start, end, thickness).
        let segments: [(CGFloat, CGFloat, CGFloat)] = [
            (-8.6, -4.4, 2.4), (-5.0, 0.6, 3.2), (0.0, 8.0, 4.2), // eyepiece, draw tube, barrel
            (-5.3, -4.5, 3.6), (-0.3, 0.7, 4.6), (7.6, 8.6, 5.0), // rings at the joints and the lens
        ]
        let path = NSBezierPath()
        path.windingRule = .nonZero
        for (start, end, thickness) in segments {
            let segment = CGRect(x: start * unit, y: -thickness * unit / 2, width: (end - start) * unit, height: thickness * unit)
            path.append(NSBezierPath(roundedRect: segment, xRadius: 0.5 * unit, yRadius: 0.5 * unit))
        }
        var transform = AffineTransform(translationByX: rect.midX, byY: rect.midY)
        transform.rotate(byDegrees: 28)
        path.transform(using: transform)
        return path
    }

    /// The menu bar icon, as a template image so it follows the menu bar's light or dark look.
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setFill()
            path(in: rect).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Spyglass"
        return image
    }()

    /// A red recording dot for the menu bar; deliberately not a template, so it stays red.
    static let recordingDot: NSImage = {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }()
}
