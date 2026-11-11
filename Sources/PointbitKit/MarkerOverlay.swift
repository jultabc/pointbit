// Draws the highlighter strokes: one click-through, borderless window per screen, above other windows, so the
// strokes are in the recording (ScreenRecorder captures the whole display). Shown while recording only.
// Finished strokes get their layers once; while drawing, only the stroke in progress changes its path, and no
// Core Animation fades run (they made circles lag behind the fingers).
import AppKit

@MainActor
final class MarkerOverlay {
    private struct Screen { let window: NSWindow; let done: CALayer; let current: CAShapeLayer }
    private var screens: [Screen] = []
    private var drawn: [MarkerStroke] = []   // the finished strokes the `done` layers show

    /// One window per screen, empty.
    func show() {
        guard screens.isEmpty else { return }
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false   // `screens` owns it
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.setFrame(screen.frame, display: false)
            let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size)); v.wantsLayer = true
            let done = CALayer(); done.frame = v.bounds
            let current = Self.shape(frame: v.bounds)
            v.layer?.addSublayer(done); v.layer?.addSublayer(current)
            w.contentView = v
            w.orderFrontRegardless()
            screens.append(Screen(window: w, done: done, current: current))
        }
        drawn = []
    }

    func hide() {
        screens.forEach { $0.window.close() }
        screens = []; drawn = []
    }

    /// Shows the lines only inside `rect` (Cocoa global, the recorded rect of ⌘ ⌘ T / ⌘ ⌘ D); nil shows them everywhere.
    func clip(to rect: CGRect?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for s in screens {
            guard let layer = s.window.contentView?.layer else { continue }
            guard let rect else { layer.mask = nil; continue }
            let m = (layer.mask as? CAShapeLayer) ?? CAShapeLayer()
            m.frame = layer.bounds
            m.path = CGPath(rect: rect.offsetBy(dx: -s.window.frame.minX, dy: -s.window.frame.minY), transform: nil)
            layer.mask = m
        }
    }

    /// Draws `strokes` and the stroke in progress (`current`, in `color`).
    func draw(_ strokes: [MarkerStroke], current: [CGPoint], color: RGBA) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let rebuild = strokes != drawn
        for s in screens {
            let o = s.window.frame.origin
            if rebuild {
                s.done.sublayers = strokes.map { stroke in
                    let l = Self.shape(frame: s.done.bounds)
                    l.path = Self.path(stroke.points, origin: o); l.strokeColor = stroke.color.cg
                    return l
                }
            }
            s.current.path = current.isEmpty ? nil : Self.path(current, origin: o)
            s.current.strokeColor = color.cg
        }
        if rebuild { drawn = strokes }
    }

    private static func shape(frame: CGRect) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.frame = frame
        l.fillColor = nil
        l.lineWidth = MarkerStrokes.lineWidth
        l.lineCap = .round; l.lineJoin = .round
        return l
    }

    /// Global Cocoa points as a path in a window whose origin is `o`. A single point still shows as a round dot.
    private static func path(_ points: [CGPoint], origin o: CGPoint) -> CGPath {
        let pts = points.map { CGPoint(x: $0.x - o.x, y: $0.y - o.y) }
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for p in pts.count == 1 ? pts : Array(pts.dropFirst()) { path.addLine(to: p) }
        return path
    }
}
