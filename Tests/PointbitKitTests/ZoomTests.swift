// ⌘ ⌘ M: the zoomed part of the recorded rect, and the easing toward it.
import CoreGraphics
import Testing
@testable import PointbitKit

struct ZoomTests {
    let base = CGRect(x: 100, y: 50, width: 800, height: 600)

    @Test func halfTheSizeAroundThePointer() {
        #expect(Zoom.rect(in: base, around: CGPoint(x: 500, y: 350)) == CGRect(x: 300, y: 200, width: 400, height: 300))
    }

    @Test func theShownPartInGlobalPoints() {
        // The box on the screen goes where the video looks: top-left origin of a screen → Cocoa's bottom-left.
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900), right = CGRect(x: 1440, y: -180, width: 1920, height: 1080)
        #expect(Zoom.global(CGRect(x: 300, y: 200, width: 400, height: 300), on: main) == CGRect(x: 300, y: 400, width: 400, height: 300))
        #expect(Zoom.global(CGRect(x: 0, y: 0, width: 960, height: 540), on: right) == CGRect(x: 1440, y: 360, width: 960, height: 540),
                "a second screen: its top edge is at y 900")
    }

    @Test func keptInsideTheRecordedRect() {
        #expect(Zoom.rect(in: base, around: CGPoint(x: 110, y: 60)).origin == CGPoint(x: 100, y: 50), "top-left corner")
        #expect(Zoom.rect(in: base, around: CGPoint(x: 5000, y: 5000)) == CGRect(x: 500, y: 350, width: 400, height: 300))
    }

    @Test func everyStepStaysInsideTheRecordedRect() {
        // A shown rect from the old place (the window moved) stepped outside the new one.
        let stale = CGRect(x: 1200, y: 700, width: 400, height: 300), now = CGRect(x: 0, y: 0, width: 800, height: 600)
        var r = Zoom.start(shown: stale, base: now)
        #expect(r == now, "starts from the recorded rect, not the old place")
        let target = Zoom.rect(in: now, around: CGPoint(x: 700, y: 500))
        for _ in 0..<40 { r = Zoom.step(from: r, to: target); #expect(now.contains(r)) }
        #expect(Zoom.start(shown: target, base: now) == target, "a shown rect inside is kept")
    }

    @Test func theZoomArrivesFromAnyBaseAndCorner() {
        // Rounding made a shown rect "outside", so the zoom restarted over and over.
        var missed = 0
        for x in stride(from: 0, through: 900, by: 101) { for w in stride(from: 300, through: 1600, by: 173) {
            for h in stride(from: 200, through: 1000, by: 123) {
                let base = CGRect(x: CGFloat(x) + 0.0, y: 0, width: CGFloat(w), height: CGFloat(h))
                for p in [CGPoint(x: base.minX, y: base.minY), CGPoint(x: base.maxX, y: base.maxY),
                          CGPoint(x: base.maxX, y: base.minY), CGPoint(x: base.midX + 3, y: base.midY - 7)] {
                    let target = Zoom.rect(in: base, around: p)
                    var shown: CGRect?
                    for _ in 0..<200 { shown = Zoom.step(from: Zoom.start(shown: shown, base: base), to: target) }
                    if shown != target { missed += 1 }
                }
            }
        } }
        #expect(missed == 0)
        #expect(Zoom.inside(CGRect(x: 0, y: 0, width: 800.3, height: 600), CGRect(x: 0, y: 0, width: 800, height: 600)))
    }

    @Test func easesThenArrives() {
        let target = CGRect(x: 300, y: 200, width: 400, height: 300)
        var r = base, steps = 0
        while r != target && steps < 100 { r = Zoom.step(from: r, to: target); steps += 1 }
        #expect(r == target && steps > 3 && steps < 30, "a few frames, then exactly there (\(steps))")
    }
}

/// The zoom and following a window change the recorded rect one at a time, and a stale zoom step is dropped.
@MainActor
struct ConfigGateTests {
    @Test func changesRunOneAtATimeInOrder() async {
        let gate = ConfigGate()
        var log: [String] = []
        var release: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            await gate.run { log.append("show starts"); await withCheckedContinuation { release = $0 }; log.append("show ends") }
        }
        await Task.yield(); await Task.yield()
        let second = Task { @MainActor in await gate.run { log.append("follow") } }
        await Task.yield(); await Task.yield()
        #expect(log == ["show starts"], "the follow waits")
        release?.resume()
        _ = await first.value; _ = await second.value
        #expect(log == ["show starts", "show ends", "follow"])
    }

    @Test func aZoomStepAskedForDuringAFollowIsDropped() async {
        // ⌘ ⌘ M while a follow waits: the step, made against the old place, queues behind the follow.
        let gate = ConfigGate()
        var release: CheckedContinuation<Void, Never>?
        let follow = Task { @MainActor in
            gate.newEpoch()
            await gate.run { await withCheckedContinuation { release = $0 }; gate.newEpoch() }   // the follow's own change
        }
        await Task.yield(); await Task.yield()
        let during = gate.epoch   // what the zoom tick reads while the follow waits
        var applied = false
        let step = Task { @MainActor in await gate.run(in: during) { applied = true } }
        await Task.yield()
        release?.resume()
        _ = await follow.value
        let r = await step.value
        #expect(r == nil && !applied, "dropped: the next tick recomputes against the new place")
    }

    @Test func aZoomStepFromBeforeAFollowIsDropped() async {
        let gate = ConfigGate()
        let epoch = gate.epoch
        gate.newEpoch()   // a follow came first
        var applied = false
        let r = await gate.run(in: epoch) { applied = true; return true }
        #expect(r == nil && !applied)
        let now = await gate.run(in: gate.epoch) { true }
        #expect(now == true)
    }
}
