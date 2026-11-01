// Click mark calculation and defaults.
import Testing
@testable import PointbitKit

struct ClickStyleTests {
    @Test func marksAndDefaults() {
        var s = ClickSettings()
        let l = clickMark(for: .left, settings: s)!, r = clickMark(for: .right, settings: s)!
        #expect(l.inner == s.leftInner && l.outer == s.leftOuter, "left uses left colors")
        #expect(r.inner == s.rightInner && r.outer == s.rightOuter, "right uses right colors")
        #expect(ClickSettings().diameter == 16 && l.diameter == 16, "default mark is 16 pt")
        #expect(l.seconds == 0.15, "default duration 0.15 s")
        s.visualFeedback = false
        #expect(clickMark(for: .left, settings: s) == nil, "visual off gives no mark")
        s = ClickSettings()
        s.diameter = 30
        #expect(clickMark(for: .left, settings: s)!.diameter == 30, "slider value is the diameter")
        s.diameter = 500
        #expect(clickMark(for: .left, settings: s)!.diameter == markDiameterRange.upperBound, "diameter clamps high")
        s.diameter = 0
        #expect(clickMark(for: .left, settings: s)!.diameter == markDiameterRange.lowerBound, "diameter clamps low")
        s = ClickSettings(); s.seconds = 0.4
        #expect(clickMark(for: .left, settings: s)!.seconds == 0.4, "slider value is the duration")
        s.seconds = 9
        #expect(clickMark(for: .left, settings: s)!.seconds == markSecondsRange.upperBound, "duration clamps high")
        s.seconds = 0
        #expect(clickMark(for: .left, settings: s)!.seconds == markSecondsRange.lowerBound, "duration clamps low")
        s = ClickSettings(); s.playSound = false
        #expect(effectiveVolume(s) == 0, "sound off is silent")
        s = ClickSettings(); s.soundVolume = 1.7
        #expect(effectiveVolume(s) == 1, "volume clamps high")
        s.soundVolume = -0.2
        #expect(effectiveVolume(s) == 0, "volume clamps low")
        let d = ClickSettings()
        #expect(d.leftOuter.r > d.leftOuter.g && d.rightOuter.g > d.rightOuter.r, "default edge: left red, right green")
        #expect(d.leftInner == RGBA(r: 1, g: 1, b: 1, a: 1) && d.rightInner == d.leftInner, "default center white")
        #expect(d.leftOuter.a < 1 && d.rightOuter.a < 1, "default edge translucent")
        #expect(ClickSettings().clickSound == .tac, "default sound is Tac, the app's own sound")
    }
}
