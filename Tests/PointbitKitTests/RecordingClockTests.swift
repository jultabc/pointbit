// The menu bar count: whole seconds since the start.
import AppKit
import Foundation
import Testing
@testable import PointbitKit

struct RecordingClockTests {
    @Test func wholeSecondsSinceTheStart() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        #expect(RecordingClock.seconds(from: t0, to: t0) == 0)
        #expect(RecordingClock.seconds(from: t0, to: t0.addingTimeInterval(0.99)) == 0)
        #expect(RecordingClock.seconds(from: t0, to: t0.addingTimeInterval(1)) == 1)
        #expect(RecordingClock.seconds(from: t0, to: t0.addingTimeInterval(125.4)) == 125, "no minutes: 125, not 2:05")
        #expect(RecordingClock.seconds(from: t0, to: t0.addingTimeInterval(-5)) == 0, "the clock went back")
    }
}

/// The menu bar button is put back as it was when the recording stops.
@MainActor
struct RecordingClockButtonTests {
    @Test func stopPutsTheIconBack() throws {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let icon = NSImage(size: NSSize(width: 18, height: 18)); icon.accessibilityDescription = appName
        item.button?.image = icon
        let clock = RecordingClock()
        clock.start(in: item)
        #expect(item.button?.image == nil && item.button?.title == "0" && item.length == NSStatusItem.variableLength)
        #expect(item.button?.accessibilityLabel()?.contains("recording") == true)
        clock.stop(showing: icon)
        #expect(item.button?.image === icon && item.button?.title == "" && item.length == NSStatusItem.squareLength)
        #expect(item.button?.accessibilityLabel()?.contains("recording") != true, "no 'recording' after it stopped")
    }
}
