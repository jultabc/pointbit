// Built-in click sounds, synthesized in code. Pure: same kind gives the same samples.
import Foundation

enum ClickSoundKind: String, CaseIterable {
    case tac, mouse, mouseSoft, mousePress, typewriter, tink
    var title: String {
        switch self {
        case .tac: return "TACS"   // the app's own sound
        case .mouse: return "Mouse click"
        case .mouseSoft: return "Mouse click (soft)"
        case .mousePress: return "Mouse press only"
        case .typewriter: return "Typewriter (short)"
        case .tink: return "Tink (macOS)"
        }
    }
    /// Pitch · brightness · ring sliders apply. Not to TACS (fixed) or system sounds.
    var adjustable: Bool { self != .tac && systemName == nil }
    /// nil = a macOS system sound played by name, not synthesized.
    var systemName: String? { self == .tink ? "Tink" : nil }
}

let soundSampleRate = 44_100

/// User adjustments for the synthesized sounds (Preferences sliders). All are multipliers; 1 = as designed.
struct SoundShape: Equatable {
    var pitch = 1.0        // every frequency × pitch
    var brightness = 1.0   // low-pass coefficient × brightness (capped at 1 = no filter)
    var ring = 1.0         // every decay time × ring
    static let pitchRange: ClosedRange<Double> = 0.5...1.5
    static let brightnessRange: ClosedRange<Double> = 0.25...1.75
    static let ringRange: ClosedRange<Double> = 0.3...2.0
    /// Values clamped to their slider ranges.
    var clamped: SoundShape {
        func c(_ v: Double, _ r: ClosedRange<Double>) -> Double { min(r.upperBound, max(r.lowerBound, v)) }
        return SoundShape(pitch: c(pitch, Self.pitchRange), brightness: c(brightness, Self.brightnessRange), ring: c(ring, Self.ringRange))
    }
}

/// Samples in -1...1 for a synthesized kind; empty for a system sound.
/// A mouse click = a short press transient, then a quieter release transient 75 ms later.
/// Each transient = decaying noise + a decaying tone (the switch "tick") + a faint low thump (the shell).
/// Typewriter = one strike: the same transient with extra metallic overtones (low-passed, short ring), then a small rattle 12 ms later.
func clickSamples(_ kind: ClickSoundKind, shape: SoundShape = SoundShape()) -> [Float] {
    let sh = kind.adjustable ? shape.clamped : SoundShape()
    struct Hit { var at: Double; var gain: Double; var tone: Double }
    let hits: [Hit], decay: Double, lowpass: Double, length: Double
    var metal: [Double] = []   // extra inharmonic overtones (Hz) for a metallic strike
    var thumpHz = 180.0, thumpDecay = 0.008   // the low thump of the shell
    switch kind {
    case .mouse: hits = [Hit(at: 0, gain: 1, tone: 3200), Hit(at: 0.075, gain: 0.55, tone: 3800)]; decay = 0.0025; lowpass = 1; length = 0.12
    case .mouseSoft: hits = [Hit(at: 0, gain: 0.8, tone: 1800), Hit(at: 0.08, gain: 0.35, tone: 2200)]; decay = 0.004; lowpass = 0.25; length = 0.13
    case .mousePress: hits = [Hit(at: 0, gain: 1, tone: 3200)]; decay = 0.0025; lowpass = 1; length = 0.05
    // Tac: the typewriter values below at pitch 1.01, brightness 0.66, ring 0.82, fixed (sliders do not apply).
    case .tac: hits = [Hit(at: 0, gain: 1, tone: 950 * 1.01), Hit(at: 0.012, gain: 0.2, tone: 1700 * 1.01)]
        decay = 0.003 * 0.82; lowpass = 0.25 * 0.66; length = 0.05
        metal = [1650 * 1.01, 2350 * 1.01]; thumpHz = 180 * 1.01; thumpDecay = 0.008 * 0.82
    case .typewriter: hits = [Hit(at: 0, gain: 1, tone: 950), Hit(at: 0.012, gain: 0.2, tone: 1700)]; decay = 0.003; lowpass = 0.25; length = 0.05
        metal = [1650, 2350]
    case .tink: return []
    }
    let n = Int(length * max(1, sh.ring) * Double(soundSampleRate))
    let d = decay * sh.ring, thump = thumpDecay * sh.ring, lp = min(1, lowpass * sh.brightness)
    var seed: UInt32 = 0x2012_0042          // fixed seed: deterministic noise
    func noise() -> Double { seed = seed &* 1_664_525 &+ 1_013_904_223; return Double(seed >> 8) / Double(1 << 23) - 1 }
    var out = [Double](repeating: 0, count: n)
    for i in 0..<n {
        let t = Double(i) / Double(soundSampleRate)
        let r = noise()
        var x = 0.0
        for h in hits where t >= h.at {
            let u = t - h.at
            x += h.gain * exp(-u / d) * (0.6 * r + 0.4 * sin(2 * .pi * h.tone * sh.pitch * u))
            for f in metal { x += h.gain * 0.25 * exp(-u / (d * 1.5)) * sin(2 * .pi * f * sh.pitch * u) }
            x += h.gain * 0.25 * exp(-u / thump) * sin(2 * .pi * thumpHz * sh.pitch * u)
        }
        out[i] = x
    }
    for i in 1..<n { out[i] = out[i - 1] + lp * (out[i] - out[i - 1]) }   // one-pole low-pass (1 = off)
    let fade = Int(0.005 * Double(soundSampleRate))
    for k in 0..<fade { out[n - 1 - k] *= Double(k) / Double(fade) }          // last 5 ms to silence
    let peak = out.map(abs).max() ?? 1
    return out.map { Float($0 / peak * 0.9) }
}

/// 16-bit mono PCM WAV file bytes.
func wavData(_ samples: [Float], rate: Int = soundSampleRate) -> Data {
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    let bytes = UInt32(samples.count * 2)
    d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
    d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(bytes)
    for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))) }
    return d
}
