// ⌘ ⌘ M while recording: the video shows the part around the pointer at twice the size, moving with the pointer;
// ⌘ ⌘ M again goes back. The screen does not change: the recorded rect shrinks (ScreenCaptureKit scales it to the
// video's size). It eases in and out over about a quarter of a second.
import AppKit

enum Zoom {
    static let factor: CGFloat = 2
    /// Rounding slack, in points: a step can end a hair past the recorded rect. Used here and by the recorder.
    static let slack: CGFloat = 0.5

    /// `r` (display points, top-left origin, of the screen at `screen`) in Cocoa global points (bottom-left origin).
    static func global(_ r: CGRect, on screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + r.minX, y: screen.maxY - r.maxY, width: r.width, height: r.height)
    }

    /// `rect` is inside `base`, give or take `slack`.
    static func inside(_ rect: CGRect, _ base: CGRect) -> Bool {
        base.insetBy(dx: -slack, dy: -slack).contains(rect)
    }

    /// The part of `base` shown when zoomed around `p` (display points, top-left origin): `factor` times smaller,
    /// centred on `p`, kept inside `base`.
    static func rect(in base: CGRect, around p: CGPoint, factor: CGFloat = factor) -> CGRect {
        let w = base.width / factor, h = base.height / factor
        let x = min(max(p.x - w / 2, base.minX), base.maxX - w), y = min(max(p.y - h / 2, base.minY), base.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Where the next step starts: the shown rect when it is inside the recorded rect now, else the recorded rect
    /// itself (the window moved, or a step from before a reset). With both ends inside `base`, every step is.
    static func start(shown: CGRect?, base: CGRect) -> CGRect {
        guard let shown, inside(shown, base) else { return base }   // with the slack (restarts)
        return shown
    }

    /// One step from `a` toward `b`: `share` of the way, or all of it when less than half a point is left.
    static func step(from a: CGRect, to b: CGRect, share: CGFloat = 0.35) -> CGRect {
        let d = max(abs(b.minX - a.minX), abs(b.minY - a.minY), abs(b.width - a.width), abs(b.height - a.height))
        guard d > 0.5 else { return b }
        func mix(_ u: CGFloat, _ v: CGFloat) -> CGFloat { u + (v - u) * share }
        return CGRect(x: mix(a.minX, b.minX), y: mix(a.minY, b.minY), width: mix(a.width, b.width), height: mix(a.height, b.height))
    }
}

/// Moves the shown rect of a recording toward the zoom target 20 times a second while it is on or easing out.
@MainActor
final class Zoomer {
    private(set) var isOn = false
    private var shown: CGRect?, timer: Timer?, busy = false
    private var round = 0   // counts resets, so a step that comes back after one is not counted
    private var pause = 0   // ticks to skip after a refused step
    /// The part the video shows (Cocoa global) after each step while zoomed; nil when it shows the whole recorded rect.
    var onShown: (CGRect?) -> Void = { _ in }

    func toggle(_ recorder: ScreenRecorder) {
        guard recorder.recordedArea != nil else { return }
        isOn.toggle()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self, weak recorder] _ in
            MainActor.assumeIsolated { if let self, let recorder { self.tick(recorder) } }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The recording stopped or its rect moved (the window was followed): no zoom.
    func reset() {
        timer?.invalidate(); timer = nil; isOn = false; shown = nil; busy = false; pause = 0; round += 1
        onShown(nil)
    }

    private func tick(_ recorder: ScreenRecorder) {
        guard !busy, let base = recorder.base else { if recorder.base == nil { reset() }; return }
        if pause > 0 { pause -= 1; return }
        let s = recorder.screenFrame, m = NSEvent.mouseLocation
        let target = isOn ? Zoom.rect(in: base, around: CGPoint(x: m.x - s.minX, y: s.maxY - m.y)) : base
        let from = Zoom.start(shown: shown, base: base)
        let next = Zoom.step(from: from, to: target)
        if next == from {
            if !isOn { reset() }   // eased out
            return
        }
        busy = true
        let epoch = recorder.gate.epoch, round = self.round
        Task {
            let ok = await recorder.show(next, epoch: epoch)
            guard round == self.round else { return }   // reset meanwhile: this step belongs to the old zoom
            if ok {
                shown = next
                onShown(next == base ? nil : Zoom.global(next, on: recorder.screenFrame))
            } else { pause = 10 }   // refused: wait half a second before trying again
            busy = false
        }
    }
}

/// One change of the recorded rect at a time, in order (the zoom and following a window both change it, and each
/// waits for ScreenCaptureKit). `epoch` counts the changes that make older zoom steps stale: a step asked for in
/// an older epoch is not applied.
@MainActor
final class ConfigGate {
    private(set) var epoch = 0
    private var busy = false, waiting: [CheckedContinuation<Void, Never>] = []

    /// A follow or a stop: zoom steps asked for before this are dropped.
    func newEpoch() { epoch += 1 }

    /// Runs `change` after the changes before it; nil when `epoch` is given and is no longer current by then.
    func run<T>(in epoch: Int? = nil, _ change: () async -> T) async -> T? {
        if busy { await withCheckedContinuation { waiting.append($0) } } else { busy = true }
        defer { if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() } }   // handed on, still busy
        if let epoch, epoch != self.epoch { return nil }
        return await change()
    }
}
