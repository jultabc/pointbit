// ⌘ ⌘ D: which part of the box a press grabs, and the box after a drag. Pure: no AppKit.
// Rects are Cocoa (bottom-left origin). A corner or an edge resizes; inside moves the whole box; outside draws a new one.
import CoreGraphics

enum AreaGrip: Equatable {
    case move
    case edges(left: Bool, right: Bool, bottom: Bool, top: Bool)
}

enum AreaDrag {
    static let reach: CGFloat = 10      // points from an edge that still grab it
    static let minSide: CGFloat = 32

    /// What a press at `p` grabs: an edge or a corner (within `reach` of it), inside, or nothing (outside).
    static func grip(at p: CGPoint, in r: CGRect) -> AreaGrip? {
        guard r.insetBy(dx: -reach, dy: -reach).contains(p) else { return nil }
        let left = abs(p.x - r.minX) <= reach, right = !left && abs(p.x - r.maxX) <= reach
        let bottom = abs(p.y - r.minY) <= reach, top = !bottom && abs(p.y - r.maxY) <= reach
        if left || right || bottom || top { return .edges(left: left, right: right, bottom: bottom, top: top) }
        return .move
    }

    /// A new box from a press at `a` to `p` (any direction), at least `minSide` each way, inside `bounds`.
    static func span(from a: CGPoint, to p: CGPoint, within bounds: CGRect) -> CGRect {
        let x0 = min(max(min(a.x, p.x), bounds.minX), bounds.maxX - minSide)
        let y0 = min(max(min(a.y, p.y), bounds.minY), bounds.maxY - minSide)
        let x1 = min(max(max(a.x, p.x), x0 + minSide), bounds.maxX)
        let y1 = min(max(max(a.y, p.y), y0 + minSide), bounds.maxY)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// `r` on whole points, its edges rounded and kept inside `bounds`. Drags add up unrounded (a move of 0.4 a
    /// step would never move a rounded box); this is done once, for the rect that is recorded.
    static func whole(_ r: CGRect, within bounds: CGRect) -> CGRect {
        let x0 = max(r.minX.rounded(), bounds.minX.rounded(.up)), y0 = max(r.minY.rounded(), bounds.minY.rounded(.up))
        let x1 = min(r.maxX.rounded(), bounds.maxX.rounded(.down)), y1 = min(r.maxY.rounded(), bounds.maxY.rounded(.down))
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// How far the part `grip` holds moved from `a` to `b` (the pointer goes along with it).
    static func moved(_ grip: AreaGrip, from a: CGRect, to b: CGRect) -> CGVector {
        switch grip {
        case .move: return CGVector(dx: b.minX - a.minX, dy: b.minY - a.minY)
        case let .edges(left, right, bottom, top):
            return CGVector(dx: left ? b.minX - a.minX : right ? b.maxX - a.maxX : 0,
                            dy: bottom ? b.minY - a.minY : top ? b.maxY - a.maxY : 0)
        }
    }

    /// `r` after dragging `grip` by `d`, kept inside `bounds`, at least `minSide` each way (not rounded: `whole`).
    static func apply(_ grip: AreaGrip, by d: CGVector, to r: CGRect, within bounds: CGRect) -> CGRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch grip {
        case .move:
            let dx = min(max(d.dx, bounds.minX - r.minX), bounds.maxX - r.maxX)
            let dy = min(max(d.dy, bounds.minY - r.minY), bounds.maxY - r.maxY)
            minX += dx; maxX += dx; minY += dy; maxY += dy
        case let .edges(left, right, bottom, top):
            if left { minX = min(max(minX + d.dx, bounds.minX), maxX - minSide) }
            if right { maxX = max(min(maxX + d.dx, bounds.maxX), minX + minSide) }
            if bottom { minY = min(max(minY + d.dy, bounds.minY), maxY - minSide) }
            if top { maxY = max(min(maxY + d.dy, bounds.maxY), minY + minSide) }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
