// Synthesized click sounds: length, level, silence at the end, shape sliders, TACS.
import Testing
@testable import PointbitKit

struct ClickSoundsTests {
    @Test func sounds() {
        func energy(_ s: [Float], from a: Double, to b: Double) -> Float {
            let i = Int(a * Double(soundSampleRate)), j = min(s.count, Int(b * Double(soundSampleRate)))
            return i < j ? s[i..<j].map { $0 * $0 }.reduce(0, +) : 0
        }
        for k in ClickSoundKind.allCases where k.systemName == nil {
            let s = clickSamples(k)
            #expect(!s.isEmpty && Double(s.count) / Double(soundSampleRate) < 0.2, "\(k): short sound (< 0.2 s)")
            let peak = s.map(abs).max() ?? 0
            #expect(peak <= 0.9001 && peak >= 0.85, "\(k): peak normalized to 0.9 (no clipping)")
            #expect(abs(s.last ?? 1) < 0.001, "\(k): ends in silence")
            #expect(s == clickSamples(k), "\(k): same samples every time")
            let w = wavData(s)
            #expect(w.count == 44 + 2 * s.count && String(decoding: w[0..<4], as: UTF8.self) == "RIFF"
                  && String(decoding: w[8..<12], as: UTF8.self) == "WAVE", "\(k): WAV header and size")
        }
        let m = clickSamples(.mouse), p = clickSamples(.mousePress)
        #expect(energy(m, from: 0.07, to: 0.09) > 20 * energy(m, from: 0.05, to: 0.07), "mouse: release click at 75 ms")
        #expect(p.count < m.count && energy(p, from: 0.03, to: 0.05) < 0.01, "press only: no release click")
        let tw = clickSamples(.typewriter)
        #expect(Double(tw.count) / Double(soundSampleRate) <= 0.08, "typewriter: short (<= 80 ms)")
        // Less treble than the mouse click: share of energy in sample-to-sample differences (a high-frequency proxy).
        func hf(_ s: [Float]) -> Float { zip(s.dropFirst(), s).map { ($0 - $1) * ($0 - $1) }.reduce(0, +) / s.map { $0 * $0 }.reduce(0, +) }
        #expect(hf(tw) < hf(m) / 2, "typewriter: less treble than the mouse click")
        #expect(energy(tw, from: 0.02, to: 0.05) < 0.02 * energy(tw, from: 0, to: 0.02), "typewriter: little ring after 20 ms (< 2% of the strike)")
        // Sliders: pitch, brightness, ring.
        let tw1 = clickSamples(.typewriter, shape: SoundShape(pitch: 0.6))
        #expect(hf(tw1) < hf(tw), "pitch lower: less high-frequency energy")
        let tw2 = clickSamples(.typewriter, shape: SoundShape(brightness: 0.3))
        #expect(hf(tw2) < hf(tw), "brightness lower: less high-frequency energy")
        let late = { (s: [Float]) in energy(s, from: 0.01, to: 0.05) / energy(s, from: 0, to: 0.01) }
        #expect(late(clickSamples(.typewriter, shape: SoundShape(ring: 0.4))) < late(tw)
              && late(clickSamples(.typewriter, shape: SoundShape(ring: 1.8))) > late(tw), "ring: shorter / longer tail")
        #expect(SoundShape(pitch: 9, brightness: -1, ring: 0).clamped == SoundShape(pitch: 1.5, brightness: 0.25, ring: 0.3), "slider values clamp to their ranges")
        #expect(clickSamples(.mouse, shape: SoundShape()) == clickSamples(.mouse), "shape 1.0 = sound as designed")
        // TACS = typewriter at pitch 1.01, brightness 0.66, ring 0.82.
        let dic = clickSamples(.tac), tuned = clickSamples(.typewriter, shape: SoundShape(pitch: 1.01, brightness: 0.66, ring: 0.82))
        #expect(dic.count == tuned.count && zip(dic, tuned).allSatisfy { abs($0 - $1) < 0.001 }, "TACS = typewriter at 1.01 / 0.66 / 0.82")
        #expect(clickSamples(.tac, shape: SoundShape(pitch: 0.5, brightness: 1.7, ring: 2)) == dic && !ClickSoundKind.tac.adjustable,
              "TACS ignores the sliders")
        #expect(ClickSoundKind.typewriter.adjustable && !ClickSoundKind.tink.adjustable, "typewriter adjustable, Tink not")
        #expect(clickSamples(.tink).isEmpty && ClickSoundKind.tink.systemName == "Tink", "Tink is the macOS system sound")
    }
}
