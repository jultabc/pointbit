// What to record: a display, and the part of it (points, top-left origin on that display) plus the video size.
// Pure: no ScreenCaptureKit.
import CoreGraphics

struct RecordingPlan: Equatable {
    var sourceRect: CGRect   // on the display, top-left origin, points
    var width: Int           // video pixels, even
    var height: Int

    /// `area` and `screen` are Cocoa global rects (bottom-left origin of the main screen); `scale` is the screen's
    /// backing scale. `area` is clipped to the screen. nil when nothing is left.
    init?(area: CGRect, screen: CGRect, scale: CGFloat) {
        let a = area.intersection(screen)
        guard !a.isNull, a.width >= 2, a.height >= 2 else { return nil }
        sourceRect = CGRect(x: a.minX - screen.minX, y: screen.maxY - a.maxY, width: a.width, height: a.height)
        func even(_ v: CGFloat) -> Int { let i = Int((v * scale).rounded()); return i - i % 2 }   // H.264 needs even sizes
        width = even(a.width); height = even(a.height)
    }

    /// The source rect after the recorded window moved to `area` (Cocoa global) on `screen`: the same size, at the
    /// window's new top-left corner, kept inside the screen.
    func following(_ area: CGRect, on screen: CGRect) -> CGRect {
        let x = min(max(area.minX - screen.minX, 0), max(screen.width - sourceRect.width, 0))
        let y = min(max(screen.maxY - area.maxY, 0), max(screen.height - sourceRect.height, 0))
        return CGRect(origin: CGPoint(x: x, y: y), size: sourceRect.size)
    }
}

/// Start / stop order of one recording. Pure: the controller does the work the returned command names.
/// A stop asked while the recording is still starting is kept and done as soon as the start finishes, so a
/// started recording is always stopped and its file finished.
struct RecordingLifecycle: Equatable {
    enum State: Equatable { case idle, starting, recording, stopping }
    enum Command: Equatable { case start, stop }
    private(set) var state = State.idle
    private var stopAfterStart = false

    /// Something is in progress or recording (quitting has to wait).
    var isActive: Bool { state != .idle }

    /// The shortcut: start when idle, stop when recording (or as soon as the start finishes).
    mutating func toggle() -> Command? {
        switch state {
        case .idle: state = .starting; return .start
        default: return requestStop()
        }
    }

    /// Feature off or quitting.
    mutating func requestStop() -> Command? {
        switch state {
        case .starting: stopAfterStart = true; return nil
        case .recording: state = .stopping; return .stop
        case .idle, .stopping: return nil
        }
    }

    mutating func started(ok: Bool) -> Command? {
        guard state == .starting else { return nil }
        guard ok else { state = .idle; stopAfterStart = false; return nil }
        if stopAfterStart { stopAfterStart = false; state = .stopping; return .stop }
        state = .recording; return nil
    }

    mutating func stopped() { state = .idle }
}
