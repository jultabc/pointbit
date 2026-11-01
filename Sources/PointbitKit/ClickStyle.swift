// Pure click-mark calculation. No AppKit state, no clock: the same input gives the same mark.
import Foundation

/// App name shown in the menu, About, and Preferences. Info.plist CFBundleName must match (build.sh checks).
public let appName = "pointbit"

enum ClickButton: String, CaseIterable { case left, right }

/// Mark diameter range in points (settings slider).
let markDiameterRange: ClosedRange<Double> = 8...64
/// Mark duration range in seconds (settings slider, Short–Long).
let markSecondsRange: ClosedRange<Double> = 0.05...1.0

struct RGBA: Equatable { var r, g, b, a: Double }

struct ClickSettings: Equatable {
    var visualFeedback = true
    var hideStartMessage = false    // false: first start, the settings window opens once and this turns true
    var windowCapture = false       // ⌘ ⌘ C captures the window under the pointer
    var copyPath = true             // a finished capture or recording also puts its file path on the clipboard
    var saveFolder = ""             // folder for pictures and recordings; empty = the Desktop
    var playSound = true
    var soundVolume = 0.35          // 0...1
    var clickSound = ClickSoundKind.tac   // built-in click sound
    var soundShape = SoundShape()           // pitch · brightness · ring of the built-in sounds
    var diameter = 16.0             // points, slider within markDiameterRange
    var seconds = 0.15              // slider within markSecondsRange
    var leftInner = RGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    var leftOuter = RGBA(r: 0.80, g: 0.10, b: 0.10, a: 0.65)
    var rightInner = RGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    var rightOuter = RGBA(r: 0.10, g: 0.60, b: 0.10, a: 0.65)
}

struct ClickMark: Equatable {
    var diameter: Double   // points
    var seconds: Double
    var inner: RGBA
    var outer: RGBA
}

/// Returns nil when visual feedback is off.
/// A round mark at the click point, a radial gradient from the inner color (center) to the outer color (edge).
/// Shown at full size for the duration and then removed. It does not grow or fade.
func clickMark(for button: ClickButton, settings s: ClickSettings) -> ClickMark? {
    guard s.visualFeedback else { return nil }
    let d = min(markDiameterRange.upperBound, max(markDiameterRange.lowerBound, s.diameter))
    let secs = min(markSecondsRange.upperBound, max(markSecondsRange.lowerBound, s.seconds))
    let (inner, outer) = button == .left ? (s.leftInner, s.leftOuter) : (s.rightInner, s.rightOuter)
    return ClickMark(diameter: d, seconds: secs, inner: inner, outer: outer)
}

/// Sound volume actually played: 0 when sound is off, clamped to 0...1 otherwise.
func effectiveVolume(_ s: ClickSettings) -> Float {
    s.playSound ? Float(min(1, max(0, s.soundVolume))) : 0
}
