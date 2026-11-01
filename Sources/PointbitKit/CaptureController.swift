// ⌘ ⌘ C on / off and its permissions: asks for Accessibility, then Screen Recording, shows ✓ / ✗ in
// Preferences (PrefsModel) and starts the key taps (CaptureKeys) when allowed; WindowShot takes the picture.
import AppKit

@MainActor
final class CaptureController {
    let keyTaps = CaptureKeys()
    private let shot = WindowShot()
    let recording = RecordingController()
    private unowned let model: PrefsModel
    private let overlay: ClickOverlay
    private let showPrefs: () -> Void
    private let prefsVisible: () -> Bool
    private var retry: Timer?     // permission check, every second until everything is in place
    private var asked = false
    private var gate = TapGate()

    init(model: PrefsModel, overlay: ClickOverlay, prefsVisible: @escaping () -> Bool, showPrefs: @escaping () -> Void) {
        self.model = model; self.overlay = overlay; self.prefsVisible = prefsVisible; self.showPrefs = showPrefs
        keyTaps.onCapture = { [weak self] key in
            guard let self else { return }
            switch key {
            case .window: self.shot.captureWindowUnderPointer()
            case .screen: self.shot.captureScreenUnderPointer()
            case .recordWindow: self.recording.toggle(window: true)
            case .recordScreen: self.recording.toggle(window: false)
            }
        }
        shot.onCaptured = { [weak self] r in self?.captured(frame: r) }
        // No automatic restart (TapGate). A recording would have no key left to stop it: stop it too.
        keyTaps.onLostPermission = { [weak self] in self?.gate.lost(); self?.recording.stop(); self?.refresh() }
    }

    /// Starts or stops ⌘ ⌘ C. When turned on: asks for both permissions once, then checks them every second
    /// (the Preferences ✓ / ✗ lines) and starts the key tap as soon as Accessibility is granted.
    /// The check stops once both are granted and the tap runs; opening Preferences checks again.
    func apply(_ s: ClickSettings) {
        shot.copyPath = s.copyPath; recording.copyPath = s.copyPath
        shot.saveFolder = s.saveFolder; recording.saveFolder = s.saveFolder
        guard s.windowCapture else {
            retry?.invalidate(); retry = nil; asked = false; gate.reset()
            keyTaps.stop(); recording.stop(); model.keysAllowed = true; model.screenAllowed = true
            return
        }
        if !asked {   // other settings changes also call this: ask only when the feature is turned on
            asked = true
            // One permission at a time: Accessibility first; Screen Recording follows once Accessibility is on.
            if CapturePermissions.trusted(prompt: true), !CapturePermissions.screenAllowed { askScreen() }
        }
        refresh()
    }

    func refresh() {
        let keys = CapturePermissions.trusted(prompt: false), screen = CapturePermissions.screenAllowed
        let hadKeys = model.keysAllowed, hadScreen = model.screenAllowed
        if hadKeys != keys { model.keysAllowed = keys }
        if hadScreen != screen { model.screenAllowed = screen }
        if keys && !hadKeys && !screen { askScreen() }   // Accessibility was just granted: next step
        if keys && screen && (!hadKeys || !hadScreen), prefsVisible() {
            DispatchQueue.main.async { self.showPrefs() }   // both granted just now: Preferences back in front
        }
        if !keyTaps.isRunning && gate.mayStart(trusted: keys) { keyTaps.start(prompt: false) }
        // Accessibility granted but macOS refused the listen-only tap: Input Monitoring is also needed.
        let listenMissing = keys && !keyTaps.isRunning && !gate.blocked
        if listenMissing && !model.listenMissing { CapturePermissions.requestListen() }
        if model.listenMissing != listenMissing { model.listenMissing = listenMissing }
        let stopped = gate.blocked
        if model.captureStopped != stopped { model.captureStopped = stopped }
        if keys && screen && keyTaps.isRunning && !listenMissing {
            retry?.invalidate(); retry = nil
        } else if retry == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }   // main run loop
            RunLoop.main.add(t, forMode: .common)
            retry = t
        }
    }

    /// Screen Recording: the system prompt (first time) and the settings page.
    private func askScreen() {
        CapturePermissions.requestScreen()
        CapturePermissions.openScreenRecordingSettings()
    }

    /// Feedback after a capture, like a macOS screenshot: a white flash over the window and the shutter sound.
    /// Both play even when Visual Effect or Audio is off.
    private func captured(frame: NSRect) {
        overlay.flash(frame)
        NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
                byReference: true)?.play()
    }
}
