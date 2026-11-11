// Highlighter strokes drawn while recording. Pure: no AppKit, no clock. Points are Cocoa global (y up).
// Drawing: on a trackpad, hold ⌥ and move two fingers (the pen starts at the pointer and the pointer follows it;
// lifting the fingers or releasing ⌥ ends the stroke); with a mouse, hold ⌥ and drag with the left button.
// One finger with ⌥ held does not draw. Adding ⇧ (⌥ + ⇧) draws a straight line from where the stroke started. ⌥ + click erases the stroke under the pointer, ⌘ ⌘ Z erases the last stroke,
// ⌘ ⌘ X erases all of them, ⌘ ⌘ 1 · 2 · 3 pick color 1 · 2 · 3 (set in Preferences). MarkerTap feeds the events,
// MarkerOverlay draws `strokes`.
import CoreGraphics

/// Default highlighter colors for ⌘ ⌘ 1 · 2 · 3 (each can be changed in Preferences): yellow, red, blue.
let markerDefaultColors = [RGBA(r: 1.0, g: 0.90, b: 0.0, a: 0.45),
                           RGBA(r: 1.0, g: 0.20, b: 0.20, a: 0.45),
                           RGBA(r: 0.15, g: 0.50, b: 1.0, a: 0.45)]

struct MarkerStroke: Equatable {
    var points: [CGPoint]
    var color = markerDefaultColors[0]
    var drawn: [CGPoint]? = nil   // the hand-drawn line when MarkerShape turned it into an ellipse
    var start: CGPoint { points[0] }
}

struct MarkerStrokes {
    static let lineWidth: CGFloat = 14
    private(set) var strokes: [MarkerStroke] = []

    mutating func add(_ s: MarkerStroke) { strokes.append(s) }
    /// Removes the last stroke drawn; when it was turned into an ellipse, brings back the hand-drawn line first.
    /// False when there is none.
    @discardableResult mutating func undo() -> Bool {
        guard let last = strokes.last else { return false }
        if let drawn = last.drawn { strokes[strokes.count - 1] = MarkerStroke(points: drawn, color: last.color) }
        else { strokes.removeLast() }
        return true
    }
    mutating func clear() { strokes = [] }
    /// Moves every stroke by `d` (the recorded window moved).
    mutating func move(by d: CGVector) {
        func shift(_ ps: [CGPoint]) -> [CGPoint] { ps.map { CGPoint(x: $0.x + d.dx, y: $0.y + d.dy) } }
        strokes = strokes.map { MarkerStroke(points: shift($0.points), color: $0.color, drawn: $0.drawn.map(shift)) }
    }
    /// Removes the stroke `hit(at:)` picks. False when the click is on no stroke.
    @discardableResult mutating func erase(at p: CGPoint) -> Bool {
        guard let i = hit(at: p) else { return false }
        strokes.remove(at: i); return true
    }

    /// The stroke under `p`: within half the line width plus `slack` of its line. On a place where strokes cross,
    /// the one whose start point is nearest to `p`; on a tie, the later one (drawn on top).
    func hit(at p: CGPoint, slack: CGFloat = 4) -> Int? {
        let reach = Self.lineWidth / 2 + slack
        let under = strokes.indices.filter { Self.distance(p, to: strokes[$0].points) <= reach }
        return under.min { a, b in
            let da = Self.length(p, strokes[a].start), db = Self.length(p, strokes[b].start)
            return da == db ? a > b : da < db
        }
    }

    static func length(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// Shortest distance from `p` to the line through `points` (one point: to that point).
    static func distance(_ p: CGPoint, to points: [CGPoint]) -> CGFloat {
        guard var best = points.first.map({ length(p, $0) }) else { return .infinity }
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            best = min(best, length(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy)))
        }
        return best
    }
}

/// Input to the highlighter, as the event tap sees it. Scroll inputs are fed only while ⌥ is held alone.
enum MarkerInput: Equatable {
    case optionUp                      // ⌥ released, or ⌘ or ⌃ joined it
    case straight(Bool)                // ⇧ pressed (true) or released (false) while ⌥ is held
    case down(CGPoint, option: Bool)   // left button press; option = ⌥ held
    case drag(CGPoint)                 // pointer moved with the left button down
    case up(CGPoint)
    case scrollBegan(CGPoint)          // two fingers touched the trackpad; the pointer's position
    case scrollBy(dx: CGFloat, dy: CGFloat)   // finger movement in screen points (Cocoa: y up)
    case scrollEnded                   // the fingers lifted
    case restOver                      // an oval or a box waited `restTime` after the fingers lifted (MarkerTap's timer)
}

