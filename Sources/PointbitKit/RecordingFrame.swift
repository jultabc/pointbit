// The line around what ⌘ ⌘ T and ⌘ ⌘ D record, with the rest of the screen dimmed. The line is drawn just outside
// the recorded rect and the window is left out of the capture, so neither is in the video (also not while the rect
// catches up with a moved window). It lets clicks through. ⌘ ⌘ D's AreaPicker, ⌘ ⌘ R's picker and the ⌘ ⌘ M box
// draw the same line (`line()`).
import AppKit

@MainActor
final class RecordingFrame {
    static let gap: CGFloat = 3         // points between the recorded rect and the line
    static let width: CGFloat = 2
    /// The outside of the recorded rect, also in ⌘ ⌘ D's picker: codegg's dark grey (#333333), lighter than black.
    static let shadeColor = NSColor(srgbRed: 0x33 / 255.0, green: 0x33 / 255.0, blue: 0x33 / 255.0, alpha: 0.3).cgColor
    private var window: NSWindow?
    private var line: CAShapeLayer?, under: CAShapeLayer?, shade: CAShapeLayer?
    private var zoomLine: CAShapeLayer?, zoomUnder: CAShapeLayer?   // ⌘ ⌘ M: the line around what the video shows
    private var pen: CAShapeLayer?   // ⌥ held: where a highlighter line would start
    private var area: CGRect?   // the recorded rect (Cocoa global) last shown
    private var aside = StepAside()   // pictures being taken: the box is off the screen until the last ends

    /// Shows the box around `rect` (Cocoa global), or moves it there: the line, and the rest of its screen dimmed.
    /// The window covers that screen; it is left out of the capture, so neither is in the video.
    func show(around rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let screen = (NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main)?.frame else { return }
        if window == nil {
            let w = NSWindow(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false   // `window` owns it
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let v = NSView(frame: NSRect(origin: .zero, size: screen.size)); v.wantsLayer = true
            let d = CAShapeLayer(); d.fillRule = .evenOdd; d.fillColor = Self.shadeColor
            let u = Self.underline(), l = Self.line(), zu = Self.underline(), zl = Self.line(), dot = Self.penDot()
            [d, u, l, zu, zl, dot].forEach { v.layer?.addSublayer($0) }
            w.contentView = v
            window = w; line = l; under = u; shade = d; zoomLine = zl; zoomUnder = zu; pen = dot
        }
        if window?.frame != screen { window?.setFrame(screen, display: false) }
        area = rect
        let local = rect.offsetBy(dx: -screen.minX, dy: -screen.minY)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        dim(outside: local)
        // The lines' layers cover only the rect and its line.
        let edge = Self.gap + Self.width, around = local.insetBy(dx: -edge, dy: -edge)
        let path = CGPath(rect: CGRect(origin: .zero, size: around.size).insetBy(dx: Self.width / 2, dy: Self.width / 2), transform: nil)
        for l in [under, line] { l?.frame = around; l?.path = path }
        CATransaction.commit()
        if !aside.isAside { window?.orderFrontRegardless() }   // a move during a picture waits for it to end
    }

    /// ⌘ ⌘ M: the screen outside the part the video shows now (Cocoa global) is dimmed instead, with the line
    /// around that part; nil dims the outside of the recorded rect again. The screen itself does not zoom, only the video.
    func showZoom(_ rect: CGRect?) {
        guard let w = window, let area else { return }
        let local = (rect ?? area).offsetBy(dx: -w.frame.minX, dy: -w.frame.minY)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        dim(outside: local)
        let edge = Self.gap + Self.width, around = local.insetBy(dx: -edge, dy: -edge)
        let path = rect == nil ? nil : CGPath(rect: CGRect(origin: .zero, size: around.size).insetBy(dx: Self.width / 2, dy: Self.width / 2), transform: nil)
        for l in [zoomUnder, zoomLine] { l?.frame = around; l?.path = path }
        CATransaction.commit()
    }

    /// While ⌥ is held: a small lavender dot at `p` (Cocoa global), where a highlighter line would start; nil takes
    /// it away. In this window, so it is not in the video.
    func showPen(_ p: CGPoint?) {
        guard let w = window, let pen else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let p, w.frame.contains(p) {
            pen.position = CGPoint(x: p.x - w.frame.minX, y: p.y - w.frame.minY)
            pen.isHidden = false
        } else { pen.isHidden = true }
        CATransaction.commit()
    }

    /// Dims the window but `local` (window points).
    private func dim(outside local: CGRect) {
        guard let w = window else { return }
        let hole = CGMutablePath(); hole.addRect(CGRect(origin: .zero, size: w.frame.size)); hole.addRect(local)
        shade?.frame = CGRect(origin: .zero, size: w.frame.size); shade?.path = hole
    }

    /// The box's window, so the recording can leave it out; nil when hidden.
    var windowID: CGWindowID? { window.map { CGWindowID($0.windowNumber) } }

    /// A ⌘ ⌘ S picture starts (screencapture has no list of windows to leave out): the box goes off the screen.
    /// False when no box is shown. Each true needs one stepBack.
    func stepAside() -> Bool {
        guard let w = window else { return false }
        if aside.take() { w.orderOut(nil) }
        return true
    }

    /// A picture ended: after the last one, the box comes back.
    func stepBack() {
        if aside.give(), let w = window { w.orderFrontRegardless() }
    }

    func hide() {
        window?.close(); window = nil; line = nil; under = nil; shade = nil; aside = StepAside()
        zoomLine = nil; zoomUnder = nil; pen = nil; area = nil
    }

    /// A soft lavender (#B8B5FF): red read as a warning on the screen.
    static let lineColor = NSColor(srgbRed: 0xB8 / 255.0, green: 0xB5 / 255.0, blue: 0xFF / 255.0, alpha: 1).cgColor

    /// The line every box uses: solid lavender over `underline`, seen on light and dark screens. Solid, not dashed:
    /// one line for all boxes.
    static func line() -> CAShapeLayer {
        let l = CAShapeLayer()
        l.fillColor = nil
        l.strokeColor = lineColor
        l.lineWidth = width
        return l
    }

    static let penSize: CGFloat = 10

    /// The pen dot: lavender with a white ring, centred on its position.
    static func penDot() -> CAShapeLayer {
        let l = CAShapeLayer()
        l.bounds = CGRect(x: 0, y: 0, width: penSize, height: penSize)
        l.path = CGPath(ellipseIn: l.bounds.insetBy(dx: 1, dy: 1), transform: nil)
        l.fillColor = lineColor
        l.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        l.lineWidth = 1.5
        l.isHidden = true
        return l
    }

    /// A thin solid white line under the line. Not a layer shadow: a shadow is drawn again on every change, and
    /// with running dashes that kept a 2017 MacBook Pro's CPU busy.
    static func underline() -> CAShapeLayer {
        let l = CAShapeLayer()
        l.fillColor = nil
        l.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        l.lineWidth = width + 1
        return l
    }
}

/// How many pictures have the box off the screen. The first takes it off, the last brings it back. Pure.
struct StepAside {
    private(set) var count = 0
    var isAside: Bool { count > 0 }

    /// True when this one takes it off (none before).
    mutating func take() -> Bool { count += 1; return count == 1 }

    /// True when this was the last one; an extra call does nothing.
    mutating func give() -> Bool {
        guard count > 0 else { return false }
        count -= 1
        return count == 0
    }
}
