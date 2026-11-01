// Start / stop order of a recording, including stops that arrive while the recording is still starting.
import Testing
@testable import PointbitKit

struct RecordingLifecycleTests {
    @Test func startThenStop() {
        var l = RecordingLifecycle()
        #expect(l.toggle() == .start)
        #expect(l.started(ok: true) == nil && l.state == .recording)
        #expect(l.toggle() == .stop && l.state == .stopping)
        l.stopped()
        #expect(l.state == .idle && !l.isActive)
    }
    @Test func stopWhileStartingStopsRightAfterTheStart() {
        var l = RecordingLifecycle()
        _ = l.toggle()
        #expect(l.requestStop() == nil && l.isActive)          // feature off / quit during the start
        #expect(l.started(ok: true) == .stop && l.state == .stopping)
        l.stopped()
        #expect(!l.isActive)
    }
    @Test func secondShortcutWhileStartingAlsoStops() {
        var l = RecordingLifecycle()
        _ = l.toggle()
        #expect(l.toggle() == nil)
        #expect(l.started(ok: true) == .stop)
    }
    @Test func failedStartGoesIdleAndDropsTheStop() {
        var l = RecordingLifecycle()
        _ = l.toggle(); _ = l.requestStop()
        #expect(l.started(ok: false) == nil && !l.isActive)
        #expect(l.toggle() == .start)                          // a later start is not stopped by the old request
        #expect(l.started(ok: true) == nil && l.state == .recording)
    }
    @Test func stopWhileStoppingDoesNothingMore() {
        var l = RecordingLifecycle()
        _ = l.toggle(); _ = l.started(ok: true); _ = l.toggle()
        #expect(l.toggle() == nil && l.requestStop() == nil && l.isActive)
    }
    @Test func stopWhenIdleDoesNothing() {
        var l = RecordingLifecycle()
        #expect(l.requestStop() == nil && !l.isActive)
    }
}
