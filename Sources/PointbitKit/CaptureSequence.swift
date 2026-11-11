// Key sequence: tap ⌘, tap ⌘, then press one action key (T · A · C · S · R · Z · X · 1 · 2 · 3). Pure: no event tap, no clock.
import Foundation

enum KeyInput: Equatable {
    case commandDown(Double)                 // seconds, any monotonic clock
    case commandUp(Double)
    case otherModifier(Double)               // Shift, Option, Control, Fn change
    case key(code: UInt16, modifiers: Bool, at: Double, repeat: Bool = false)   // a key down; modifiers = any modifier held
    case keyUp(code: UInt16, at: Double)
}

/// The key after ⌘ ⌘, and what it does.
enum CaptureKey: UInt16, CaseIterable {
    case recordWindow = 17   // T: record the window under the pointer (start / stop)
    case recordScreen = 0    // A: record the whole screen under the pointer (start / stop)
    case recordArea = 2      // D: a box to size first (Return starts), then record it (start / stop)
    case window = 8          // C: picture of the window under the pointer
    case screen = 1          // S: picture of the whole screen under the pointer
    case undoMark = 6        // Z: while recording, erase the last highlighter stroke
    case clearMarks = 7      // X: while recording, erase all highlighter strokes
    case cutout = 15         // R: picture of the window under the pointer, background removed (macOS 14+)
    case color1 = 18         // 1 · 2 · 3: highlighter color 1 · 2 · 3 (Preferences)
    case color2 = 19
    case color3 = 20
    case pen = 37            // L · O · B: while recording, the highlighter draws a free line, an oval or a box
    case oval = 31
    case box = 11
    case zoom = 46           // M: while recording, the video zooms around the pointer (Magnify) or back

    /// The keys this Mac acts on: R only where background removal exists (macOS 14+). A key left out is not an
    /// action key here: after ⌘ ⌘ it goes on to the front app like any other letter.
    static var onThisMac: Set<CaptureKey> { Cutout.isAvailable ? Set(allCases) : Set(allCases).subtracting([.cutout]) }
}

/// What the event tap does with the input.
enum KeyAction: Equatable {
    case pass                  // goes on to the front app
    case capture(CaptureKey)   // the key that completes the sequence: act, do not pass on
    case swallow               // repeats and the release of that key: do not pass on
}

struct CaptureSequence {
    var tapMax = 0.30       // longest ⌘ press that counts as a tap
    var gapMax = 0.35       // longest pause between the two taps
    var keyWindow = 1.0     // time after the second tap to press the action key
    var keys = CaptureKey.onThisMac

    private enum State: Equatable { case idle, down1(Double), up1(Double), down2(Double), armed(Double), holding(UInt16) }
    private var state = State.idle

    /// The short-lived tap that can hold back the action key is needed from the second ⌘ press until that key's
    /// release. It starts at the second ⌘ *press*, so it is in place before a fast key can arrive.
    var wantsSwallowTap: Bool {
        switch state { case .down2, .armed, .holding: return true; default: return false }
    }
    /// Back to the start (the short-lived tap's time limit ran out).
    mutating func cancel() { state = .idle }

    mutating func feed(_ input: KeyInput) -> KeyAction {
        switch (input, state) {
        // After the action, the held key's repeats and its release stay with the app.
        case (.key(let code, _, _, true), .holding(let held)) where code == held:
            return .swallow   // auto-repeat of the held key
        case (.key, .holding):
            state = .idle     // a new key press (the release was missed): normal input again
            return .pass
        case (.keyUp(let code, _), .holding(let held)) where code == held:
            state = .idle
            return .swallow
        case (.keyUp, _):
            return .pass   // releases do not change the sequence
        case (.commandDown(let t), .up1(let u)) where t - u <= gapMax:
            state = .down2(t)
        case (.commandDown(let t), _):
            state = .down1(t)
        case (.commandUp(let t), .down1(let d)) where t - d <= tapMax:
            state = .up1(t)
        case (.commandUp(let t), .down2(let d)) where t - d <= tapMax:
            state = .armed(t)
        case (.key(let code, let mods, let t, _), .armed(let a)) where !mods && t - a <= keyWindow:
            guard let k = CaptureKey(rawValue: code), keys.contains(k) else { state = .idle; return .pass }
            state = .holding(code)
            return .capture(k)
        default:
            state = .idle
        }
        return .pass
    }
}

/// When the key tap may be (re)started. Pure.
/// After macOS turns the tap off (or Accessibility goes away), the tap is not started again on its own while
/// Accessibility still reads as granted: it waits for the permission to go away and come back, or for the
/// user to turn the feature off and on.
struct TapGate {
    private(set) var blocked = false
    /// The tap was removed (system turned it off or Accessibility is gone).
    mutating func lost() { blocked = true }
    /// The user turned the feature off.
    mutating func reset() { blocked = false }
    /// Whether to start the tap now, given the current Accessibility state.
    mutating func mayStart(trusted: Bool) -> Bool {
        if blocked && !trusted { blocked = false }   // permission gone: the next grant is a new one
        return trusted && !blocked
    }
}
