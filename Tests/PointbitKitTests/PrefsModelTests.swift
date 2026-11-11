// Restore Defaults, start-up without onChange, and the sound preview (debounce), on a throwaway
// UserDefaults domain. The domain is an absolute path in the temporary folder, so its plist is written
// there and not under ~/Library/Preferences. The file is deleted at the end of the test.
import AppKit
import Foundation
import Testing
@testable import PointbitKit

@MainActor
struct PrefsModelTests {
    @Test func restoreAndPreview() async throws {
        let domain = FileManager.default.temporaryDirectory
            .appendingPathComponent("pointbit-test-\(ProcessInfo.processInfo.processIdentifier)").path
        let d = UserDefaults(suiteName: domain)!
        let store = SettingsStore(d)
        var changes = 0
        let m = PrefsModel(store: store) { _ in changes += 1 }
        #expect(changes == 0, "creating the model does not call onChange (the app's lazy model would re-enter)")

        // Change every setting away from its default.
        m.s.visualFeedback = false; m.s.playSound = false; m.s.soundVolume = 0.9
        m.s.diameter = 40; m.s.seconds = 0.6; m.s.hideStartMessage = true
        m.s.leftInner = RGBA(r: 0, g: 0, b: 1, a: 1); m.s.leftOuter = RGBA(r: 0, g: 0, b: 1, a: 0.3)
        m.s.rightInner = RGBA(r: 1, g: 1, b: 0, a: 1); m.s.rightOuter = RGBA(r: 1, g: 1, b: 0, a: 0.3)
        m.s.clickSound = .tink
        m.s.soundShape = SoundShape(pitch: 0.7, brightness: 0.5, ring: 0.5)
        #expect(store.load() != ClickSettings(), "changed settings are saved")

        changes = 0
        m.restoreDefaults()
        var want = ClickSettings(); want.hideStartMessage = true
        #expect(m.s == want, "window values are the defaults")
        #expect(store.load() == want, "saved values are the defaults (read back from storage)")
        #expect(m.s.hideStartMessage, "the first-start flag is kept")
        #expect(changes > 0, "running app is told (onChange)")
        for k in ["visualFeedback", "playSounds", "soundVolume", "markDiameter", "markSeconds"] {
            #expect(d.object(forKey: k) != nil, "key \(k) written after restore")
        }

        // The voice choices are kept, like the save folder.
        m.s.recordVoice = true; m.s.voiceLanguage = "ko-KR"; m.s.diameter = 40
        m.restoreDefaults()
        #expect(store.load().recordVoice && store.load().voiceLanguage == "ko-KR" && m.s.diameter == 16, "voice kept, marks reset")
        m.s.recordVoice = false; m.s.voiceLanguage = ""
        #expect(!ClickSettings().recordFullSize, "recordings are half size by default")
        m.s.recordFullSize = true
        #expect(store.load().recordFullSize, "recording size saved")
        m.s.markerSlot = 3; m.s.markerColors[1] = RGBA(r: 0, g: 1, b: 0, a: 0.5)
        #expect(store.load().markerSlot == 3 && store.load().markerColors[1].g == 1, "highlight color and choice saved")
        m.restoreDefaults()
        #expect(m.s.markerSlot == 1 && m.s.markerColors == markerDefaultColors, "highlight colors back to yellow · red · blue")
        #expect(!ClickSettings().recordVoice, "voice is off by default")

        // Restore with the start message unchecked keeps it unchecked.
        m.s.hideStartMessage = false; m.s.diameter = 50
        m.restoreDefaults()
        #expect(m.s == ClickSettings() && store.load() == ClickSettings(), "restore with start message shown = plain defaults")

        // Preview: a burst of sound changes plays once, after the last change.
        var plays = 0
        m.playSound = { plays += 1 }
        m.previewDelay = 0.1
        for p in [0.6, 0.7, 0.8, 0.9, 1.1] { m.s.soundShape.pitch = p }
        try await Task.sleep(nanoseconds: 400_000_000)   // main actor idle: the preview timer can fire
        #expect(plays == 1, "5 quick pitch changes -> 1 preview")
        m.s.diameter = 30
        try await Task.sleep(nanoseconds: 300_000_000)   // main actor idle: the preview timer can fire
        #expect(plays == 1, "a non-sound change does not play")
        m.s.soundVolume = 0.5
        try await Task.sleep(nanoseconds: 300_000_000)   // main actor idle: the preview timer can fire
        #expect(plays == 2, "a volume change plays once")
        m.s.playSound = false; m.s.soundShape.ring = 0.5
        try await Task.sleep(nanoseconds: 300_000_000)   // main actor idle: the preview timer can fire
        #expect(plays == 3, "Audio Off: a sound change still previews once")
        m.s.playSound = true; m.s.soundShape.ring = 0.6; m.s.playSound = false
        try await Task.sleep(nanoseconds: 300_000_000)   // main actor idle: the preview timer can fire
        #expect(plays == 4, "Audio turned Off inside the delay: still previews once")
        m.s.playSound = true

        d.removePersistentDomain(forName: domain)
        CFPreferencesAppSynchronize(domain as CFString)
        try? FileManager.default.removeItem(atPath: domain + ".plist")
        #expect(!FileManager.default.fileExists(atPath: domain + ".plist"), "throwaway domain file removed")
    }
}
