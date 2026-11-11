// ⌘ ⌘ C sequence timing.
import Carbon.HIToolbox
import Foundation
import Testing
@testable import PointbitKit

struct CaptureSequenceTests {
    private func run(_ inputs: [KeyInput]) -> [Bool] {
        actions(inputs).map { $0 == .capture(.window) }
    }
    private func actions(_ inputs: [KeyInput]) -> [KeyAction] {
        var s = CaptureSequence()
        return inputs.map { s.feed($0) }
    }
    private let c = CaptureKey.window.rawValue

    @Test func tapTapC() {
        #expect(run([.commandDown(0), .commandUp(0.1), .commandDown(0.2), .commandUp(0.3), .key(code: c, modifiers: false, at: 0.5)]).last == true)
    }
    @Test func slowSecondTap() {
        #expect(run([.commandDown(0), .commandUp(0.1), .commandDown(0.6), .commandUp(0.7), .key(code: c, modifiers: false, at: 0.8)]).last == false)
    }
    @Test func longPress() {
        #expect(run([.commandDown(0), .commandUp(0.5), .commandDown(0.6), .commandUp(0.7), .key(code: c, modifiers: false, at: 0.8)]).last == false)
    }
    @Test func cTooLate() {
        #expect(run([.commandDown(0), .commandUp(0.1), .commandDown(0.2), .commandUp(0.3), .key(code: c, modifiers: false, at: 1.5)]).last == false)
    }
    @Test func commandC_isCopyNotCapture() {
        // ⌘ held while C is pressed = ⌘C (copy)
        #expect(run([.commandDown(0), .commandUp(0.1), .commandDown(0.2), .key(code: c, modifiers: true, at: 0.25)]).last == false)
    }
    @Test func otherKeyCancels() {
        #expect(run([.commandDown(0), .commandUp(0.1), .commandDown(0.2), .commandUp(0.3), .key(code: 0, modifiers: false, at: 0.4),
                     .key(code: c, modifiers: false, at: 0.5)]).last == false)
    }
    @Test func shiftCancels() {
        #expect(run([.commandDown(0), .commandUp(0.1), .otherModifier(0.15), .commandDown(0.2), .commandUp(0.3),
                     .key(code: c, modifiers: false, at: 0.4)]).last == false)
    }
    @Test func oneTapOnly() {
        #expect(run([.commandDown(0), .commandUp(0.1), .key(code: c, modifiers: false, at: 0.2)]).last == false)
    }
    @Test func plainCWithoutTaps() {
        #expect(run([.key(code: c, modifiers: false, at: 0)]) == [false])
    }
    @Test func threeTapsThenC_usesLastTwo() {
        #expect(run([.commandDown(0), .commandUp(0.1), .commandDown(0.2), .commandUp(0.3), .commandDown(0.4), .commandUp(0.5),
                     .commandDown(0.6), .commandUp(0.7), .key(code: c, modifiers: false, at: 0.8)]).last == true)
    }

    @Test func heldCRepeatsAndReleaseAreSwallowedThenTypingPasses() {
        let a = actions([.commandDown(0), .commandUp(0.1), .commandDown(0.2), .commandUp(0.3),
                         .key(code: c, modifiers: false, at: 0.4),      // completes
                         .key(code: c, modifiers: false, at: 0.9, repeat: true),    // auto-repeat
                         .key(code: c, modifiers: false, at: 0.95, repeat: true),   // auto-repeat
                         .keyUp(code: c, at: 1.0),                      // release
                         .key(code: c, modifiers: false, at: 1.5),      // a new, normal C
                         .keyUp(code: c, at: 1.6)])
        #expect(a == [.pass, .pass, .pass, .pass, .capture(.window), .swallow, .swallow, .swallow, .pass, .pass])
    }
    @Test func otherKeyUpsPass() {
        #expect(actions([.keyUp(code: 0, at: 0), .keyUp(code: c, at: 0.1)]) == [.pass, .pass])
    }

    @Test func missedReleaseDoesNotEatTheNextC() {
        // capture, the C release never arrives, a later (non-repeat) C and ⌘C pass
        let a = actions([.commandDown(0), .commandUp(0.1), .commandDown(0.2), .commandUp(0.3),
                         .key(code: c, modifiers: false, at: 0.4),
                         .key(code: c, modifiers: false, at: 50),
                         .key(code: c, modifiers: true, at: 51)])
        #expect(a == [.pass, .pass, .pass, .pass, .capture(.window), .pass, .pass])
    }

    @Test func fileNamesInTheSameSecondDiffer() {
        let d = Date(timeIntervalSince1970: 0)
        var taken: Set<String> = []
        let a = WindowShot.fileName(at: d) { taken.contains($0) }; taken.insert(a)
        let b = WindowShot.fileName(at: d) { taken.contains($0) }; taken.insert(b)
        let c3 = WindowShot.fileName(at: d) { taken.contains($0) }
        #expect(a != b && b != c3 && a != c3)
        #expect(b.hasSuffix("-2.png") && c3.hasSuffix("-3.png"))
        #expect(!a.contains(" "), "no spaces: a pasted path works in a shell")
    }

    @Test func tapIsNotRestartedAfterTheSystemStopsIt() {
        var g = TapGate()
        let s1 = g.mayStart(trusted: true); #expect(s1)            // first start
        g.lost()                                      // macOS turned the tap off, permission still reads granted
        let s2 = g.mayStart(trusted: true); #expect(!s2)           // no automatic restart
        let s3 = g.mayStart(trusted: true); #expect(!s3)
        let s4 = g.mayStart(trusted: false); #expect(!s4)          // permission gone
        let s5 = g.mayStart(trusted: true); #expect(s5)            // granted again: a new grant may start it
    }
    @Test func turningTheFeatureOffAndOnAllowsAStart() {
        var g = TapGate()
        g.lost()
        let s6 = g.mayStart(trusted: true); #expect(!s6)
        g.reset()
        let s7 = g.mayStart(trusted: true); #expect(s7)
    }

    @Test func holdingTapOnlyBetweenSecondTapAndRelease() {
        var s = CaptureSequence()
        var wants: [Bool] = []
        for i in [KeyInput.commandDown(0), .commandUp(0.1), .commandDown(0.2), .commandUp(0.3),
                  .key(code: c, modifiers: false, at: 0.4), .keyUp(code: c, at: 0.5)] {
            _ = s.feed(i); wants.append(s.wantsSwallowTap)
        }
        #expect(wants == [false, false, true, true, true, false])   // from the second ⌘ press, before any C
        _ = s.feed(.commandDown(1)); _ = s.feed(.commandUp(1.1)); _ = s.feed(.commandDown(1.2)); _ = s.feed(.commandUp(1.3))
        #expect(s.wantsSwallowTap)
        s.cancel()
        #expect(!s.wantsSwallowTap)
    }

    @Test func eachActionKeyCompletesTheSequence() {
        for k in CaptureKey.onThisMac {
            var s = CaptureSequence()
            let a = [KeyInput.commandDown(0), .commandUp(0.1), .commandDown(0.2), .commandUp(0.3),
                     .key(code: k.rawValue, modifiers: false, at: 0.4)].map { s.feed($0) }
            #expect(a.last == .capture(k))
            #expect(s.feed(.keyUp(code: k.rawValue, at: 0.5)) == .swallow)
        }
    }
    @Test func aKeyThisMacCannotDoGoesOn() {
        // On macOS 13 (no background removal) R after ⌘ ⌘ must reach the front app.
        var s = CaptureSequence(); s.keys = Set(CaptureKey.allCases).subtracting([.cutout])
        let a = [KeyInput.commandDown(0), .commandUp(0.1), .commandDown(0.2), .commandUp(0.3),
                 .key(code: CaptureKey.cutout.rawValue, modifiers: false, at: 0.4)].map { s.feed($0) }
        #expect(a.last == .pass)
        #expect(!s.wantsSwallowTap)
        #expect(CaptureKey.onThisMac.contains(.cutout) == Cutout.isAvailable)
    }

    @Test func otherKeyAfterTapsPassesAndCancels() {
        var s = CaptureSequence()
        let a = [KeyInput.commandDown(0), .commandUp(0.1), .commandDown(0.2), .commandUp(0.3),
                 .key(code: 14 /* E */, modifiers: false, at: 0.4)].map { s.feed($0) }
        #expect(a.last == .pass)
        #expect(!s.wantsSwallowTap)
    }

    @Test func actionKeyCodesAreTheMacKeys() {
        #expect(CaptureKey.recordWindow.rawValue == UInt16(kVK_ANSI_T))
        #expect(CaptureKey.recordArea.rawValue == UInt16(kVK_ANSI_D))
        #expect([CaptureKey.pen, .oval, .box].map(\.rawValue) == [kVK_ANSI_L, kVK_ANSI_O, kVK_ANSI_B].map { UInt16($0) })
        #expect(CaptureKey.zoom.rawValue == UInt16(kVK_ANSI_M))
        #expect(CaptureKey.recordScreen.rawValue == UInt16(kVK_ANSI_A))
        #expect(CaptureKey.window.rawValue == UInt16(kVK_ANSI_C))
        #expect(CaptureKey.screen.rawValue == UInt16(kVK_ANSI_S))
        #expect(CaptureKey.undoMark.rawValue == UInt16(kVK_ANSI_Z))
        #expect(CaptureKey.clearMarks.rawValue == UInt16(kVK_ANSI_X))
        #expect(CaptureKey.cutout.rawValue == UInt16(kVK_ANSI_R))
        #expect([CaptureKey.color1, .color2, .color3].map(\.rawValue) == [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3].map { UInt16($0) })
    }
}
