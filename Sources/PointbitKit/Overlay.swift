// Draws one click mark in a click-through, borderless window at the cursor.
import AppKit

extension RGBA { var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) } }

final class ClickOverlay {
    private var live: [NSWindow] = []   // keep windows alive until they are closed

    /// A white flash over `frame` that fades out in 0.35 s; lighter over a whole screen.
    func flash(_ frame: NSRect) {
        let whole = NSScreen.screens.contains { $0.frame == frame }
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false; w.backgroundColor = NSColor(white: 1, alpha: whole ? 0.3 : 0.7); w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.orderFrontRegardless()
        live.append(w)
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.35; w.animator().alphaValue = 0 },
                                            completionHandler: { [weak self, weak w] in
            guard let w else { return }
            w.close(); self?.live.removeAll { $0 === w }
        })
    }

    func show(_ m: ClickMark, at p: NSPoint) {
        let side = m.diameter + 4
        let w = NSWindow(contentRect: NSRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false   // `live` owns the window
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let v = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side)); v.wantsLayer = true
        w.contentView = v

        // Round mark: radial gradient, inner color at the center to outer color at the edge.
        // Inner color up to 30% of the radius, outer color from 75%.
        let dot = CAGradientLayer()
        dot.type = .radial
        dot.colors = [m.inner.cg, m.inner.cg, m.outer.cg, m.outer.cg]
        dot.locations = [0, 0.3, 0.75, 1]
        dot.startPoint = CGPoint(x: 0.5, y: 0.5); dot.endPoint = CGPoint(x: 1, y: 1)
        let r = m.diameter / 2
        dot.frame = CGRect(x: side / 2 - r, y: side / 2 - r, width: r * 2, height: r * 2)
        dot.cornerRadius = r; dot.masksToBounds = true
        v.layer?.addSublayer(dot)
        w.orderFrontRegardless()
        live.append(w)
        // Shown for the duration, then removed at once (no fade).
        DispatchQueue.main.asyncAfter(deadline: .now() + m.seconds) { [weak self, weak w] in
            guard let w else { return }
            w.close(); self?.live.removeAll { $0 === w }
        }
    }
}
