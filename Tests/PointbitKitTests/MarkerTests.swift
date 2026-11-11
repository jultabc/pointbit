// Highlighter: which stroke a click picks, undo and clear, and how ⌥ + mouse events become strokes or erases.
import CoreGraphics
import Testing
@testable import PointbitKit

struct MarkerTests {
    private func line(_ a: CGPoint, _ b: CGPoint) -> MarkerStroke { MarkerStroke(points: [a, b]) }

    @Test func clickPicksTheStrokeUnderIt() {
        var m = MarkerStrokes()
        m.add(line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)))
        m.add(line(CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)))
        #expect(m.hit(at: CGPoint(x: 50, y: 3)) == 0, "on the first line (within half the width)")
        #expect(m.hit(at: CGPoint(x: 50, y: 48)) == 1, "on the second line")
        #expect(m.hit(at: CGPoint(x: 50, y: 25)) == nil, "between the lines: no stroke")
        #expect(m.erase(at: CGPoint(x: 50, y: 25)) == false && m.strokes.count == 2, "a click on nothing erases nothing")
        #expect(m.erase(at: CGPoint(x: 50, y: 0)) && m.strokes.count == 1 && m.strokes[0].start.y == 50, "erases only that stroke")
    }

    @Test func crossingStrokesPickTheNearestStart() {
        var m = MarkerStrokes()
        m.add(line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)))     // starts bottom left
        m.add(line(CGPoint(x: 100, y: 0), CGPoint(x: 0, y: 100)))     // starts bottom right, crosses at 50,50
        #expect(m.hit(at: CGPoint(x: 48, y: 50)) == 0, "crossing point, nearer the first stroke's start")
        #expect(m.hit(at: CGPoint(x: 52, y: 50)) == 1, "crossing point, nearer the second stroke's start")
        #expect(m.hit(at: CGPoint(x: 50, y: 50)) == 1, "same distance: the later stroke (drawn on top)")
    }

    @Test func undoGoesBackInOrderAndClearRemovesAll() {
        var m = MarkerStrokes()
        for i in 0..<3 { m.add(MarkerStroke(points: [CGPoint(x: i, y: 0)])) }
        #expect(m.undo() && m.strokes.map(\.start.x) == [0, 1], "the third goes first")
        #expect(m.undo() && m.strokes.map(\.start.x) == [0], "then the second")
        #expect(m.undo() && m.strokes.isEmpty, "then the first")
        #expect(m.undo() == false, "nothing left")
        for i in 0..<3 { m.add(MarkerStroke(points: [CGPoint(x: i, y: 0)])) }
        m.clear()
        #expect(m.strokes.isEmpty)
    }

    @Test func movingTakesEveryStrokeAndItsHandDrawnLine() {
        var m = MarkerStrokes()
        m.add(MarkerStroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]))
        m.add(MarkerStroke(points: [CGPoint(x: 5, y: 5)], drawn: [CGPoint(x: 1, y: 1)]))
        m.move(by: CGVector(dx: 30, dy: -20))
        #expect(m.strokes[0].points == [CGPoint(x: 30, y: -20), CGPoint(x: 40, y: -20)])
        #expect(m.strokes[1].points == [CGPoint(x: 35, y: -15)] && m.strokes[1].drawn == [CGPoint(x: 31, y: -19)])
        #expect(m.undo() && m.strokes[1].points == [CGPoint(x: 31, y: -19)], "undo brings back the moved hand-drawn line")
    }
    @Test func distanceToALine() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]
        #expect(MarkerStrokes.distance(CGPoint(x: 5, y: 3), to: pts) == 3, "above the middle")
        #expect(MarkerStrokes.distance(CGPoint(x: 13, y: 4), to: pts) == 5, "past the end: to the end point")
        #expect(MarkerStrokes.distance(CGPoint(x: 3, y: 4), to: [CGPoint.zero]) == 5, "one point")
        #expect(MarkerStrokes.distance(.zero, to: []) == .infinity)
    }

    @Test func aBoxGoesFromThePressToThePen() {
        var g = MarkerGesture(); g.tool = .box
        _ = g.feed(.down(CGPoint(x: 10, y: 10), option: true))
        _ = g.feed(.drag(CGPoint(x: 50, y: 30)))
        _ = g.feed(.drag(CGPoint(x: 80, y: 40)))   // redrawn from the press, not added to
        #expect(g.current == [CGPoint(x: 10, y: 10), CGPoint(x: 80, y: 10), CGPoint(x: 80, y: 40), CGPoint(x: 10, y: 40), CGPoint(x: 10, y: 10)])
        let a = g.feed(.up(CGPoint(x: 80, y: 40)))
        #expect(a == .drew(MarkerStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 80, y: 10), CGPoint(x: 80, y: 40), CGPoint(x: 10, y: 40), CGPoint(x: 10, y: 10)])),
                "kept as a box, not turned into an ellipse")
    }

    @Test func shiftMakesASquareOrACircle() {
        var g = MarkerGesture(); g.tool = .box
        _ = g.feed(.scrollBegan(.zero)); _ = g.feed(.scrollBy(dx: 40, dy: -10))
        _ = g.feed(.straight(true))
        #expect(g.current[2] == CGPoint(x: 40, y: -40), "the longer side, toward the pen")
        let circle = MarkerGesture.outline(.oval, from: .zero, to: CGPoint(x: 20, y: 60), even: true)
        let xs = circle.map(\.x), ys = circle.map(\.y)
        #expect(abs((xs.max()! - xs.min()!) - 60) < 0.01 && abs((ys.max()! - ys.min()!) - 60) < 0.01)
    }

    @Test func aShapeWaitsForTheFingersToComeBack() {
        // 2017 test: on a trackpad a shape is often pushed twice; lifting the fingers ended it at the first push.
        var g = MarkerGesture(); g.tool = .box
        _ = g.feed(.scrollBegan(.zero)); _ = g.feed(.scrollBy(dx: 30, dy: 20))
        #expect(g.feed(.scrollEnded) == .hold && g.isResting && g.isActive, "lifted: it waits")
        #expect(g.feed(.scrollBegan(CGPoint(x: 30, y: 20))) == .hold && !g.isResting, "back: it goes on")
        _ = g.feed(.scrollBy(dx: 30, dy: 20))
        #expect(g.current[2] == CGPoint(x: 60, y: 40), "from the same corner, bigger")
        _ = g.feed(.scrollEnded)
        #expect(g.feed(.restOver) == .drew(MarkerStroke(points: MarkerGesture.outline(.box, from: .zero, to: CGPoint(x: 60, y: 40), even: false))))
        #expect(!g.isActive)
    }

    @Test func aSecondBeginKeepsTheShape() {
        // May-begin then began (both read as began) dropped the shape being drawn.
        var g = MarkerGesture(); g.tool = .oval
        _ = g.feed(.scrollBegan(CGPoint(x: 100, y: 100))); _ = g.feed(.scrollBy(dx: 50, dy: 30)); _ = g.feed(.scrollEnded)
        _ = g.feed(.scrollBegan(CGPoint(x: 150, y: 130))); _ = g.feed(.scrollBegan(CGPoint(x: 150, y: 130)))
        _ = g.feed(.scrollBy(dx: 10, dy: 10)); _ = g.feed(.scrollEnded)
        guard case .drew(let s) = g.feed(.restOver) else { Issue.record("drawn"); return }
        let xs = s.points.map(\.x)
        #expect(abs(xs.min()! - 100) < 0.01 && abs(xs.max()! - 160) < 0.01, "one oval from 100 to 160")
        var line = MarkerGesture()
        _ = line.feed(.scrollBegan(.zero)); _ = line.feed(.scrollBy(dx: 30, dy: 0)); _ = line.feed(.scrollBegan(CGPoint(x: 30, y: 0)))
        _ = line.feed(.scrollBy(dx: 10, dy: 0))
        #expect(line.current.last == CGPoint(x: 40, y: 0), "a free line goes on too")
    }

    @Test func shiftOnAMouseBoxSquaresItAtThePen() {
        // A box's last point is its start corner; the mouse box shrank to a dot.
        var g = MarkerGesture(); g.tool = .box
        _ = g.feed(.down(.zero, option: true)); _ = g.feed(.drag(CGPoint(x: 100, y: 40)))
        _ = g.feed(.straight(true))
        #expect(g.current[2] == CGPoint(x: 100, y: 100))
        _ = g.feed(.straight(false))
        #expect(g.current[2] == CGPoint(x: 100, y: 40), "back to the pen when ⇧ is released")
    }

    @Test func releasingOptionDrawsARestingShapeAtOnce() {
        var g = MarkerGesture(); g.tool = .oval
        _ = g.feed(.scrollBegan(.zero)); _ = g.feed(.scrollBy(dx: 30, dy: 20)); _ = g.feed(.scrollEnded)
        if case .drew = g.feed(.optionUp) {} else { Issue.record("⌥ released: drawn") }
        #expect(g.feed(.restOver) == .pass, "the timer after that does nothing")
    }

    @Test func aFreeLineStillEndsWhenTheFingersLift() {
        var g = MarkerGesture()
        _ = g.feed(.scrollBegan(.zero)); _ = g.feed(.scrollBy(dx: 30, dy: 0))
        if case .drew = g.feed(.scrollEnded) {} else { Issue.record("a free line ends at once") }
        #expect(!g.isResting)
    }

    @Test func anOvalFitsTheBox() {
        let o = MarkerGesture.outline(.oval, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 60), even: false)
        let xs = o.map(\.x), ys = o.map(\.y)
        #expect(o.count == MarkerGesture.ovalPoints + 1 && abs(xs.min()! - 10) < 0.01 && abs(xs.max()! - 110) < 0.01)
        #expect(abs(ys.min()! - 10) < 0.01 && abs(ys.max()! - 60) < 0.01)
    }

    @Test func aClickWithAShapeToolStillErases() {
        var g = MarkerGesture(); g.tool = .oval
        _ = g.feed(.down(CGPoint(x: 10, y: 10), option: true))
        #expect(g.feed(.up(CGPoint(x: 11, y: 10))) == .erase(CGPoint(x: 10, y: 10)))
    }

    @Test func twoFingersWithOptionDraw() {
        var g = MarkerGesture()
        #expect(g.feed(.scrollBegan(CGPoint(x: 10, y: 10))) == .hold, "the pen starts at the pointer")
        #expect(g.feed(.scrollBy(dx: 10, dy: 0)) == .hold, "the page does not scroll")
        #expect(g.feed(.scrollBy(dx: 10, dy: -5)) == .hold)
        #expect(g.current.last == CGPoint(x: 30, y: 5), "the pen moves by the finger movement")
        #expect(g.feed(.scrollEnded) == .drew(MarkerStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 10), CGPoint(x: 30, y: 5)])),
                "lifting the fingers ends the stroke")
        #expect(g.feed(.scrollBy(dx: 30, dy: 0)) == .hold, "momentum after the lift: held, draws nothing")
        #expect(!g.isActive)

        _ = g.feed(.scrollBegan(.zero)); _ = g.feed(.scrollBy(dx: 40, dy: 0))
        #expect(g.feed(.optionUp) == .drew(MarkerStroke(points: [.zero, CGPoint(x: 40, y: 0)])), "releasing ⌥ also ends it")

        _ = g.feed(.scrollBegan(.zero))
        #expect(g.feed(.scrollEnded) == .hold, "fingers rested without moving: nothing drawn")
        #expect(g.feed(.optionUp) == .pass)
    }

    @Test func mouseOptionPressAndDragDraws() {
        var g = MarkerGesture()
        #expect(g.feed(.down(.zero, option: true)) == .hold)
        #expect(g.feed(.drag(CGPoint(x: 50, y: 0))) == .hold)
        #expect(g.feed(.up(CGPoint(x: 50, y: 20))) == .drew(MarkerStroke(points: [.zero, CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 20)])))
        #expect(g.feed(.optionUp) == .pass, "a press stroke ends at its release, not at ⌥")
    }

    @Test func optionClickErases() {
        var g = MarkerGesture()
        #expect(g.feed(.down(CGPoint(x: 80, y: 0), option: true)) == .hold)
        #expect(g.feed(.drag(CGPoint(x: 82, y: 0))) == .hold, "a small move is still a click")
        #expect(g.feed(.up(CGPoint(x: 81, y: 0))) == .erase(CGPoint(x: 80, y: 0)))
        #expect(!g.isActive)
    }

    @Test func withoutOptionTheAppGetsEverything() {
        var g = MarkerGesture()
        #expect(g.feed(.down(.zero, option: false)) == .pass)
        #expect(g.feed(.drag(CGPoint(x: 40, y: 0))) == .pass)
        #expect(g.feed(.up(CGPoint(x: 40, y: 0))) == .pass)
        _ = g.feed(.scrollBegan(.zero))
        #expect(g.feed(.down(.zero, option: false)) == .pass, "a plain click during a two-finger stroke still goes on")
        g.cancel()
        #expect(g.feed(.up(.zero)) == .pass, "after cancel the release goes to the app")
        #expect(!g.isActive)
    }

    @Test func colorGoesWithTheStroke() {
        var g = MarkerGesture(); g.color = markerDefaultColors[2]
        _ = g.feed(.scrollBegan(.zero)); _ = g.feed(.scrollBy(dx: 30, dy: 0))
        guard case .drew(let s) = g.feed(.scrollEnded) else { Issue.record("no stroke"); return }
        #expect(s.color == markerDefaultColors[2])
    }

    @Test func theAppGetsNoPartOfAStroke() {
        // What the tap passes on: run whole gestures through the gesture and letsThrough, as MarkerTap does.
        func through(_ inputs: [MarkerInput]) -> [Bool] {
            var g = MarkerGesture()
            return inputs.map { MarkerGesture.letsThrough($0, g.feed($0)) }
        }
        #expect(through([.down(.zero, option: true), .drag(CGPoint(x: 50, y: 0)), .up(CGPoint(x: 50, y: 0))]) == [false, false, false],
                "mouse stroke: press, drag and the release that ends it are all held")
        #expect(through([.scrollBegan(.zero), .scrollBy(dx: 40, dy: 0), .scrollEnded]) == [false, false, false],
                "two-finger stroke: the lift that ends it is held too")
        #expect(through([.scrollBegan(.zero), .scrollBy(dx: 40, dy: 0), .optionUp]) == [false, false, true],
                "releasing ⌥ ends the stroke and still reaches the app")
        #expect(through([.down(.zero, option: true), .up(.zero)]) == [false, false], "⌥ + click (erase) is held")
        #expect(through([.down(.zero, option: false), .drag(CGPoint(x: 9, y: 0)), .up(CGPoint(x: 9, y: 0))]) == [true, true, true],
                "without ⌥ everything goes on")
    }

    @Test func aDroppedStrokeIsRedrawnAway() {
        // Fingers rest (a dot shows), ⌥ released without moving: the dot must go.
        var g = MarkerGesture()
        _ = g.feed(.scrollBegan(.zero))
        let was = g.isActive, action = g.feed(.optionUp)
        #expect(action == .pass && !g.isActive)
        #expect(MarkerGesture.needsRedraw(wasActive: was, isActive: g.isActive, action), "the ended stroke is cleared")
        #expect(!MarkerGesture.needsRedraw(wasActive: false, isActive: false, .pass), "plain events: no redraw")
    }

    @Test func thePenStaysOnItsScreen() {
        var g = MarkerGesture(); g.penBounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        _ = g.feed(.scrollBegan(CGPoint(x: 50, y: 50)))
        _ = g.feed(.scrollBy(dx: 100_000, dy: -100_000))
        #expect(g.current.last == CGPoint(x: 100, y: 0), "stopped at the screen edge")
        _ = g.feed(.scrollBy(dx: -30, dy: 30))
        #expect(g.current.last == CGPoint(x: 70, y: 30), "coming back draws at once")
    }

    @Test func aPressDuringATwoFingerStrokeIsHeldToItsRelease() {
        func through(_ inputs: [MarkerInput]) -> [Bool] {
            var g = MarkerGesture()
            return inputs.map { MarkerGesture.letsThrough($0, g.feed($0)) }
        }
        #expect(through([.scrollBegan(.zero), .down(.zero, option: true), .drag(CGPoint(x: 9, y: 0)), .up(CGPoint(x: 9, y: 0)), .scrollEnded])
                == [false, false, false, false, false], "the app gets no release without its press")
    }

    @Test func trackpadReadingsFollowTheFingers() {
        let p = CGPoint(x: 5, y: 5)
        #expect(ScrollReading(began: true).input(at: p) == .scrollBegan(p))
        #expect(ScrollReading(ended: true).input(at: p) == .scrollEnded)
        #expect(ScrollReading(momentum: true, changed: true, deltaX: 30).input(at: p) == .scrollBy(dx: 0, dy: 0), "momentum moves nothing")
        #expect(ScrollReading().input(at: p) == nil, "no phase (a mouse wheel): goes on to the app")
        // Fingers right and down. Natural scrolling: content moves with them (+x, +y content); off: the opposite.
        #expect(ScrollReading(changed: true, natural: true, deltaX: 10, deltaY: 4).input(at: p) == .scrollBy(dx: 10, dy: -4))
        #expect(ScrollReading(changed: true, natural: false, deltaX: -10, deltaY: -4).input(at: p) == .scrollBy(dx: 10, dy: -4),
                "the same finger movement gives the same pen movement either way")
    }

    @Test func optionShiftDrawsAStraightLine() {
        var g = MarkerGesture()
        _ = g.feed(.straight(true))
        _ = g.feed(.scrollBegan(.zero))
        for _ in 0..<5 { _ = g.feed(.scrollBy(dx: 10, dy: 3)) }
        #expect(g.current == [.zero, CGPoint(x: 50, y: 0)], "near horizontal: kept at the start's y")
        #expect(g.feed(.scrollEnded) == .drew(MarkerStroke(points: [.zero, CGPoint(x: 50, y: 0)])))
    }

    @Test func shiftMidStrokeStraightensFromTheStart() {
        var g = MarkerGesture()
        _ = g.feed(.down(.zero, option: true))
        _ = g.feed(.drag(CGPoint(x: 10, y: 20))); _ = g.feed(.drag(CGPoint(x: 30, y: 5)))
        _ = g.feed(.straight(true))
        #expect(g.current == [.zero, CGPoint(x: 30, y: 0)], "the curve so far becomes start → pen, levelled")
        _ = g.feed(.drag(CGPoint(x: 60, y: 0)))
        #expect(g.current == [.zero, CGPoint(x: 60, y: 0)])
        _ = g.feed(.straight(false))
        _ = g.feed(.drag(CGPoint(x: 70, y: 9)))
        #expect(g.current.count == 3, "⇧ released: free drawing again from there")
        #expect(MarkerGesture.letsThrough(.straight(true), .pass), "⇧ itself reaches the app")
    }

    @Test func aOneMoveStraightLineIsLevelledToo() {
        // With one move only, the end was kept as drawn.
        var g = MarkerGesture()
        _ = g.feed(.straight(true)); _ = g.feed(.scrollBegan(.zero)); _ = g.feed(.scrollBy(dx: 80, dy: 9))
        #expect(g.feed(.scrollEnded) == .drew(MarkerStroke(points: [.zero, CGPoint(x: 80, y: 0)])))
    }

    @Test func straightLinesSnapLevel() {
        let a = CGPoint(x: 100, y: 200)
        #expect(MarkerGesture.level(from: a, to: CGPoint(x: 300, y: 230)) == CGPoint(x: 300, y: 200), "almost horizontal → the start's y")
        #expect(MarkerGesture.level(from: a, to: CGPoint(x: 90, y: 500)) == CGPoint(x: 100, y: 500), "almost vertical → the start's x")
        #expect(MarkerGesture.level(from: a, to: CGPoint(x: 0, y: 170)) == CGPoint(x: 0, y: 200), "leftward too (17°)")
        #expect(MarkerGesture.level(from: a, to: CGPoint(x: 200, y: 300)) == CGPoint(x: 200, y: 300), "45°: as drawn")
        #expect(MarkerGesture.level(from: a, to: a) == a)
    }

    @Test func levellingNeverHoldsTheTwoFingerPen() {
        // Once levelled, the pen stayed on the level line.
        var g = MarkerGesture()
        _ = g.feed(.straight(true)); _ = g.feed(.scrollBegan(.zero))
        _ = g.feed(.scrollBy(dx: 500, dy: 0))
        for _ in 0..<50 { _ = g.feed(.scrollBy(dx: 0, dy: 20)) }   // small moves, as fingers send them
        #expect(g.current.last == CGPoint(x: 500, y: 1000), "right 500 then up 1000: the line follows (63°, as drawn)")
        #expect(g.pen == CGPoint(x: 500, y: 1000), "the pen (and pointer) is where the fingers went")
        g = MarkerGesture()
        _ = g.feed(.straight(true)); _ = g.feed(.scrollBegan(.zero))
        _ = g.feed(.scrollBy(dx: 60, dy: 0))
        for _ in 0..<40 { _ = g.feed(.scrollBy(dx: 10, dy: 10)) }
        #expect(g.current.last == CGPoint(x: 460, y: 400), "flat 60 then 45° 400·400: the diagonal is drawn")
    }

    @Test func cancelEndsStraightMode() {
        var g = MarkerGesture()
        _ = g.feed(.straight(true)); g.cancel()
        _ = g.feed(.scrollBegan(.zero))
        for i in 1...6 { _ = g.feed(.scrollBy(dx: 10, dy: CGFloat(i % 2) * 8)) }
        #expect(g.current.count == 7, "free drawing after cancel")
    }

    @Test func shiftAtTwoPointsLevelsAtOnce() {
        var g = MarkerGesture()
        _ = g.feed(.down(.zero, option: true)); _ = g.feed(.drag(CGPoint(x: 50, y: 6)))
        _ = g.feed(.straight(true))
        #expect(g.current == [.zero, CGPoint(x: 50, y: 0)], "levelled when ⇧ comes")
    }
}
