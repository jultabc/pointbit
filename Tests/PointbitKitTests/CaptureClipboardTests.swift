import AppKit
import Testing
@testable import PointbitKit

@Suite struct CaptureClipboardTests {
    let url = URL(fileURLWithPath: "/Users/x/Desktop/TACS-20261101-095000123.png")

    @Test func pictureIsPathOnly() {
        let board = NSPasteboard(name: NSPasteboard.Name("pointbit-test-\(UUID())"))
        defer { board.releaseGlobally() }
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        CaptureClipboard.put(file: url, image: image, to: board)
        #expect(board.string(forType: .string) == url.path, "a terminal or an agent's chat pastes the path")
        let types = board.types ?? []
        #expect(!types.contains(.png) && !types.contains(.tiff) && !types.contains(.fileURL),
                "no image or file form, so an app does not paste the picture instead")
    }

    @Test func recordingIsPathOnly() {
        let board = NSPasteboard(name: NSPasteboard.Name("pointbit-test-\(UUID())"))
        defer { board.releaseGlobally() }
        CaptureClipboard.put(file: url, to: board)
        #expect(board.string(forType: .string) == url.path)
        let types = board.types ?? []
        #expect(!types.contains(.png) && !types.contains(.tiff) && !types.contains(.fileURL))
    }
}

@Suite struct CaptureClipboardOffTests {
    let url = URL(fileURLWithPath: "/Users/x/Desktop/TACS-20261101-095000123.mov")

    @Test func withoutPathPictureIsImageOnly() {
        let board = NSPasteboard(name: NSPasteboard.Name("pointbit-test-\(UUID())"))
        defer { board.releaseGlobally() }
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        CaptureClipboard.put(file: url, image: image, withPath: false, to: board)
        #expect(board.string(forType: .string) == nil, "no path when the box is off")
        #expect(board.string(forType: .fileURL) == nil)
        #expect(board.canReadObject(forClasses: [NSImage.self]), "the picture is still copied")
    }

    @Test func withoutPathRecordingLeavesClipboard() {
        let board = NSPasteboard(name: NSPasteboard.Name("pointbit-test-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("before", forType: .string)
        CaptureClipboard.put(file: url, withPath: false, to: board)
        #expect(board.string(forType: .string) == "before")
    }

    @Test func copyPathIsOnByDefaultAndSaved() {
        let d = UserDefaults(suiteName: "pointbit-test-\(UUID())")!
        let store = SettingsStore(d)
        #expect(store.load().copyPath)
        var s = store.load(); s.copyPath = false; store.save(s)
        #expect(!store.load().copyPath)
        store.reset()
        #expect(store.load().copyPath)
    }
}

@Suite struct SaveFolderTests {
    @Test func emptyOrMissingFolderIsDesktop() {
        #expect(SaveFolder.resolve("") == SaveFolder.desktop)
        #expect(SaveFolder.resolve("/no/such/folder-\(UUID())") == SaveFolder.desktop)
        #expect(SaveFolder.display("") == "Desktop")
    }

    @Test func existingFolderIsUsedAndSaved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pointbit-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(SaveFolder.resolve(dir.path).standardizedFileURL == dir.standardizedFileURL)
        let d = UserDefaults(suiteName: "pointbit-test-\(UUID())")!
        let store = SettingsStore(d)
        var s = store.load(); #expect(s.saveFolder.isEmpty)
        s.saveFolder = dir.path; store.save(s)
        #expect(store.load().saveFolder == dir.path)
    }
}

@Suite struct ShellPathTests {
    @Test func plainPathStaysAsIs() {
        #expect(CaptureClipboard.shellPath("/Users/x/Desktop/TACS-20261101-095000123.png") == "/Users/x/Desktop/TACS-20261101-095000123.png")
    }
    @Test func pathWithShellCharactersIsQuoted() {
        #expect(CaptureClipboard.shellPath("/tmp/A&B/a.png") == "'/tmp/A&B/a.png'")
        #expect(CaptureClipboard.shellPath("/tmp/Joe's/a.png") == "'/tmp/Joe'\\''s/a.png'")
        #expect(CaptureClipboard.shellPath("/tmp/사진/a.png") == "'/tmp/사진/a.png'")
    }
    @Test func pathWithSpaceIsQuoted() {
        #expect(CaptureClipboard.shellPath("/Volumes/T7 Shield/a.png") == "'/Volumes/T7 Shield/a.png'")
        #expect(CaptureClipboard.shellPath("/x/it's here/a.png") == "'/x/it'\\''s here/a.png'")
    }
}
