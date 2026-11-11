// Event tap for the highlighter. It exists only while recording (RecordingController adds and removes it).
// It reads ⌥ (modifier changes) and passes it on unchanged. It holds back only an ⌥ + press with its drags and
// release, and scrolls while ⌥ is held alone (two fingers draw); every other event goes on unchanged. When macOS turns the tap
// off it is removed, not turned on again, so it can never keep holding the mouse.
import AppKit

@MainActor
final class MarkerTap {
    private var tap: CFMachPort?, source: CFRunLoopSource?
    private var gesture = MarkerGesture()
    private var rest: Timer?   // waitForFingers
    private var penTimer: Timer?   // follows the pointer while ⌥ is held (showPen)
    private var penOff = false     // the recording is stopping: no dot until the next start
    /// While ⌥ is held alone: where a line would start (the pointer, Cocoa global), about 30 times a second; nil
    /// when ⌥ is released. RecordingFrame shows a dot there, left out of the video.
    var onPen: (CGPoint?) -> Void = { _ in }
    private var optionAlone = false, straightHeld = false
    private(set) var marks = MarkerStrokes()
    let overlay = MarkerOverlay()
    /// Color of the next strokes (⌘ ⌘ 1 · 2 · 3 pick one of the three colors in Preferences).
    var color: RGBA {
        get { gesture.color }
        set { gesture.color = newValue }
    }

    /// ⌘ ⌘ L · O · B: free line, oval or box. Back to the pen when the recording stops.
    var tool: MarkerTool {
        get { gesture.tool }
        set { gesture.tool = newValue }
    }

    var isRunning: Bool { tap != nil }

    private static let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
        | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        | CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

