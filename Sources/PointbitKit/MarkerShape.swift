// Turns a hand-drawn closed loop into a clean ellipse (a circle when it is nearly round). Pure: no AppKit.
// A stroke counts as a loop when it comes back near its start, goes once around its centre, and stays near the
// ellipse that fits its bounding box. Anything else is left as drawn. ⌘ ⌘ Z on a turned stroke brings back the
// hand-drawn line first (MarkerStrokes.undo).
import CoreGraphics

enum MarkerShape {
    static let minPoints = 12
    static let minSize: CGFloat = 20              // points, the bounding box's shorter side
    static let closeGap: CGFloat = 0.3            // end-to-start gap, as a share of the box's longer side
    static let minTurn: CGFloat = 300             // degrees swept around the centre
    static let maxMiss: CGFloat = 0.1             // mean distance from the fitted ellipse, as a share of its radius
    static let roundEnough: CGFloat = 0.12        // axes this close (share of the longer) make a circle
    static let outlinePoints = 72

    /// The ellipse outline for `points`, or nil when they do not look like a closed loop.
    static func ellipse(for points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= minPoints, let first = points.first, let last = points.last else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let w = maxX - minX, h = maxY - minY
        guard min(w, h) >= minSize else { return nil }
        guard MarkerStrokes.length(first, last) <= closeGap * max(w, h) else { return nil }
        let c = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        guard abs(turn(points, around: c)) >= minTurn else { return nil }
        var a = w / 2, b = h / 2
        let miss = points.map { p -> CGFloat in
            let dx = (p.x - c.x) / a, dy = (p.y - c.y) / b
            return abs((dx * dx + dy * dy).squareRoot() - 1)
        }.reduce(0, +) / CGFloat(points.count)
        guard miss <= maxMiss else { return nil }
        if abs(a - b) <= roundEnough * max(a, b) { a = (a + b) / 2; b = a }
        // Start the outline at the angle the hand started, so the line begins where it was drawn.
        let start = atan2(first.y - c.y, first.x - c.x)
        return (0...outlinePoints).map { i in
            let t = start + CGFloat(i) / CGFloat(outlinePoints) * 2 * .pi
            return CGPoint(x: c.x + a * cos(t), y: c.y + b * sin(t))
        }
    }

    /// Total angle (degrees) the points sweep around `c`; the sign is the direction.
    static func turn(_ points: [CGPoint], around c: CGPoint) -> CGFloat {
        var total: CGFloat = 0
        for (p, q) in zip(points, points.dropFirst()) {
            var d = atan2(q.y - c.y, q.x - c.x) - atan2(p.y - c.y, p.x - c.x)
            if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
            total += d
        }
        return total * 180 / .pi
    }
}
