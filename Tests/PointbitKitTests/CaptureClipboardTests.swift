import AppKit
import Testing
@testable import PointbitKit

@Suite struct CaptureClipboardTests {
    let url = URL(fileURLWithPath: "/Users/x/Desktop/TACS-20261101-095000123.png")

    @Test func pictureIsTheFileAndItsPath() {
        // Paste a capture straight into Notes. The file form lets Notes (or a chat app) attach
        // it; the text form keeps a terminal pasting the path. No image form: a file, not a copy of its pixels.
        let board = NSPasteboard(name: NSPasteboard.Name("pointbit-test-\(UUID())"))
        defer { board.releaseGlobally() }
        CaptureClipboard.put(file: url, to: board)
        #expect(board.string(forType: .string) == url.path, "a terminal pastes the path")
        #expect(board.string(forType: .fileURL) == url.absoluteString, "Notes pastes the file")
        let types = board.types ?? []
        #expect(!types.contains(.png) && !types.contains(.tiff))
    }

    @Test func recordingIsTheFileAndItsPath() {
        let board = NSPasteboard(name: NSPasteboard.Name("pointbit-test-\(UUID())"))
        defer { board.releaseGlobally() }
        CaptureClipboard.put(file: url, to: board)
        #expect(board.string(forType: .string) == url.path)
        #expect(board.string(forType: .fileURL) == url.absoluteString)
    }

    @Test func videoAndTextAreTwoPathsWithASpace() {
        let board = NSPasteboard(name: NSPasteboard.Name("pointbit-test-\(UUID())"))
        defer { board.releaseGlobally() }
        let video = URL(fileURLWithPath: "/Users/x/Desktop/TACS-20261101-095000123.mov")
        let text = URL(fileURLWithPath: "/Users/x/My Files/TACS-20261101-095000123.txt")
        CaptureClipboard.put(files: [video, text], to: board)
        #expect(board.string(forType: .string) == "/Users/x/Desktop/TACS-20261101-095000123.mov '/Users/x/My Files/TACS-20261101-095000123.txt'")
        let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(files == [video, text], "both files, for an app that takes several")
    }
}

@Suite struct CaptureClipboardOffTests {
    let url = URL(fileURLWithPath: "/Users/x/Desktop/TACS-20261101-095000123.mov")

    @Test func offCopiesNothing() {
        // "Copy to clipboard when it ends" off copies nothing (it used to copy a picture's image).
        let board = NSPasteboard(name: NSPasteboard.Name("pointbit-test-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("before", forType: .string)
        CaptureClipboard.put(file: url, copy: false, to: board)
        #expect(board.string(forType: .string) == "before" && board.string(forType: .fileURL) == nil)
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
