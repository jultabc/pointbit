// Puts a finished picture or recording on the clipboard. With the path: the file's path as text only, so a
// terminal or an agent's chat pastes the path (apps that prefer an image would otherwise paste the picture).
// Without the path: a picture's image only, and nothing for a recording.
import AppKit

enum CaptureClipboard {
    static func put(file url: URL, image: NSImage? = nil, withPath: Bool = true, to board: NSPasteboard = .general) {
        guard withPath else {
            guard let image else { return }
            board.clearContents(); board.writeObjects([image])
            return
        }
        board.clearContents()
        board.setString(shellPath(url.path), forType: .string)
    }

    /// The path as text, pasted into a shell as one argument: left as is when every character is a letter, digit
    /// or one of / . _ -; otherwise wrapped in single quotes (a ' inside becomes '\'').
    static func shellPath(_ path: String) -> String {
        let safe = path.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "/._-".unicodeScalars.contains($0)) }
        return safe ? path : "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
