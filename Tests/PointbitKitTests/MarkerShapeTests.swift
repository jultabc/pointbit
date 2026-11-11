// Closed loops become ellipses; other strokes stay as drawn.
import CoreGraphics
import Foundation
import Testing
@testable import PointbitKit

struct MarkerShapeTests {
    /// A hand-like loop: radius wobbles by `wobble`, ends `gap` degrees short of the start.
    private func loop(center c: CGPoint = CGPoint(x: 300, y: 300), a: CGFloat, b: CGFloat, wobble: CGFloat = 0.06,
                      gap: CGFloat = 20, n: Int = 60) -> [CGPoint] {
        (0..<n).map { i in
            let t = CGFloat(i) / CGFloat(n - 1) * (2 * .pi - gap * .pi / 180)
            let k = 1 + wobble * sin(5 * t)
            return CGPoint(x: c.x + a * k * cos(t), y: c.y + b * k * sin(t))
        }
    }

    @Test func aWobblyCircleBecomesACircle() {
        guard let e = MarkerShape.ellipse(for: loop(a: 80, b: 76)) else { Issue.record("not recognized"); return }
        let c = CGPoint(x: e.dropLast().map(\.x).reduce(0, +) / CGFloat(e.count - 1), y: e.dropLast().map(\.y).reduce(0, +) / CGFloat(e.count - 1))
        let rs = e.map { MarkerStrokes.length($0, c) }
        #expect(rs.max()! - rs.min()! < 1.5, "one radius: a circle")
        #expect(e.count == MarkerShape.outlinePoints + 1)
    }

    @Test func aWideLoopBecomesAnEllipse() {
        guard let e = MarkerShape.ellipse(for: loop(a: 150, b: 50)) else { Issue.record("not recognized"); return }
        let xs = e.map(\.x), ys = e.map(\.y)
        #expect(xs.max()! - xs.min()! > 2.5 * (ys.max()! - ys.min()!), "kept long, around a wide button")
    }

    @Test func otherStrokesStayAsDrawn() {
        #expect(MarkerShape.ellipse(for: loop(a: 80, b: 80, gap: 150)) == nil, "an open arc (C shape)")
        #expect(MarkerShape.ellipse(for: (0..<30).map { CGPoint(x: CGFloat($0) * 10, y: 0) }) == nil, "a line")
        #expect(MarkerShape.ellipse(for: loop(a: 8, b: 8)) == nil, "too small")
        #expect(MarkerShape.ellipse(for: loop(a: 80, b: 80, wobble: 0.35)) == nil, "too far from round")
        // A hand-drawn box: four sides, back to the start.
        var box: [CGPoint] = []
        for i in 0..<15 { box.append(CGPoint(x: CGFloat(i) * 10, y: 0)) }
        for i in 0..<15 { box.append(CGPoint(x: 150, y: CGFloat(i) * 10)) }
        for i in 0..<15 { box.append(CGPoint(x: 150 - CGFloat(i) * 10, y: 150)) }
        for i in 0..<15 { box.append(CGPoint(x: 0, y: 150 - CGFloat(i) * 10)) }
        #expect(MarkerShape.ellipse(for: box) == nil, "a box stays a box")
    }

    @Test func undoBringsBackTheHandDrawnLineFirst() {
        var g = MarkerGesture()
        let hand = loop(a: 80, b: 78)
        _ = g.feed(.down(hand[0], option: true))
        for p in hand.dropFirst() { _ = g.feed(.drag(p)) }
        guard case .drew(let s) = g.feed(.up(hand.last!)), s.drawn != nil else { Issue.record("not turned"); return }
        var m = MarkerStrokes(); m.add(s)
        #expect(m.undo() && m.strokes.count == 1 && m.strokes[0].drawn == nil, "first ⌘⌘Z: the hand-drawn line")
        #expect(m.strokes[0].points.count == hand.count + 1)
        #expect(m.undo() && m.strokes.isEmpty, "second ⌘⌘Z: gone")
    }
}