/// One trackpad scroll event as the device reports it, without AppKit (MarkerTap reads it from NSEvent).
/// Input devices meet the highlighter here: the trackpad through this, the mouse through down · drag · up.
/// A pen (Sidecar, a drawing tablet) would be one more reading turned into the same MarkerInput.
struct ScrollReading: Equatable {
    var momentum = false               // movement after the fingers lifted
    var began = false                  // fingers touched (began or may begin)
    var ended = false                  // fingers lifted (ended or cancelled)
    var changed = false                // fingers moved
    var natural = true                 // natural scrolling: content follows the fingers
    var deltaX: CGFloat = 0            // content movement (scrollingDeltaX)
    var deltaY: CGFloat = 0

    /// As highlighter input. Finger movement in Cocoa screen points, with or without natural scrolling.
    /// A scroll with no phase (a mouse wheel) gives nil: it goes on to the app. Momentum gives a zero move (held).
    func input(at p: CGPoint) -> MarkerInput? {
        if momentum { return .scrollBy(dx: 0, dy: 0) }
        if began { return .scrollBegan(p) }
        if ended { return .scrollEnded }
        guard changed else { return nil }
        return .scrollBy(dx: natural ? deltaX : -deltaX, dy: natural ? -deltaY : deltaY)
    }
}

/// What to do with one event.
enum MarkerAction: Equatable {
    case pass                  // goes on to the app under the pointer
    case hold                  // part of a highlighter gesture: the app does not get it
    case drew(MarkerStroke)    // a stroke ended
    case erase(CGPoint)        // ⌥ + click without moving: erase there (the click is held)
}

/// What a stroke draws: the line as drawn (pen), or an oval or a box from the press point (one corner) to the pen
/// (the opposite corner), redrawn as the pen moves. ⌘ ⌘ L · O · B.
enum MarkerTool: Equatable { case pen, oval, box }

/// One gesture at a time: an ⌥ + press (mouse) or an ⌥ + two-finger scroll (trackpad). A press and release in
/// place is a click: it erases there. A stroke that moved no more than `clickMax` points is dropped.
struct MarkerGesture {
    var clickMax: CGFloat = 4
    var color = markerDefaultColors[0]
    var tool = MarkerTool.pen
    /// The screen a two-finger stroke started on; the pen stays inside it (set by MarkerTap at scrollBegan).
    var penBounds = CGRect.infinite
    private enum Source { case press, scroll }
    private var points: [CGPoint]? = nil
    private var source = Source.press
    private var moved = false
    private var ignoredPress = false   // an ⌥ + press during a two-finger stroke: held up to its release
    private var straight = false       // ⇧ held with ⌥: straight lines; with an oval or a box, a circle or a square
    private var anchor: CGPoint? = nil // an oval's or a box's corner where the stroke started
    /// An oval or a box whose fingers lifted: it waits `restTime` for them to touch again and go on (a trackpad is
    /// small; a shape is often drawn in two pushes), then it is drawn. Releasing ⌥ draws it at once.
    private(set) var isResting = false
    static let restTime = 0.6   // seconds
    /// Where the pen is: the fingers' position (two-finger strokes) or the mouse's, before a straight line is
    /// levelled. A trackpad pointer follows it, and the next movement starts from it, so levelling never holds the
    /// pen on a line; a shape is redrawn to it (a box's last point is its start corner, not the pen).
    private(set) var pen: CGPoint? = nil

    var isActive: Bool { points != nil }
    /// The stroke being drawn, for live drawing; its last point is the pen (the pointer follows it on a trackpad).
    var current: [CGPoint] { points ?? [] }

    mutating func feed(_ e: MarkerInput) -> MarkerAction {
        switch e {
        case .down(let p, let option):
            guard option else { return .pass }
            if isResting { ignoredPress = true; return end() }   // a press ends a resting shape; the press itself is held
            guard points == nil else { ignoredPress = true; return .hold }   // during a two-finger stroke: held, ignored
            points = [p]; source = .press; moved = false; anchor = p; pen = p
            return .hold
        case .drag(let p):
            if ignoredPress { return .hold }
            guard points != nil, source == .press else { return .pass }
            pen = p
            add(p)
            return .hold
        case .up(let p):
            if ignoredPress { ignoredPress = false; return .hold }
            guard let pts = points, source == .press else { return .pass }
            let start = anchor ?? pts[0]
            if !moved && MarkerStrokes.length(p, start) <= clickMax { points = nil; anchor = nil; return .erase(start) }
            pen = p
            add(p)
            return end()
        case .scrollBegan(let p):
            if isResting { isResting = false; return .hold }   // the fingers are back: the shape goes on from the pen
            // Another begin without an end (a trackpad can send may-begin and began): the stroke goes on; it was
            // ended and dropped here before, so a shape or a line vanished.
            guard points == nil else { return .hold }
            points = [p]; source = .scroll; moved = false; pen = p; anchor = p
            return .hold
        case .scrollBy(let dx, let dy):
            guard points != nil, source == .scroll, let last = pen else { return .hold }   // momentum after a stroke: held, ignored
            let b = penBounds
            let next = CGPoint(x: min(max(last.x + dx, b.minX), b.maxX), y: min(max(last.y + dy, b.minY), b.maxY))
            pen = next
            add(next)
            return .hold
        case .scrollEnded:
            guard points != nil, source == .scroll else { return .hold }
            if tool != .pen, moved { isResting = true; return .hold }
            let a = end(); return a == .pass ? .hold : a
        case .restOver:
            guard isResting else { return .pass }
            return end()
        case .optionUp:
            straight = false
            guard points != nil, source == .scroll else { return .pass }   // a press ends at its release
            return end()
        case .straight(let on):
            straight = on
            // An oval or a box: ⇧ makes it a circle or a square (and back) where the pen is.
            if tool != .pen, let a = anchor, let at = pen, points != nil {
                points = Self.outline(tool, from: a, to: at, even: on)
                return .pass
            }
            // ⇧ pressed mid-stroke: the line so far becomes a straight line from its start to where the pen is.
            if on, let pts = points, pts.count >= 2 {
                let at = pen ?? pts[pts.count - 1]
                points = [pts[0], Self.level(from: pts[0], to: at)]
            }
            return .pass
        }
    }

