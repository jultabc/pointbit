// ⌘ ⌘ D: a box over one screen, first the size of the window under the pointer. Drag a corner or an edge to
// resize it, the grey triangle in its top-left corner (or inside it) to move it, outside it to draw a new one
// (AreaDrag); the pointer shows which (a hand inside, arrows on the edges).
// The outside is dimmed. Return or ⌘ ⌘ D starts recording it; Esc cancels.
// The picker's window takes the keys and the mouse only while it is open; it is gone before the recording starts.
import AppKit

@MainActor
final class AreaPicker {
    private var window: NSWindow?
    private var done: ((CGRect?) -> Void)?
    private var previous: NSRunningApplication?

    var isOpen: Bool { window != nil }

    /// Opens on `screen` with the box at `rect` (Cocoa global); `done` gets the chosen rect, or nil when cancelled.
    func open(on screen: NSScreen, rect: CGRect, done: @escaping (CGRect?) -> Void) {
        guard window == nil else { return }
        self.done = done
        previous = NSWorkspace.shared.frontmostApplication
        let w = KeyWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let local = rect.intersection(screen.frame).offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let v = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size), box: local)
        v.onEnd = { [weak self] r in self?.finish(r.map { Self.global($0, on: screen.frame) }) }
        w.contentView = v
        w.acceptsMouseMovedEvents = true
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(v)
    }

    /// ⌘ ⌘ D while open: start with the box as it is (the same way as Return, so the box is put back on the screen).
    func confirm() { (window?.contentView as? PickerView)?.confirm() }

    /// The view's box (its screen's points) as a Cocoa global rect.
    nonisolated static func global(_ local: CGRect, on screen: CGRect) -> CGRect {
        local.offsetBy(dx: screen.minX, dy: screen.minY)
    }

    func cancel() { finish(nil) }

    private func finish(_ rect: CGRect?) {
        guard let w = window else { return }
        w.close(); window = nil
        previous?.activate()   // give the keys back to the app being recorded
        let d = done; done = nil
        d?(rect)
    }

    private final class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private final class PickerView: NSView {
        private var box: CGRect   // as dragged, unrounded
        /// The box to record: on whole points, inside the screen.
        var chosen: CGRect { AreaDrag.whole(box, within: bounds) }
        var onEnd: (CGRect?) -> Void = { _ in }
        private var grip: AreaGrip?, last = CGPoint.zero
        private var anchor: CGPoint?   // a press outside the box: a new box from here
        private var fingers: AreaGrip?   // two fingers on the trackpad: what they grabbed where the pointer was
        private var pointer = CGPoint.zero   // where the pointer is during a two-finger drag (view points)
        private let shade = CAShapeLayer(), under = RecordingFrame.underline(), line = RecordingFrame.line()
        private let handle = CAShapeLayer()
        static let handleSide: CGFloat = 22   // the triangle in the box's top-left corner: drag it to move the box

        init(frame: NSRect, box: CGRect) {
            self.box = box
            super.init(frame: frame)
            wantsLayer = true
            shade.fillRule = .evenOdd
            shade.fillColor = RecordingFrame.shadeColor   // the outside dimmed, the box left clear
            handle.fillColor = NSColor.systemGray.withAlphaComponent(0.85).cgColor   // grey, calmer than red
            handle.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor; handle.lineWidth = 1
            [shade, under, line, handle].forEach { layer?.addSublayer($0) }
            // Nothing animates: the layers change only when the box does. (Running dashes were tried earlier; then still
            // dashes; now one solid line for every box.)
            redraw()
        }
        required init?(coder: NSCoder) { nil }

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // Cursor rects: AppKit keeps the pointer shape while it is over each part (mouseMoved alone loses it).
        override func resetCursorRects() {
            let r = AreaDrag.reach, b = box
            addCursorRect(bounds, cursor: .arrow)
            addCursorRect(b.insetBy(dx: r, dy: r), cursor: .openHand)
            addCursorRect(CGRect(x: b.minX - r, y: b.minY + r, width: 2 * r, height: b.height - 2 * r), cursor: .resizeLeftRight)
            addCursorRect(CGRect(x: b.maxX - r, y: b.minY + r, width: 2 * r, height: b.height - 2 * r), cursor: .resizeLeftRight)
            addCursorRect(CGRect(x: b.minX + r, y: b.minY - r, width: b.width - 2 * r, height: 2 * r), cursor: .resizeUpDown)
            addCursorRect(CGRect(x: b.minX + r, y: b.maxY - r, width: b.width - 2 * r, height: 2 * r), cursor: .resizeUpDown)
            for x in [b.minX, b.maxX] { for y in [b.minY, b.maxY] {
                addCursorRect(CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), cursor: .crosshair)
            } }
            addCursorRect(CGRect(x: b.minX, y: b.maxY - Self.handleSide, width: Self.handleSide, height: Self.handleSide), cursor: .openHand)
        }

        private func redraw() {
            window?.invalidateCursorRects(for: self)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            let p = CGMutablePath(); p.addRect(bounds); p.addRect(box)
            shade.frame = bounds; shade.path = p
            // The lines' layers cover the box and its line, not the whole screen (smaller backing; the CPU effect on
            // the 2017 MacBook Pro is still to be measured).
            let g = RecordingFrame.gap + RecordingFrame.width / 2, edge = RecordingFrame.gap + RecordingFrame.width + 1
            let around = box.insetBy(dx: -edge, dy: -edge)
            let path = CGPath(rect: box.insetBy(dx: -g, dy: -g).offsetBy(dx: -around.minX, dy: -around.minY), transform: nil)
            for l in [under, line] { l.frame = around; l.path = path }
            let t = CGMutablePath(), h = Self.handleSide
            t.move(to: CGPoint(x: box.minX, y: box.maxY)); t.addLine(to: CGPoint(x: box.minX + h, y: box.maxY))
            t.addLine(to: CGPoint(x: box.minX, y: box.maxY - h)); t.closeSubpath()
            handle.frame = bounds; handle.path = t
            CATransaction.commit()
        }

        override func mouseDown(with e: NSEvent) {
            last = convert(e.locationInWindow, from: nil)
            grip = grabbed(at: last)
            anchor = grip == nil ? last : nil
            if grip == .move { NSCursor.closedHand.set() }
        }
        override func mouseDragged(with e: NSEvent) {
            let p = convert(e.locationInWindow, from: nil)
            if let a = anchor {
                box = AreaDrag.span(from: a, to: p, within: bounds); redraw(); return
            }
            guard let grip else { return }
            box = AreaDrag.apply(grip, by: CGVector(dx: p.x - last.x, dy: p.y - last.y), to: box, within: bounds)
            last = p
            redraw()
        }
        /// The triangle moves the box even though it sits on the corner, where a press would resize.
        private func grabbed(at p: CGPoint) -> AreaGrip? {
            let onHandle = CGRect(x: box.minX, y: box.maxY - Self.handleSide, width: Self.handleSide, height: Self.handleSide).contains(p)
            return onHandle ? .move : AreaDrag.grip(at: p, in: box)
        }

        /// Two fingers on the trackpad work like a drag from where the pointer is (as the highlighter reads them).
        override func scrollWheel(with e: NSEvent) {
            guard let input = MarkerTap.reading(e).input(at: convert(e.locationInWindow, from: nil)) else { return }
            switch input {
            case .scrollBegan(let p): fingers = grabbed(at: p); pointer = p
            case .scrollBy(let dx, let dy):
                guard let g = fingers, dx != 0 || dy != 0 else { return }
                let old = box
                box = AreaDrag.apply(g, by: CGVector(dx: dx, dy: dy), to: box, within: bounds)
                redraw()
                // Fingers do not move the pointer: take it along with the part it holds, as a mouse drag would.
                let d = AreaDrag.moved(g, from: old, to: box)
                pointer = CGPoint(x: pointer.x + d.dx, y: pointer.y + d.dy)
                if let w = window, let top = NSScreen.screens.first?.frame.maxY {
                    CGWarpMouseCursorPosition(CGPoint(x: w.frame.minX + pointer.x, y: top - (w.frame.minY + pointer.y)))
                }
            case .scrollEnded: fingers = nil
            default: break
            }
        }

        override func mouseUp(with e: NSEvent) { grip = nil; anchor = nil; window?.invalidateCursorRects(for: self) }

        func confirm() { onEnd(chosen) }

        override func keyDown(with e: NSEvent) {
            switch e.keyCode {
            case 36, 76: confirm()       // Return, keypad Enter
            case 53: onEnd(nil)          // Esc
            default: super.keyDown(with: e)
            }
        }
    }
}
