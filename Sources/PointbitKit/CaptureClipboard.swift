// Puts a finished picture or recording on the clipboard: the file itself and its path as text, so Notes or a chat
// app pastes the file and a terminal usually pastes the path. Preferences → Capture → "Copy to clipboard when it
// ends"; off, nothing is copied.
import AppKit

enum CaptureClipboard {
    /// `url` on the clipboard, when `copy` (the setting) is on; nothing otherwise.
    static func put(file url: URL, copy: Bool = true, to board: NSPasteboard = .general) {
        guard copy else { return }
        put(files: [url], to: board)
    }

    /// The files themselves (so Notes, Mail or a chat app pastes them as attachments) and their paths as text,
    /// separated by a space, each as `shellPath` writes it (so a terminal pastes the paths). One item per file;
    /// the text goes on the first (paste a capture straight into Notes).
    static func put(files urls: [URL], to board: NSPasteboard = .general) {
        board.clearContents()
        let items = urls.map { url -> NSPasteboardItem in
            let item = NSPasteboardItem(); item.setString(url.absoluteString, forType: .fileURL); return item
        }
        items.first?.setString(urls.map { shellPath($0.path) }.joined(separator: " "), forType: .string)
        board.writeObjects(items)
    }

    /// The path as text, pasted into a shell as one argument: left as is when every character is a letter, digit
    /// or one of / . _ -; otherwise wrapped in single quotes (a ' inside becomes '\'').
    static func shellPath(_ path: String) -> String {
        let safe = path.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "/._-".unicodeScalars.contains($0)) }
        return safe ? path : "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
