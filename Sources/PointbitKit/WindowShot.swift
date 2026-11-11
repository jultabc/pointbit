// Pictures: the window or the whole screen under the pointer, saved with screencapture to the save folder
// (SaveFolder, the Desktop by default) and, with Copy to clipboard when it ends on, the clipboard.
import AppKit

final class WindowShot {
    private var pending: Set<String> = []   // file names of captures still being written
    /// Called on the main thread after a capture, with the captured window's frame (Cocoa screen coordinates).
    var onCaptured: (NSRect) -> Void = { _ in }
    /// Put the file and its path on the clipboard (Preferences → Capture → Copy to clipboard when it ends).
    var copyPath = true
    /// Folder chosen in Preferences; empty or missing = the Desktop (SaveFolder).
    var saveFolder = ""

    /// The top window under `point` (Cocoa screen coordinates): another app's normal window or this app's Preferences,
    /// with its frame in Cocoa screen coordinates.
    static func window(at point: NSPoint) -> (id: CGWindowID, frame: NSRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height else { return nil }
        let p = CGPoint(x: point.x, y: mainHeight - point.y)   // window bounds use top-left origin on the main screen
        let me = ProcessInfo.processInfo.processIdentifier
        for w in list {   // front to back
            // Normal windows of other apps, and this app's Preferences (a floating window). This app's click marks
            // and highlighter windows (screen saver level) are never the target.
            let layer = w[kCGWindowLayer as String] as? Int, mine = (w[kCGWindowOwnerPID as String] as? Int32) == me
            guard mine ? layer == Int(CGWindowLevelForKey(.floatingWindow)) : layer == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let id = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if r.contains(p) { return (id, NSRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)) }
        }
        return nil
    }

    /// The window's frame now (Cocoa global), nil when it is gone or off screen.
    static func frame(of id: CGWindowID) -> NSRect? {
        guard let w = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first,
              w[kCGWindowIsOnscreen as String] as? Bool == true,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let mainHeight = NSScreen.screens.first?.frame.height else { return nil }
        let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        return NSRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
    }

    /// File name for a capture taken at `date`, unique among `taken` (files already in the folder and names
    /// being written): "TACS-<yyyyMMdd>-<HHmmssSSS>.png", then "-2", "-3" for the same millisecond.
    static func fileName(at date: Date, ext: String = "png", taken: (String) -> Bool) -> String {
        // TACS-<date>-<time with milliseconds>, no spaces, so a pasted path works in a shell without quotes.
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmssSSS"
        let base = "TACS-\(f.string(from: date))"
        var name = "\(base).\(ext)", n = 2
        while taken(name) { name = "\(base)-\(n).\(ext)"; n += 1 }
        return name
    }

    /// Captures the window under the pointer to the save folder (and the clipboard, if the setting is on).
    func captureWindowUnderPointer() {
        guard Self.screenRecordingAllowed() else { return }
        guard let (id, frame) = Self.window(at: NSEvent.mouseLocation) else { NSSound.beep(); return }
        run(["-o", "-l", String(id)], frame: frame)   // no shadow, this window only
    }

    /// ⌘ ⌘ R: opens the picker over the window under the pointer (CutoutPicker); ⌘ ⌘ R again saves the choice.
    /// macOS 14 or later.
    @MainActor func captureCutoutUnderPointer() {
        guard #available(macOS 14, *) else { NSSound.beep(); return }
        let picker = (cutoutPicker as? CutoutPicker) ?? CutoutPicker()
        cutoutPicker = picker
        if picker.isBusy { picker.confirm(); return }   // open: save; still preparing: cancel
        guard Self.screenRecordingAllowed() else { return }
        guard let (id, frame) = Self.window(at: NSEvent.mouseLocation) else { NSSound.beep(); return }
        picker.open(window: id, frame: frame, recording: isRecording()) { [weak self] scene, choice, picture in
            self?.save(scene, choice, frame: frame, removing: picture)
        }
    }
    private var cutoutPicker: AnyObject?   // a CutoutPicker (macOS 14 or later)

    /// Whether a recording is on (CaptureController): ⌘ ⌘ R then shows no dimmed outline while it reads.
    var isRecording: () -> Bool = { false }

    /// ⌘ ⌘ R is choosing (or preparing): other capture keys wait.
    @MainActor var cutoutBusy: Bool {
        guard #available(macOS 14, *) else { return false }
        return (cutoutPicker as? CutoutPicker)?.isBusy ?? false
    }

    /// Closes ⌘ ⌘ R's picker without saving (the feature turned off, the permission lost).
    @MainActor func cancelCutout() {
        guard #available(macOS 14, *) else { return }
        (cutoutPicker as? CutoutPicker)?.cancel()
    }

    /// Writes the chosen cut to a new file in the save folder, then the clipboard (if the setting is on) and onCaptured(frame).
    /// A line of text also gets its words in a .txt of the same name (with the setting on, on the clipboard with the picture's path, as a recording).
    @available(macOS 14, *)
    private func save(_ scene: CutoutScene, _ choice: CutoutChoice, frame: NSRect, removing picture: URL) {
        let folder = SaveFolder.resolve(saveFolder)
        let name = Self.fileName(at: Date()) { [pending] n in
            pending.contains(n) || FileManager.default.fileExists(atPath: folder.appendingPathComponent(n).path)
        }
        pending.insert(name)
        let url = folder.appendingPathComponent(name)
        DispatchQueue.global(qos: .userInitiated).async {
            var text: URL?
            let ok: Bool
            switch choice {
            case .subjects(let s): ok = scene.cut(s, into: url)
            case .text(let i):
                ok = scene.cutText(i, into: url)
                let t = url.deletingPathExtension().appendingPathExtension("txt")
                if ok, (try? (scene.texts[i].string + "\n").write(to: t, atomically: true, encoding: .utf8)) != nil { text = t }
            }
            try? FileManager.default.removeItem(at: picture)   // the window's picture, read by the cut
            DispatchQueue.main.async {
                self.pending.remove(name)
                guard ok, NSImage(contentsOf: url) != nil else { NSSound.beep(); return }
                if self.copyPath { if let text { CaptureClipboard.put(files: [url, text]) } else { CaptureClipboard.put(file: url) } }
                if case .text = choice, text == nil { NSSound.beep() }   // the picture is saved, its words are not
                self.onCaptured(frame)
            }
        }
    }

    /// Captures the whole screen (display) under the pointer to the save folder (and the clipboard, if the setting is on).
    func captureScreenUnderPointer() {
        guard Self.screenRecordingAllowed() else { return }
        let point = NSEvent.mouseLocation
        guard let screen = Self.screen(at: point),
              let mainHeight = NSScreen.screens.first?.frame.height else { NSSound.beep(); return }
        let f = screen.frame   // -R takes the top-left origin of the main screen
        run(["-R", "\(Int(f.minX)),\(Int(mainHeight - f.maxY)),\(Int(f.width)),\(Int(f.height))"], frame: f, area: true)
    }

    /// The screen under `point`; the main screen when the point is on an outer edge (NSMouseInRect leaves out
    /// the top and right edge lines).
    static func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
    }

    /// Screen Recording: without it screencapture exits 1.
    private static func screenRecordingAllowed() -> Bool {
        if CapturePermissions.screenAllowed { return true }
        NSSound.beep(); CapturePermissions.openScreenRecordingSettings()
        return false
    }

    /// A picture of a screen area (screencapture -R takes every window): takes the recording's dimmed outside off the
    /// screen and says whether there was one; the shot then waits `asideWait` so the screen shows it gone.
    /// RecordingFrame counts these, so overlapping pictures bring it back only after the last.
    var stepAside: () -> Bool = { false }
    /// Once for each stepAside that said true, as soon as screencapture ends.
    var stepBack: () -> Void = {}
    static let asideWait: TimeInterval = 0.25   // a picture within about half a second still feels at once

    /// Runs screencapture (no sound) into a new file in the save folder, then copies the file and its path (if the setting is on) and calls onCaptured(frame).
    /// `area`: a screen area, not one window (`-l`), so the dimmed outside has to step aside.
    private func run(_ arguments: [String], frame: NSRect, area: Bool = false) {
        let folder = SaveFolder.resolve(saveFolder)
        let name = Self.fileName(at: Date()) { [pending] n in
            pending.contains(n) || FileManager.default.fileExists(atPath: folder.appendingPathComponent(n).path)
        }
        pending.insert(name)
        let url = folder.appendingPathComponent(name)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x"] + arguments + [url.path]
        let aside = area && stepAside()
        p.terminationHandler = { proc in
            if aside { DispatchQueue.main.async { self.stepBack() } }   // right away, not after the cutout below
            DispatchQueue.main.async {
                self.pending.remove(name)
                guard proc.terminationStatus == 0, NSImage(contentsOf: url) != nil else { NSSound.beep(); return }
                CaptureClipboard.put(file: url, copy: self.copyPath)
                self.onCaptured(frame)
            }
        }
        let start = { [self] in
            do { try p.run() } catch { pending.remove(name); if aside { stepBack() }; NSSound.beep() }
        }
        if aside { DispatchQueue.main.asyncAfter(deadline: .now() + Self.asideWait, execute: start) } else { start() }
    }
}