    private mutating func add(_ p: CGPoint) {
        guard var pts = points else { return }
        if MarkerStrokes.length(p, anchor ?? pts[0]) > clickMax { moved = true }
        if tool != .pen, let a = anchor { points = Self.outline(tool, from: a, to: p, even: straight); return }
        // ⌥ + ⇧: a straight line from the stroke's start to the pen (the newest point replaces the line's end).
        if straight {
            let end = Self.level(from: pts[0], to: p)
            if pts.count >= 2 { pts[pts.count - 1] = end } else { pts.append(end) }   // the first move is levelled too
        } else { pts.append(p) }
        points = pts
    }

    /// Ends the stroke: .drew when it moved, else .pass (nothing drawn).
    private mutating func end() -> MarkerAction {
        guard let pts = points else { return .pass }
        points = nil; pen = nil; anchor = nil; isResting = false
        guard moved else { return .pass }
        if tool != .pen { return .drew(MarkerStroke(points: pts, color: color)) }   // already its shape
        // A closed loop becomes a clean ellipse; the hand-drawn line is kept for ⌘ ⌘ Z.
        if let e = MarkerShape.ellipse(for: pts) { return .drew(MarkerStroke(points: e, color: color, drawn: pts)) }
        return .drew(MarkerStroke(points: pts, color: color))
    }

    /// The outline of an oval or a box with corners `a` and `b`; `even` makes it a circle or a square (the longer
    /// side, toward `b`). A box is its four corners and back to the first; an oval, `ovalPoints` points around.
    static let ovalPoints = 72
    static func outline(_ tool: MarkerTool, from a: CGPoint, to b: CGPoint, even: Bool) -> [CGPoint] {
        var dx = b.x - a.x, dy = b.y - a.y
        if even { let side = max(abs(dx), abs(dy)); dx = dx < 0 ? -side : side; dy = dy < 0 ? -side : side }
        let c = CGPoint(x: a.x + dx, y: a.y + dy)
        switch tool {
        case .pen: return [a, c]
        case .box: return [a, CGPoint(x: c.x, y: a.y), c, CGPoint(x: a.x, y: c.y), a]
        case .oval:
            let mid = CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2), rx = abs(dx) / 2, ry = abs(dy) / 2
            return (0...ovalPoints).map { i in
                let t = CGFloat(i) / CGFloat(ovalPoints) * 2 * .pi
                return CGPoint(x: mid.x + rx * cos(t), y: mid.y + ry * sin(t))
            }
        }
    }

    /// A straight line's end: within `snapDegrees` of horizontal it keeps the start's y, within it of vertical the
    /// start's x; other angles stay as drawn.
    static let snapDegrees: CGFloat = 20
    static func level(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
        guard dx > 0 || dy > 0 else { return b }
        let angle = atan2(dy, dx) * 180 / .pi   // 0 = horizontal, 90 = vertical
        if angle <= snapDegrees { return CGPoint(x: b.x, y: a.y) }
        if angle >= 90 - snapDegrees { return CGPoint(x: a.x, y: b.y) }
        return b
    }

    /// Drops a stroke in progress (the tap was removed, or recording stopped).
    mutating func cancel() { points = nil; ignoredPress = false; straight = false; pen = nil; anchor = nil; isResting = false }

    /// Whether the overlay must be drawn again after an event: while a stroke is in progress, when one just
    /// ended or was dropped (its last points must go away), and after any held or erasing event.
    static func needsRedraw(wasActive: Bool, isActive: Bool, _ action: MarkerAction) -> Bool {
        wasActive || isActive || action != .pass
    }

    /// Whether the event goes on to the app. ⌥ itself always does (only its release can end a stroke).
    /// Everything else goes on only when the gesture passed it: a stroke's last event (mouse release, fingers
    /// lifted) is held like the rest of it, so the app never gets half of a press or a scroll.
    static func letsThrough(_ input: MarkerInput, _ action: MarkerAction) -> Bool {
        if case .optionUp = input { return true }
        return action == .pass
    }
}
