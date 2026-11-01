// ClickSettings <-> UserDefaults. Keys live here only.
import Foundation

enum Key {
    static let visual = "visualFeedback", startMessage = "hideStartMessage", sound = "playSounds", volume = "soundVolume"
    static let size = "markDiameter", duration = "markSeconds", clickSound = "clickSound", pitch = "soundPitch", brightness = "soundBrightness", ring = "soundRing"
    static let capture = "windowCapture", copyPath = "copyPath", saveFolder = "saveFolder"
    static let colors = ["leftInner", "leftOuter", "rightInner", "rightOuter"]
}

final class SettingsStore {
    private let d: UserDefaults
    init(_ d: UserDefaults = .standard) { self.d = d }


    func load() -> ClickSettings {
        var s = ClickSettings()
        if d.object(forKey: Key.visual) != nil { s.visualFeedback = d.bool(forKey: Key.visual) }
        if d.object(forKey: Key.startMessage) != nil { s.hideStartMessage = d.bool(forKey: Key.startMessage) }
        if d.object(forKey: Key.capture) != nil { s.windowCapture = d.bool(forKey: Key.capture) }
        if d.object(forKey: Key.copyPath) != nil { s.copyPath = d.bool(forKey: Key.copyPath) }
        if let v = d.string(forKey: Key.saveFolder) { s.saveFolder = v }
        if d.object(forKey: Key.sound) != nil { s.playSound = d.bool(forKey: Key.sound) }
        if let v = d.string(forKey: Key.clickSound).flatMap(ClickSoundKind.init(rawValue:)) { s.clickSound = v }
        if d.object(forKey: Key.pitch) != nil { s.soundShape.pitch = d.double(forKey: Key.pitch) }
        if d.object(forKey: Key.brightness) != nil { s.soundShape.brightness = d.double(forKey: Key.brightness) }
        if d.object(forKey: Key.ring) != nil { s.soundShape.ring = d.double(forKey: Key.ring) }
        if d.object(forKey: Key.volume) != nil { s.soundVolume = d.double(forKey: Key.volume) }
        if d.object(forKey: Key.size) != nil { s.diameter = d.double(forKey: Key.size) }
        if d.object(forKey: Key.duration) != nil { s.seconds = d.double(forKey: Key.duration) }
        let paths: [WritableKeyPath<ClickSettings, RGBA>] = [\.leftInner, \.leftOuter, \.rightInner, \.rightOuter]
        for (k, p) in zip(Key.colors, paths) {
            if let a = d.array(forKey: k) as? [Double], a.count == 4 { s[keyPath: p] = RGBA(r: a[0], g: a[1], b: a[2], a: a[3]) }
        }
        return s
    }

    func save(_ s: ClickSettings) {
        d.set(s.visualFeedback, forKey: Key.visual)
        d.set(s.hideStartMessage, forKey: Key.startMessage)
        d.set(s.windowCapture, forKey: Key.capture)
        d.set(s.copyPath, forKey: Key.copyPath)
        d.set(s.saveFolder, forKey: Key.saveFolder)
        d.set(s.playSound, forKey: Key.sound)
        d.set(s.soundVolume, forKey: Key.volume)
        d.set(s.clickSound.rawValue, forKey: Key.clickSound)
        d.set(s.soundShape.pitch, forKey: Key.pitch)
        d.set(s.soundShape.brightness, forKey: Key.brightness)
        d.set(s.soundShape.ring, forKey: Key.ring)
        d.set(s.diameter, forKey: Key.size)
        d.set(s.seconds, forKey: Key.duration)
        for (k, c) in zip(Key.colors, [s.leftInner, s.leftOuter, s.rightInner, s.rightOuter]) { d.set([c.r, c.g, c.b, c.a], forKey: k) }
    }

    func reset() { (Key.colors + [Key.visual, Key.startMessage, Key.capture, Key.copyPath, Key.saveFolder, Key.sound, Key.volume, Key.size, Key.duration, Key.clickSound, Key.pitch, Key.brightness, Key.ring]).forEach { d.removeObject(forKey: $0) } }
}
