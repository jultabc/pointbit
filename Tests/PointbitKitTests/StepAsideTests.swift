// Pictures taken while recording: the dimmed outside steps aside once and comes back after the last picture.
import Testing
@testable import PointbitKit

struct StepAsideTests {
    @Test func overlappingPicturesBringItBackOnlyAfterTheLast() {
        var s = StepAside()
        let aOff = s.take(), bOff = s.take()
        #expect(aOff && !bOff, "A takes it off; B finds it off")
        let aBack = s.give()
        #expect(!aBack && s.isAside, "A ends while B is still taken: it stays off")
        let bBack = s.give()
        #expect(bBack && !s.isAside, "B ends: it comes back")
    }

    @Test func anExtraEndDoesNothing() {
        var s = StepAside()
        _ = s.take()
        let first = s.give(), second = s.give()
        #expect(first && !second && s.count == 0)
    }
}