    /// Adds the tap and shows the empty overlay. False when macOS refuses the tap (no Accessibility).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let me = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, info in
            MainActor.assumeIsolated { Unmanaged<MarkerTap>.fromOpaque(info!).takeUnretainedValue().handle(type, event) }
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: Self.mask, callback: callback, userInfo: me) else { return false }
        let s = CFMachPortCreateRunLoopSource(nil, t, 0)!
        CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t; source = s
        marks.clear(); gesture.cancel(); gesture.tool = .pen; optionAlone = false; straightHeld = false   // L · O · B count only while recording
        penOff = false
        overlay.show(); redraw()
        // ⌥ (or ⌥ + ⇧) already held when the recording starts: no modifier change comes, so the state is set here as a
        // change would set it.
        if Self.optionHeld() {
            optionAlone = true; showPen(true)
            if NSEvent.modifierFlags.contains(.shift) { straightHeld = true; _ = gesture.feed(.straight(true)) }
        }
        return true
    }

    /// Removes the tap and the strokes.
    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
        rest?.invalidate(); rest = nil
        gesture.cancel(); gesture.tool = .pen; optionAlone = false; straightHeld = false; marks.clear()
        showPen(false)
        overlay.hide()
    }

    /// The recording is stopping (the capture takes a moment to end): the dot goes now and stays off until the next
    /// start, also when ⌥ changes meanwhile.
    func stopPen() { penOff = true; showPen(false) }

    /// ⌘ ⌘ Z
    func undo() { if marks.undo() { redraw() } }
    /// ⌘ ⌘ X
    func clear() { marks.clear(); redraw() }
    /// Lines show only inside `rect` (the recorded rect); nil = everywhere (⌘ ⌘ A).
    func clip(to rect: CGRect?) { overlay.clip(to: rect) }
    /// The recorded window moved by `d`: its strokes go with it. A line being drawn stays where the pen is.
    func move(by d: CGVector) { guard !marks.strokes.isEmpty else { return }; marks.move(by: d); redraw() }

    private func redraw() { overlay.draw(marks.strokes, current: gesture.current, color: gesture.color) }

    /// Quartz global (y down, from the top of the main screen) to Cocoa global (y up).
    private static func cocoa(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - p.y)
    }

    /// The scroll fields the highlighter uses, read from AppKit (ScrollReading turns them into input).
    static func reading(_ e: NSEvent) -> ScrollReading {
        ScrollReading(momentum: !e.momentumPhase.isEmpty,
                      began: e.phase.contains(.began) || e.phase.contains(.mayBegin),
                      ended: e.phase.contains(.ended) || e.phase.contains(.cancelled),
                      changed: e.phase.contains(.changed),
                      natural: e.isDirectionInvertedFromDevice,
                      deltaX: e.scrollingDeltaX, deltaY: e.scrollingDeltaY)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let p = Self.cocoa(event.location)
        let input: MarkerInput
        switch type {
        case .flagsChanged:
            // ⌥ alone, or ⌥ + ⇧ (straight lines), counts as "⌥ held"; ⌘ or ⌃ with it does not.
            let mods = event.flags.intersection([.maskAlternate, .maskCommand, .maskControl])
            let alone = mods == .maskAlternate
            let shift = alone && event.flags.contains(.maskShift)
            if alone == optionAlone {
                if alone, penTimer == nil { showPen(true) }   // the dot went off on a missed release; ⌥ is back
                guard alone, shift != straightHeld else { return Unmanaged.passUnretained(event) }
                straightHeld = shift
                input = .straight(shift)
            } else {
                optionAlone = alone; straightHeld = shift
                showPen(alone)
                if alone {
                    guard shift else { return Unmanaged.passUnretained(event) }
                    input = .straight(true)
                } else { input = .optionUp }
            }
        case .scrollWheel:
            // Only while ⌥ is held alone (checked on this event too, in case a release was missed): two fingers
            // draw instead of scrolling.
            let option = optionAlone && event.flags.contains(.maskAlternate)
            guard option || gesture.isActive, let e = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
            guard let i = Self.reading(e).input(at: p) else { return Unmanaged.passUnretained(event) }
            if case .scrollBegan = i {
                gesture.penBounds = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }?.frame ?? .infinite
            }
            input = i
        case .leftMouseDown: input = .down(p, option: event.flags.contains(.maskAlternate))
        case .leftMouseDragged: input = .drag(p)
        case .leftMouseUp: input = .up(p)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:   // turned off by macOS: remove it, never turn it on again
            DispatchQueue.main.async { self.removeTapOnly() }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
        let wasActive = gesture.isActive
        let action = gesture.feed(input)
        switch action {
        case .drew(let s): marks.add(s)
        case .erase(let p): marks.erase(at: p)
        case .pass, .hold: break
        }
        if MarkerGesture.needsRedraw(wasActive: wasActive, isActive: gesture.isActive, action) { redraw() }
        waitForFingers()
        // Two-finger drawing: the pointer follows the pen, so the video shows where it is.
        if case .scrollWheel = type, let pen = gesture.pen, gesture.current.count > 1 {
            CGWarpMouseCursorPosition(CGPoint(x: pen.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - pen.y))
        }
        return MarkerGesture.letsThrough(input, action) ? Unmanaged.passUnretained(event) : nil
    }

    /// A resting oval or box is drawn after `MarkerGesture.restTime` unless the fingers come back first.
    private func waitForFingers() {
        rest?.invalidate(); rest = nil
        guard gesture.isResting else { return }
        let t = Timer(timeInterval: MarkerGesture.restTime, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if case .drew(let s) = self.gesture.feed(.restOver) { self.marks.add(s) }
                self.redraw()
            }
        }
        RunLoop.main.add(t, forMode: .common)   // also while a menu is open
        rest = t
    }

    /// macOS turned the tap off: remove it. A gesture in progress is dropped (its release goes to the app, which
    /// never got its press). Strokes already drawn stay on screen until the recording stops (stop()).
    private func removeTapOnly() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
        gesture.cancel(); optionAlone = false; straightHeld = false; redraw()
        showPen(false)
    }

    /// ⌥ alone (⇧ may be with it) is held now, as the keyboard says.
    private static func optionHeld() -> Bool {
        NSEvent.modifierFlags.intersection([.option, .command, .control]) == .option
    }

    /// The pen dot follows the pointer while ⌥ is held: a timer reads the pointer, so the tap need not take every
    /// mouse move (fewer events through it while recording). It also reads the keys, so a missed ⌥ release does
    /// not leave the dot on, and moves the dot only when the pointer moved.
    private func showPen(_ on: Bool) {
        penTimer?.invalidate(); penTimer = nil
        guard on, !penOff else { onPen(nil); return }
        var last = NSEvent.mouseLocation
        onPen(last)
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard Self.optionHeld() else { self.showPen(false); return }   // only the dot; the gesture keeps its own state
                let p = NSEvent.mouseLocation
                if p != last { last = p; self.onPen(p) }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        penTimer = t
    }
}
