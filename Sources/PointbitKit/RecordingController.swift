// ⌘ ⌘ T / ⌘ ⌘ A: starts or stops recording the window / the whole screen under the pointer.
// The video goes to the save folder (SaveFolder) as "TACS-<date>-<time>.mov". The order of starts and stops is RecordingLifecycle.
import AppKit

@MainActor
final class RecordingController {
    private let recorder = ScreenRecorder()
    private var life = RecordingLifecycle()
    private var whenIdle: [() -> Void] = []   // stop() callers waiting for the file to be finished
    /// Called on the main thread when recording starts (true) or ends (false).
    var onRecording: (Bool) -> Void = { _ in }
    /// Put the finished file's path on the clipboard (Preferences → Capture and Record).
    var copyPath = true
    /// Folder chosen in Preferences; empty or missing = the Desktop (SaveFolder).
    var saveFolder = ""

    /// Starting, recording or finishing a file.
    var isActive: Bool { life.isActive }

    /// Starts recording (window or whole screen under the pointer), or stops the recording.
    func toggle(window: Bool) {
        if life.state == .idle {
            guard let job = Self.job(window: window, folder: saveFolder) else { NSSound.beep(); return }
            _ = life.toggle()
            Task { @MainActor in
                let ok = (try? await recorder.start(area: job.area, screen: job.screen, url: job.url)) != nil
                if !ok { NSSound.beep() }
                if ok { onRecording(true) }
                if life.started(ok: ok) == .stop { finish() } else if !ok { idle() }
            }
        } else if life.toggle() == .stop {
            finish()
        }
    }

    /// Stops a recording (also one still starting) and finishes the file; `done` runs on the main thread
    /// once nothing is recording.
    func stop(done: @escaping () -> Void = {}) {
        guard life.isActive else { done(); return }
        whenIdle.append(done)
        if life.requestStop() == .stop { finish() }
    }

    private func finish() {
        Task { @MainActor in
            let url = await recorder.stop()
            onRecording(false)
            if let url { if copyPath { CaptureClipboard.put(file: url) } } else { NSSound.beep() }
            life.stopped()
            idle()
        }
    }

    private func idle() {
        let waiting = whenIdle; whenIdle = []
        waiting.forEach { $0() }
    }

    /// What to record: area, its screen and a new file in the save folder. nil when nothing is under the pointer or
    /// Screen Recording is not allowed (the settings page opens).
    private static func job(window: Bool, folder saveFolder: String) -> (area: CGRect, screen: NSScreen, url: URL)? {
        guard CapturePermissions.screenAllowed else { CapturePermissions.openScreenRecordingSettings(); return nil }
        let point = NSEvent.mouseLocation
        let area: CGRect
        if window {
            guard let (_, frame) = WindowShot.window(at: point) else { return nil }
            area = frame
        } else {
            guard let s = WindowShot.screen(at: point) else { return nil }
            area = s.frame
        }
        let center = NSPoint(x: area.midX, y: area.midY)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) ?? WindowShot.screen(at: point)
        else { return nil }
        let folder = SaveFolder.resolve(saveFolder)
        let url = folder.appendingPathComponent(WindowShot.fileName(at: Date(), ext: "mov") {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        })
        return (area, screen, url)
    }
}
