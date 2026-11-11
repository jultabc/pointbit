// ⌘ ⌘ D's box: what a press grabs and the box after a drag.
import CoreGraphics
import Testing
@testable import PointbitKit

struct AreaDragTests {
    let box = CGRect(x: 100, y: 100, width: 400, height: 300)
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func cornersEdgesInsideAndOutside() {
        #expect(AreaDrag.grip(at: CGPoint(x: 102, y: 398), in: box) == .edges(left: true, right: false, bottom: false, top: true))
        #expect(AreaDrag.grip(at: CGPoint(x: 505, y: 250), in: box) == .edges(left: false, right: true, bottom: false, top: false))
        #expect(AreaDrag.grip(at: CGPoint(x: 300, y: 250), in: box) == .move)
        #expect(AreaDrag.grip(at: CGPoint(x: 600, y: 250), in: box) == nil, "outside the reach")
    }

    @Test func aCornerResizesTwoSidesOnly() {
        let r = AreaDrag.apply(.edges(left: false, right: true, bottom: true, top: false), by: CGVector(dx: 50, dy: -20), to: box, within: screen)
        #expect(r == CGRect(x: 100, y: 80, width: 450, height: 320))
    }

    @Test func movingKeepsTheSizeAndStaysOnTheScreen() {
        #expect(AreaDrag.apply(.move, by: CGVector(dx: 30, dy: 40), to: box, within: screen) == CGRect(x: 130, y: 140, width: 400, height: 300))
        #expect(AreaDrag.apply(.move, by: CGVector(dx: 900, dy: -900), to: box, within: screen) == CGRect(x: 600, y: 0, width: 400, height: 300))
    }

    @Test func aNewBoxSpansThePressAndThePointerInAnyDirection() {
        #expect(AreaDrag.span(from: CGPoint(x: 600, y: 500), to: CGPoint(x: 200, y: 100), within: screen) == CGRect(x: 200, y: 100, width: 400, height: 400))
        #expect(AreaDrag.span(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 11), within: screen).size == CGSize(width: 32, height: 32), "a click is a small box")
        #expect(AreaDrag.span(from: CGPoint(x: 900, y: 700), to: CGPoint(x: 1500, y: 1200), within: screen).maxX == 1000, "inside the screen")
    }
    @Test func thePointerGoesWithTheHeldPart() {
        let moved = AreaDrag.apply(.move, by: CGVector(dx: 900, dy: 10), to: box, within: screen)
        #expect(AreaDrag.moved(.move, from: box, to: moved) == CGVector(dx: 500, dy: 10), "stopped at the screen edge")
        let right = AreaGrip.edges(left: false, right: true, bottom: false, top: false)
        #expect(AreaDrag.moved(right, from: box, to: AreaDrag.apply(right, by: CGVector(dx: 20, dy: 30), to: box, within: screen))
                == CGVector(dx: 20, dy: 0), "an edge moves one way only")
    }
    @Test func smallStepsAddUp() {
        var r = box
        for _ in 0..<100 { r = AreaDrag.apply(.move, by: CGVector(dx: 0.4, dy: -0.5), to: r, within: screen) }
        #expect(AreaDrag.whole(r, within: screen) == CGRect(x: 140, y: 50, width: 400, height: 300), "0.4 x 100 moved nothing")
    }
    @Test func theRecordedRectIsWholeAndOnTheScreen() {
        let r = AreaDrag.whole(AreaDrag.span(from: CGPoint(x: 10.5, y: 10), to: CGPoint(x: 1200, y: 50), within: screen), within: screen)
        #expect(r.minX == 11 && r.maxX == 1000, "maxX was 1001")
    }
    @Test func aBoxOnTheSecondScreenIsPutBackOnIt() {
        // A second screen at x 1000; the box at x 100 of it is at x 1100 on the desktop.
        #expect(AreaPicker.global(CGRect(x: 100, y: 50, width: 300, height: 200), on: CGRect(x: 1000, y: -200, width: 1920, height: 1080))
                == CGRect(x: 1100, y: -150, width: 300, height: 200))
    }
    @Test func anEdgeStopsAtTheMinimumAndTheScreen() {
        let narrow = AreaDrag.apply(.edges(left: true, right: false, bottom: false, top: false), by: CGVector(dx: 1000, dy: 0), to: box, within: screen)
        #expect(narrow.width == AreaDrag.minSide && narrow.maxX == 500)
        let wide = AreaDrag.apply(.edges(left: true, right: false, bottom: false, top: false), by: CGVector(dx: -500, dy: 0), to: box, within: screen)
        #expect(wide.minX == 0 && wide.maxX == 500)
    }
}
