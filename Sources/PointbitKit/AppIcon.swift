// App icon and menu bar icon, drawn in code: a center dot, one ring and two ripples.
import AppKit

public enum AppIcon {
    /// Menu bar: center dot, one ring, one fainter ripple. Template image (follows light/dark menu bar).
    static func menuBar() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 7, y: 7, width: 4, height: 4)).fill()
            NSColor.black.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 10, height: 10)); ring.lineWidth = 1.8; ring.stroke()
            NSColor.black.withAlphaComponent(0.45).setStroke()
            let ripple = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 16, height: 16)); ripple.lineWidth = 1.2; ripple.stroke()
            return true
        }
        img.isTemplate = true; img.accessibilityDescription = appName
        return img
    }


    /// App icon at `size` points.
    static func app(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY), u = size / 2 * 0.94
            let deep = rgb(0.78, 0.06, 0.09), orange = rgb(1.0, 0.50, 0.28), edge = rgb(0.55, 0.03, 0.08, 0.6)
            // Ripples: fraction of u, width as a fraction of u, opacity. At least one pixel wide, wider below 40 pt,
            // so they still show at 16 pt.
            let px = max(1, size / 512)
            for (f, w, a) in [(0.93, 0.055, 0.30), (0.76, 0.075, 0.60)] as [(CGFloat, CGFloat, CGFloat)] {
                let p = circle(c, u * f); p.lineWidth = max(u * w, 1.2 * px * (size < 40 ? 1.6 : 1))
                rgb(0.92, 0.20, 0.16, a).setStroke(); p.stroke()
            }
            NSColor(white: 0.99, alpha: 1).setFill(); circle(c, u * 0.58).fill()
            band(c, outer: u * 0.58, inner: u * 0.36, size: size, deep: deep, light: orange, edge: edge)
            band(c, outer: u * 0.20, inner: 0, size: size, deep: deep, light: orange, edge: edge)
            return true
        }
    }

    /// Writes the PNG sizes of an .iconset folder (16 to 512 pt, 1x and 2x). Used by MakeIcon.
    public static func writeIconset(to dir: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                app(size: CGFloat(px)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
            }
        }
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    private static func circle(_ c: NSPoint, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
    /// A red band between two radii: orange at the inner edge to deep red at the outer edge, thin dark outline.
    private static func band(_ c: NSPoint, outer r1: CGFloat, inner r2: CGFloat, size: CGFloat,
                             deep: NSColor, light: NSColor, edge: NSColor) {
        let p = circle(c, r1); if r2 > 0 { p.append(circle(c, r2).reversed) }
        NSGraphicsContext.saveGraphicsState(); p.addClip()
        let mid = rgb(0.93, 0.24, 0.16)
        NSGradient(colors: [light, light, mid, deep], atLocations: [0, r2 / r1, (r2 / r1 + 1) / 2, 1], colorSpace: .sRGB)!
            .draw(fromCenter: c, radius: 0, toCenter: c, radius: r1, options: [])   // explicit radius: draw(in:) spreads to the corner
        NSGraphicsContext.restoreGraphicsState()
        edge.setStroke(); p.lineWidth = max(1, size / 200); p.stroke()
    }
}
