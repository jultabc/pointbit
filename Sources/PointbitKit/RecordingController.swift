// ⌘ ⌘ T / ⌘ ⌘ A: starts or stops recording the window / the whole screen under the pointer.
// ⌘ ⌘ D: first a box the size of that window (AreaPicker); Return starts recording the box, ⌘ ⌘ D stops.
// While ⌘ ⌘ T or ⌘ ⌘ D records, the rest of the screen is dimmed (RecordingFrame).
// The video goes to the save folder (SaveFolder) as "TACS-<date>-<time>.mov". The order of starts and stops is RecordingLifecycle.
// While recording: the highlighter (MarkerTap). With Record my voice: the microphone, and afterwards the .txt (Transcript).
import AppKit
import os

private let log = Logger(subsystem: "si.codegg.pointbit", category: "recorder")

@MainActor
final class RecordingController {
    private let recorder = ScreenRecorder()
    /// ⌥ + drag highlighter; on only while recording.
    let marker = MarkerTap()
    private let frame = RecordingFrame()
    private let picker = AreaPicker()
    private let zoomer = Zoomer()
    private var life = RecordingLifecycle()
    private var recovered = false   // recoverLeftovers ran
    private var whenIdle: [() -> Void] = []   // stop() callers waiting for the file to be finished
    /// Called on the main thread when recording starts (true) or ends (false).
    var onRecording: (Bool) -> Void = { _ in }
    /// Put the finished file and its path on the clipboard (Preferences → Capture → Copy to clipboard when it ends).
    var copyPath = true
    /// Folder chosen in Preferences; empty or missing = the Desktop (SaveFolder).
    var saveFolder = ""
    /// Preferences → Record my voice, and the recognition language (empty = the Mac's language).
    var recordVoice = false
    var voiceLanguage = ""
    /// Preferences → Recording size: the screen's full pixels, or point size (smaller files).
    var fullSize = false
    /// ⌘ ⌘ T: the recorded window, its frame when the recorded rect last moved, and the timer that looks for moves.
    private var watched: (id: CGWindowID, frame: CGRect)?
    private var watch: Timer?
    private var catchingUp = false   // a move of the recorded rect is in progress
    private var settling: (frame: CGRect, since: Date)?   // the window's frame while it moves, and since when it is there
    /// The recorded rect moves once the window has stood still this long: one jump in the video, not a jump every
    /// few frames, and no capture changes while the window is dragged (they cost a lot of CPU on a 2017 MacBook Pro).
    static let settle: TimeInterval = 0.3

    /// Starting, recording or finishing a file.
    var isActive: Bool { life.isActive }

    /// Starts recording (window or whole screen under the pointer), or stops the recording.
    func toggle(window: Bool) {
        if picker.isOpen { return }
        if life.state == .idle {
            guard let job = Self.job(window: window, folder: saveFolder) else { NSSound.beep(); return }
            begin(job, outlined: window)
        } else if life.toggle() == .stop {
            finish()
        }
    }

    /// ⌘ ⌘ D: opens the box, starts recording it (when the box is open), or stops the recording.
    func toggleArea() {
        if picker.isOpen { picker.confirm(); return }
        guard life.state == .idle else { if life.toggle() == .stop { finish() }; return }
        guard let job = Self.job(window: true, folder: saveFolder) ?? Self.job(window: false, folder: saveFolder)
        else { NSSound.beep(); return }
        // No window under the pointer: the middle half of the screen.
        let start = job.window != nil ? job.area : job.area.insetBy(dx: job.area.width / 4, dy: job.area.height / 4)
        picker.open(on: job.screen, rect: start) { [weak self] rect in
            guard let self, let rect, self.life.state == .idle else { return }
            self.begin((rect, job.screen, job.url, nil), outlined: true)
        }
    }

    private func begin(_ job: (area: CGRect, screen: NSScreen, url: URL, window: CGWindowID?), outlined: Bool) {
        _ = life.toggle()
        // Without the Microphone permission, or without a microphone, the video is still recorded, without sound.
        let voice = recordVoice && CapturePermissions.microphoneAllowed
        let full = fullSize
        // Shown before the start so that the capture can leave its window out. ⌘ ⌘ A: around the whole screen, so
        // the line is off its edges and nothing is dimmed; the window is there for the ⌘ ⌘ M box.
        frame.show(around: outlined ? job.area.intersection(job.screen.frame) : job.screen.frame)
        zoomer.onShown = { [weak self] in self?.frame.showZoom($0) }
        marker.onPen = { [weak self] in self?.frame.showPen($0) }
        let hidden = frame.windowID.map { [$0] } ?? []
        Task { @MainActor in
            let sound = try? await recorder.start(area: job.area, screen: job.screen, url: job.url, voice: voice, fullSize: full,
                                                  leavingOut: hidden)
            let ok = sound != nil
            if !ok { NSSound.beep(); frame.hide() }
            if ok {
                marker.start(); onRecording(true)
                if outlined, let r = recorder.recordedArea { frame.show(around: r); marker.clip(to: r) }
                if let id = job.window { follow(id, from: job.area) }
            }
            if life.started(ok: ok) == .stop { finish() } else if !ok { idle() }
        }
    }

