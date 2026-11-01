// Pictures: the window or the whole screen under the pointer, saved with screencapture to the save folder
// (SaveFolder, the Desktop by default) and the clipboard.
import AppKit

final class WindowShot {
    private var pending: Set<String> = []   // file names of captures still being written
    /// Called on the main thread after a capture, with the captured window's frame (Cocoa screen coordinates).
    var onCaptured: (NSRect) -> Void = { _ in }
    /// Put the file's path on the clipboard instead of the image (Preferences → Capture and Record).
    var copyPath = true
    /// Folder chosen in Preferences; empty or missing = the Desktop (SaveFolder).
    var saveFolder = ""

    /// The top normal window under `point` (Cocoa screen coordinates), not this app's own,
    /// with its frame in Cocoa screen coordinates.
    static func window(at point: NSPoint) -> (id: CGWindowID, frame: NSRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height else { return nil }
        let p = CGPoint(x: point.x, y: mainHeight - point.y)   // window bounds use top-left origin on the main screen
        let me = ProcessInfo.processInfo.processIdentifier
        for w in list {   // front to back
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let id = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if r.contains(p) { return (id, NSRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)) }
        }
        return nil
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

    /// Captures the window under the pointer to the save folder and the clipboard.
    func captureWindowUnderPointer() {
        guard Self.screenRecordingAllowed() else { return }
        guard let (id, frame) = Self.window(at: NSEvent.mouseLocation) else { NSSound.beep(); return }
        run(["-o", "-l", String(id)], frame: frame)   // no shadow, this window only
    }

    /// Captures the whole screen (display) under the pointer to the save folder and the clipboard.
    func captureScreenUnderPointer() {
        guard Self.screenRecordingAllowed() else { return }
        let point = NSEvent.mouseLocation
        guard let screen = Self.screen(at: point),
              let mainHeight = NSScreen.screens.first?.frame.height else { NSSound.beep(); return }
        let f = screen.frame   // -R takes the top-left origin of the main screen
        run(["-R", "\(Int(f.minX)),\(Int(mainHeight - f.maxY)),\(Int(f.width)),\(Int(f.height))"], frame: f)
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

    /// Runs screencapture (no sound) into a new file in the save folder, then copies the image and calls onCaptured(frame).
    private func run(_ arguments: [String], frame: NSRect) {
        let folder = SaveFolder.resolve(saveFolder)
        let name = Self.fileName(at: Date()) { [pending] n in
            pending.contains(n) || FileManager.default.fileExists(atPath: folder.appendingPathComponent(n).path)
        }
        pending.insert(name)
        let url = folder.appendingPathComponent(name)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x"] + arguments + [url.path]
        p.terminationHandler = { proc in
            DispatchQueue.main.async {
                self.pending.remove(name)
                guard proc.terminationStatus == 0, let image = NSImage(contentsOf: url) else { NSSound.beep(); return }
                CaptureClipboard.put(file: url, image: image, withPath: self.copyPath)
                self.onCaptured(frame)
            }
        }
        do { try p.run() } catch { pending.remove(name); NSSound.beep() }
    }
}
