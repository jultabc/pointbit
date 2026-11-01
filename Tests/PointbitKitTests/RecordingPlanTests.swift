// What part of the display is recorded, and at what size.
import CoreGraphics
import Testing
@testable import PointbitKit

struct RecordingPlanTests {
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
    @Test func nothingOnThisScreen() {
        #expect(RecordingPlan(area: CGRect(x: 5000, y: 0, width: 10, height: 10),
                              screen: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 1) == nil)
    }
}
