// A recording with sound is written as two files, the picture and the sound, and joined when it stops. When the
// sound fails part way (2017 MacBook Pro, macOS 13: the microphone's stream shook when another recording started,
// -16364), only the sound is lost: the video is kept without it. Joining copies both as they are (passthrough).
import AVFoundation

enum RecordingJoin {
    /// Both parts are .mov: a .m4a sound part drops the silence before the first sound, and the voice then comes
    /// early by the time the microphone took to start. ScreenRecorder writes the parts with this.
    static let partType = AVFileType.mov

    /// Where the two parts are written: hidden files next to the recording, so a crash leaves them in the save folder.
    static func parts(of url: URL) -> (video: URL, sound: URL) {
        (hidden(url, "video.mov"), hidden(url, "sound.mov"))
    }

    private static func hidden(_ url: URL, _ suffix: String) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent).\(suffix)")
    }

    /// The video at `video` with the sound at `sound` as one .mov at `out` (a new file), both from their start. The
    /// sound is cut at the video's end. False when either cannot be read or the export fails; `out` is then not there.
    static func join(video: URL, sound: URL, into out: URL) async -> Bool {
        let v = AVURLAsset(url: video), a = AVURLAsset(url: sound), all = AVMutableComposition()
        guard let vt = try? await v.loadTracks(withMediaType: .video).first,
              let at = try? await a.loadTracks(withMediaType: .audio).first,
              let length = try? await v.load(.duration), let soundLength = try? await a.load(.duration),
              let cv = all.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let ca = all.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              (try? cv.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: vt, at: .zero)) != nil,
              (try? ca.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, soundLength)), of: at, at: .zero)) != nil,
              let export = AVAssetExportSession(asset: all, presetName: AVAssetExportPresetPassthrough)
        else { return false }
        export.outputURL = out
        export.outputFileType = .mov
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in export.exportAsynchronously { done.resume() } }
        if export.status != .completed { try? FileManager.default.removeItem(at: out); return false }
        return true
    }

    /// Recordings whose parts are still in `folder` (the app quit or crashed while it recorded or joined): the
    /// recording's own name, for each video part whose recording is not there.
    static func leftovers(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { n -> URL? in
            guard n.hasPrefix("."), n.hasSuffix(".video.mov") else { return nil }
            let url = folder.appendingPathComponent(String(n.dropFirst().dropLast(".video.mov".count)) + ".mov")
            return FileManager.default.fileExists(atPath: url.path) ? nil : url
        }.sorted { $0.path < $1.path }
    }

    /// Puts the parts of `recordings` (from `leftovers`) at their names: joined when the sound part reads, else the
    /// video alone. Only a video part that reads (a finished file: the app died while joining) is put in place; one
    /// the app died while writing has no index and does not read, and its parts are left as they are. Returns the
    /// recordings put in place.
    static func recover(_ recordings: [URL]) async -> [URL] {
        var done: [URL] = []
        for url in recordings {
            let (video, sound) = parts(of: url)
            guard await reads(video, .video) else { continue }
            try? FileManager.default.removeItem(at: hidden(url, "joined.mov"))
            if await finish(url, videoDone: true, soundDone: await reads(sound, .audio)) != nil { done.append(url) }
        }
        return done
    }

    /// The file at `url` opens and has a `type` track.
    static func reads(_ url: URL, _ type: AVMediaType) async -> Bool {
        (try? await AVURLAsset(url: url).loadTracks(withMediaType: type))?.isEmpty == false
    }

    /// Puts the finished parts at `url`: joined when the sound is good, else the video alone. Returns whether `url`
    /// has sound; nil when there is no video at `url`. The parts are removed once `url` holds the video, or when
    /// there is no video; when the video cannot be put at `url` (it is taken, the move fails), both parts stay
    /// in the save folder as hidden files, so the recording is not lost.
    static func finish(_ url: URL, videoDone: Bool, soundDone: Bool) async -> Bool? {
        let (video, sound) = parts(of: url), fm = FileManager.default
        func removeParts() { try? fm.removeItem(at: video); try? fm.removeItem(at: sound) }
        guard videoDone else { removeParts(); return nil }
        // Joined into a hidden file first: an export into `url` would remove a file someone else put there.
        let joined = hidden(url, "joined.mov")
        if soundDone, await join(video: video, sound: sound, into: joined) {
            do { try fm.moveItem(at: joined, to: url) } catch { try? fm.removeItem(at: joined); return nil }
            removeParts(); return true
        }
        do { try fm.moveItem(at: video, to: url) } catch { return nil }
        removeParts()
        return false
    }
}
