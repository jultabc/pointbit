// What part of the display is recorded, and at what size.
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Testing
@testable import PointbitKit

struct RecordingPlanTests {
    @Test func halfSizeIsThePointSize() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let full = RecordingPlan(area: screen, screen: screen, scale: 2)!, half = RecordingPlan(area: screen, screen: screen, scale: 1)!
        #expect(full.width == 3600 && full.height == 2338, "Retina pixels")
        #expect(half.width == 1800 && half.height == 1168 && half.sourceRect == full.sourceRect, "same area, half each way (even)")
    }

    @Test func windowOnMainScreen() {
        // main screen 1800 × 1169 points at 2×; window at x 100, 200 points from the bottom, 640 × 480
        let p = RecordingPlan(area: CGRect(x: 100, y: 200, width: 640, height: 480),
                              screen: CGRect(x: 0, y: 0, width: 1800, height: 1169), scale: 2)
        #expect(p?.sourceRect == CGRect(x: 100, y: 1169 - 680, width: 640, height: 480))   // top-left origin
        #expect(p?.width == 1280 && p?.height == 960)
    }
    @Test func wholeScreen() {
        let s = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let p = RecordingPlan(area: s, screen: s, scale: 2)
        #expect(p?.sourceRect == CGRect(x: 0, y: 0, width: 1800, height: 1169))
        #expect(p?.width == 3600 && p?.height == 2338)
    }
    @Test func sizesAreEven() {
        let p = RecordingPlan(area: CGRect(x: 0, y: 0, width: 101, height: 51),
                              screen: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 1)
        #expect(p?.width == 100 && p?.height == 50)
    }
    @Test func secondScreenToTheRight() {
        // second screen right of a 1800-wide main screen, its own origin at x 1800
        let screen = CGRect(x: 1800, y: 0, width: 1920, height: 1080)
        let p = RecordingPlan(area: CGRect(x: 1900, y: 100, width: 400, height: 300), screen: screen, scale: 1)
        #expect(p?.sourceRect == CGRect(x: 100, y: 1080 - 400, width: 400, height: 300))
    }
    @Test func windowPartlyOffScreenIsClipped() {
        let p = RecordingPlan(area: CGRect(x: -50, y: 0, width: 200, height: 100),
                              screen: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 1)
        #expect(p?.sourceRect.minX == 0 && p?.width == 150)
    }
    @Test func theRecorderLogNeverHoldsAPath() {
        let under = NSError(domain: NSOSStatusErrorDomain, code: -12737, userInfo: [NSFilePathErrorKey: "/Users/x/private.mov"])
        let e = NSError(domain: "AVFoundationErrorDomain", code: -11800,
                        userInfo: [NSFilePathErrorKey: "/Users/x/private.mov", NSUnderlyingErrorKey: under])
        #expect(logCode(e) == "AVFoundationErrorDomain -11800 (NSOSStatusErrorDomain -12737)")
        #expect(logCode(nil) == "none")
    }
    @Test func aMovedWindowIsFollowedAtTheSameSize() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let p = RecordingPlan(area: CGRect(x: 100, y: 200, width: 640, height: 480), screen: screen, scale: 1)!
        // 50 right and 100 up (Cocoa y grows upward): 100 less from the top
        #expect(p.following(CGRect(x: 150, y: 300, width: 640, height: 480), on: screen)
                == CGRect(x: 150, y: 1169 - 780, width: 640, height: 480))
        // a resized window keeps the first size
        #expect(p.following(CGRect(x: 150, y: 300, width: 900, height: 700), on: screen).size == CGSize(width: 640, height: 480))
    }
    @Test func aFollowedRectStaysOnTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let p = RecordingPlan(area: CGRect(x: 100, y: 200, width: 640, height: 480), screen: screen, scale: 1)!
        #expect(p.following(CGRect(x: -300, y: 900, width: 640, height: 480), on: screen).origin == .zero, "left and top edge")
        #expect(p.following(CGRect(x: 1500, y: -200, width: 640, height: 480), on: screen).origin
                == CGPoint(x: 1800 - 640, y: 1169 - 480), "right and bottom edge")
    }
    @Test func nothingOnThisScreen() {
        #expect(RecordingPlan(area: CGRect(x: 5000, y: 0, width: 10, height: 10),
                              screen: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 1) == nil)
    }
}

/// Moving the recorded rect: the configuration keeps the old rect when ScreenCaptureKit refuses the change.
struct FollowMoveTests {
    struct Refused: Error {}

    @Test func aRefusedMoveKeepsTheOldRect() async {
        let c = SCStreamConfiguration(); c.sourceRect = CGRect(x: 10, y: 10, width: 100, height: 80)
        let ok = await ScreenRecorder.move(c, to: CGRect(x: 50, y: 10, width: 100, height: 80)) { _ in throw Refused() }
        #expect(!ok && c.sourceRect == CGRect(x: 10, y: 10, width: 100, height: 80))
    }

    @Test func anAcceptedMoveKeepsTheNewRect() async {
        let c = SCStreamConfiguration(); c.sourceRect = CGRect(x: 10, y: 10, width: 100, height: 80)
        var handed: CGRect?
        let ok = await ScreenRecorder.move(c, to: CGRect(x: 50, y: 10, width: 100, height: 80)) { handed = $0.sourceRect }
        #expect(ok && c.sourceRect.minX == 50 && handed?.minX == 50, "the update gets the new rect")
    }

    @Test func theSameRectIsNoChange() async {
        let c = SCStreamConfiguration(); c.sourceRect = CGRect(x: 10, y: 10, width: 100, height: 80)
        var calls = 0
        let ok = await ScreenRecorder.move(c, to: c.sourceRect) { _ in calls += 1 }
        #expect(ok && calls == 0)
    }
}
