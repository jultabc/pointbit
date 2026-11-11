// ⌘ ⌘ R: picks what to cut before saving. The window under the pointer is taken once and Vision finds its subjects;
// a box then shows the subject under the pointer (every subject when the pointer is on the background) as the
// pointer moves. Return or ⌘ ⌘ R again saves that cut (WindowShot); Esc cancels. Pausing a video first helps: the
// choice is made on the picture taken at the start.
import AppKit

/// What ⌘ ⌘ R saves: a subject (nil: every subject) or a line of text.
enum CutoutChoice: Equatable {
    case subjects(Int?)
    case text(Int)
}

@available(macOS 14, *)
@MainActor
final class CutoutPicker {
    private var window: NSWindow?
    private var previous: NSRunningApplication?
    private var done: ((CutoutChoice) -> Void)?
    private var picture: URL?   // the window's picture; set from the ⌘ ⌘ R until the picker is closed
    private let preparing = RecordingFrame()   // the window outlined (the rest dimmed) while its picture is read

    var isOpen: Bool { window != nil }
    /// Takes window `id` into the file, then calls back (off the main thread) with whether it worked. screencapture;
    /// a test puts its own here.
    var takePicture: (CGWindowID, URL, @escaping @Sendable (Bool) -> Void) -> Void = { id, url, done in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(id), url.path]
        p.terminationHandler = { done($0.terminationStatus == 0) }
        do { try p.run() } catch { done(false) }
    }
    /// Taking the picture, finding the subjects, or open: other capture keys wait (CaptureController).
    var isBusy: Bool { picture != nil }
    /// The window outline that says the picture is being read is shown.
    var isPreparing: Bool { preparing.windowID != nil }

    /// Takes window `id` (at `frame`, Cocoa global), finds its subjects and opens the picker over it. `save` gets the
    /// scene and the subject chosen (nil: every subject) on Return; nothing on Esc. A beep when no subject is found.
    /// `recording`: a recording is on; the dimmed outline is not shown then (it would be in the video for the
    /// seconds of reading). The box while choosing is shown, and recorded, like the click marks.
    func open(window id: CGWindowID, frame: NSRect, recording: Bool = false,
              save: @escaping (CutoutScene, CutoutChoice, URL) -> Void) {
        guard window == nil, picture == nil else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pointbit-pick-\(UUID().uuidString).png")
        picture = url
        // Reading a big window with much text can take seconds (45 lines, 4.2 s on an M1): show that
        // ⌘ ⌘ R is working. The picture is of that window only (-l), so the outline is not in it.
        if !recording { preparing.show(around: frame) }
        takePicture(id, url) { ok in
            let scene = ok ? CutoutScene(url) : nil   // Vision takes a moment: off the main thread
            DispatchQueue.main.async {
                // A cancelled round: only its file goes; the outline may belong to the next round.
                guard self.picture == url else { try? FileManager.default.removeItem(at: url); return }
                self.preparing.hide()
                guard let scene else { self.close(); NSSound.beep(); return }
                self.show(scene, over: frame) { choice in save(scene, choice, url) }
            }
        }
    }

    /// Return or ⌘ ⌘ R while open; ⌘ ⌘ R while the subjects are still being found cancels.
    func confirm() {
        guard let v = window?.contentView as? PickView else { cancel(); return }
        guard let choice = v.choice else { NSSound.beep(); return }   // nothing under the pointer (text only, off it)
        finish(choice)
    }

    /// Esc, the feature turned off or the permission lost: closes without saving, also while still preparing.
    func cancel() {
        if window != nil { finish(nil); return }
        if let picture { try? FileManager.default.removeItem(at: picture) }   // a picture still being taken is dropped when done
        picture = nil
        preparing.hide()
    }

    private func show(_ scene: CutoutScene, over frame: NSRect, save: @escaping (CutoutChoice) -> Void) {
        previous = NSWorkspace.shared.frontmostApplication
        let w = KeyWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.level = .screenSaver
        w.acceptsMouseMovedEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]   // also over a full-screen video
        let v = PickView(frame: NSRect(origin: .zero, size: frame.size), scene: scene)
        v.onEnd = { [weak self] confirmed in confirmed ? self?.confirm() : self?.cancel() }
        w.contentView = v
        window = w
        done = save
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(v)
        v.point(at: w.mouseLocationOutsideOfEventStream)
    }

    /// A choice hands the picture to `save`, which removes it after the cut (the scene still reads it); nil cancels.
    private func finish(_ choice: CutoutChoice?) {
        guard window != nil else { return }
        let d = done
        close(keepingPicture: choice != nil)
        if let choice { d?(choice) }
    }

    private func close(keepingPicture: Bool = false) {
        window?.close(); window = nil; done = nil
        previous?.activate(); previous = nil
        if let picture, !keepingPicture { try? FileManager.default.removeItem(at: picture) }
        picture = nil
    }

    private final class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private final class PickView: NSView {
        private let scene: CutoutScene
        private(set) var choice: CutoutChoice?
        var onEnd: (Bool) -> Void = { _ in }
        private let box = RecordingFrame.line(), under = RecordingFrame.underline(), tint = CAShapeLayer()

        init(frame: NSRect, scene: CutoutScene) {
            self.scene = scene
            super.init(frame: frame)
            wantsLayer = true
            tint.fillColor = NSColor.white.withAlphaComponent(0.12).cgColor
            [tint, under, box].forEach { layer?.addSublayer($0) }
        }
        required init?(coder: NSCoder) { nil }

        override var acceptsFirstResponder: Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseMoved(with e: NSEvent) { point(at: convert(e.locationInWindow, from: nil)) }

        /// What is under `p` (view points) is shown: a line of text, a subject, or on the background every subject.
        func point(at p: CGPoint) {
            let share = Cutout.share(of: p, in: bounds)
            var e: CGRect?
            if let share, let t = scene.text(at: share) {
                choice = .text(t); e = scene.texts[t].box
            } else if scene.hasSubjects {
                let s = share.flatMap(scene.subject(at:))
                choice = .subjects(s); e = scene.extent(of: s)
            } else { choice = nil }
            guard let e else {
                for l in [box, under, tint] { l.path = nil }
                return
            }
            let r = CGRect(x: e.minX * bounds.width, y: (1 - e.maxY) * bounds.height,
                           width: e.width * bounds.width, height: e.height * bounds.height).insetBy(dx: -4, dy: -4)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for l in [box, under, tint] { l.frame = bounds; l.path = CGPath(rect: r, transform: nil) }
            CATransaction.commit()
        }

        override func keyDown(with e: NSEvent) {
            switch e.keyCode {
            case 36, 76: onEnd(true)    // Return, keypad Enter
            case 53: onEnd(false)       // Esc
            default: super.keyDown(with: e)
            }
        }
    }
}