    /// Puts recordings left as hidden parts in the save folder (the app quit or crashed while joining) back at
    /// their names. Once, the first time the feature is on, before anything records: the leftovers are listed here,
    /// at once, so a recording started afterwards is not among them. A folder chosen later is not looked at.
    func recoverLeftovers() {
        guard !recovered, !life.isActive else { return }
        recovered = true
        let leftovers = RecordingJoin.leftovers(in: SaveFolder.resolve(saveFolder))
        guard !leftovers.isEmpty else { return }
        Task {
            for url in await RecordingJoin.recover(leftovers) { log.notice("recovered \(url.lastPathComponent, privacy: .public)") }
        }
    }

    /// A picture of a screen area is about to be taken: the dimmed outside and the line step aside (RecordingFrame
    /// counts overlapping pictures). False when none is shown.
    func pictureStarts() -> Bool { frame.stepAside() }
    /// That picture is taken.
    func pictureDone() { frame.stepBack() }

    /// Stops a recording (also one still starting) and finishes the file; `done` runs on the main thread
    /// once nothing is recording.
    func stop(done: @escaping () -> Void = {}) {
        picker.cancel()   // an open ⌘ ⌘ D box closes too (feature off, permission lost)
        guard life.isActive else { done(); return }
        whenIdle.append(done)
        if life.requestStop() == .stop { finish() }
    }

    /// Looks 10 times a second; when the window moved and then stood still for `settle`, moves the recorded rect, then
    /// the highlighter strokes (as far as the rect moved) and the dimmed outside with it, so the strokes stay put in the video.
    private func follow(_ id: CGWindowID, from frame: CGRect) {
        watched = (id, frame); catchingUp = false; settling = nil
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // The top-left corner: page content stays there when a window is resized from the bottom or right.
                guard let self, !self.catchingUp, let (id, old) = self.watched, let now = WindowShot.frame(of: id) else { return }
                guard now.minX != old.minX || now.maxY != old.maxY else { self.settling = nil; return }
                // Still moving: wait until it stands still.
                guard let s = self.settling, s.frame == now else { self.settling = (now, Date()); return }
                guard Date().timeIntervalSince(s.since) >= Self.settle else { return }
                self.settling = nil
                self.catchingUp = true
                Task {
                    self.zoomer.reset()   // the zoom is of the old place; ⌘ ⌘ M again zooms the new one
                    let before = self.recorder.recordedArea
                    let moved = await self.recorder.follow(now)
                    defer { self.catchingUp = false }
                    // Stopped meanwhile; or the capture refused the move: nothing moves, the next look tries again.
                    guard self.watched?.id == id, moved, let before, let r = self.recorder.recordedArea else { return }
                    self.watched = (id, now)
                    // The lines go with the recorded rect, not the window: at a screen edge the rect stops while the
                    // window goes on, and lines moved with the window left the rect and were hidden (2017 test).
                    self.marker.move(by: CGVector(dx: r.minX - before.minX, dy: r.maxY - before.maxY))
                    self.frame.show(around: r); self.marker.clip(to: r)
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        watch = t
    }

    /// ⌘ ⌘ M: zoom the video around the pointer, or back. Only while recording.
    func toggleZoom() {
        guard life.state == .recording else { return }
        zoomer.toggle(recorder)
    }

    private func finish() {
        zoomer.reset()
        marker.stopPen()
        watch?.invalidate(); watch = nil; watched = nil
        frame.hide()
        Task { @MainActor in
            // The highlighter goes as soon as the capture stops, not after the file is joined (2017: the lines
            // stayed on the screen for a few seconds after ⌘ ⌘ D).
            let url = await recorder.stop { marker.stop(); onRecording(false) }
            if let url { if copyPath { CaptureClipboard.put(file: url) } } else { NSSound.beep() }
            let copied = NSPasteboard.general.changeCount
            life.stopped()
            idle()
            if let url, recorder.lastHasSound { transcribe(url, copied: copied) }   // not when the sound part failed
        }
    }

    /// Writes the .txt after the video is done (recognition takes a few seconds per minute of speech).
    /// With Copy to clipboard on, the clipboard then holds both files and both paths (the video, a space, the text file) —
    /// only if nothing else was copied since the video's path (`copied` = the clipboard's change count then).
    private func transcribe(_ video: URL, copied: Int) {
        let language = voiceLanguage, copy = copyPath
        Task { @MainActor in
            guard let text = await Transcript.write(for: video, language: language) else { return }
            if copy && NSPasteboard.general.changeCount == copied { CaptureClipboard.put(files: [video, text]) }
        }
    }

    private func idle() {
        let waiting = whenIdle; whenIdle = []
        waiting.forEach { $0() }
    }

    /// What to record: area, its screen and a new file in the save folder. nil when nothing is under the pointer or
    /// Screen Recording is not allowed (the settings page opens).
    private static func job(window: Bool, folder saveFolder: String) -> (area: CGRect, screen: NSScreen, url: URL, window: CGWindowID?)? {
        guard CapturePermissions.screenAllowed else { CapturePermissions.openScreenRecordingSettings(); return nil }
        let point = NSEvent.mouseLocation
        let area: CGRect, id: CGWindowID?
        if window {
            guard let (w, frame) = WindowShot.window(at: point) else { return nil }
            area = frame; id = w
        } else {
            guard let s = WindowShot.screen(at: point) else { return nil }
            area = s.frame; id = nil
        }
        let center = NSPoint(x: area.midX, y: area.midY)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) ?? WindowShot.screen(at: point)
        else { return nil }
        let folder = SaveFolder.resolve(saveFolder)
        let url = folder.appendingPathComponent(WindowShot.fileName(at: Date(), ext: "mov") {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        })
        return (area, screen, url, id)
    }
}
