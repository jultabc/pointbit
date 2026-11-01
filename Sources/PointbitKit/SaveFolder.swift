// Where pictures and recordings are saved: the folder chosen in Preferences, or the Desktop.
import AppKit

enum SaveFolder {
    static var desktop: URL { FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0] }

    /// The chosen folder when it still exists; otherwise (empty, moved or deleted) the Desktop.
    static func resolve(_ path: String) -> URL {
        var isDir: ObjCBool = false
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue
        else { return desktop }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Short name for Preferences: "Desktop" or the folder's path with ~ for the home folder.
    static func display(_ path: String) -> String {
        let url = resolve(path)
        if url.standardizedFileURL == desktop.standardizedFileURL { return "Desktop" }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// Asks for a folder. nil when the panel is cancelled.
    @MainActor static func choose() -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.allowsMultipleSelection = false; p.prompt = "Choose"; p.message = "Pictures and recordings are saved in this folder."
        return p.runModal() == .OK ? p.url?.path : nil
    }
}
