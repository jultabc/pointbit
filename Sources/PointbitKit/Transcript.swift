// What was said in a recording, as text: "TACS-<date>-<time>.txt" next to the .mov, one line per sentence or
// pause, each with its time in the video ("[01:05] …"). An agent cannot hear a video; it can read this file.
// Speech recognition runs on this Mac only: SpeechAnalyzer on macOS 26+, else SFSpeechRecognizer with
// requiresOnDeviceRecognition. Pointbit sends nothing over the network (macOS may download a language model).
import AVFoundation
import OSLog
import Speech

/// `log show --predicate 'subsystem == "si.codegg.pointbit"'` shows why a .txt was not written.
private let log = Logger(subsystem: "si.codegg.pointbit", category: "transcript")

/// One recognized word or phrase: where it starts in the video, how long it lasts, and its text.
/// `gap`: not speech but a note that a stretch could not be recognized; it gets a line of its own.
struct SpokenPiece: Equatable {
    var start: Double
    var duration: Double
    var text: String
    var gap = false
}

/// The outcome of one recognition part (`Transcript.partSeconds` of sound).
enum PartResult: Equatable {
    case heard([SpokenPiece])
    case silent                          // recognition finished with nothing said
    case failed(start: Double, end: Double, why: String = "")   // why: what the user can do, if known
}

enum Transcript {
    /// A new line after a pause longer than this (seconds), or after a sentence end (. ? ! 。).
    static let pauseBreak = 1.0

    /// The file text: one line per sentence or pause, "[mm:ss] words". Empty when nothing was said.
    static func lines(_ pieces: [SpokenPiece]) -> String {
        var out: [String] = [], line: [String] = [], lineStart = 0.0, lastEnd = -Double.infinity
        func flush() { if !line.isEmpty { out.append("[\(clock(lineStart))] " + line.joined(separator: " ")); line = [] } }
        for p in pieces where !p.text.isEmpty {
            if p.gap {
                flush(); out.append("[\(clock(p.start))] " + p.text); lastEnd = p.start + p.duration
                continue
            }
            if p.start - lastEnd > pauseBreak { flush() }
            if line.isEmpty { lineStart = p.start }
            line.append(p.text)
            lastEnd = p.start + p.duration
            if let c = p.text.last, ".?!。".contains(c) { flush() }
        }
        flush()
        return out.isEmpty ? "" : out.joined(separator: "\n") + "\n"
    }

    /// All parts in order. A failed part becomes a note line, so the file shows that stretch is missing
    /// instead of reading as silence.
    static func pieces(_ parts: [PartResult]) -> [SpokenPiece] {
        parts.flatMap { part -> [SpokenPiece] in
            switch part {
            case .heard(let p): return p
            case .silent: return []
            case .failed(let a, let b, let why):
                let note = why.isEmpty ? "" : " — \(why)"
                return [SpokenPiece(start: a, duration: b - a, text: "(not recognized: \(clock(a))–\(clock(b))\(note))", gap: true)]
            }
        }
    }

    /// Seconds as mm:ss (h:mm:ss from one hour).
    static func clock(_ seconds: Double) -> String {
        let t = seconds.isFinite ? Int(max(0, min(seconds, 359_999))) : 0   // NaN or ±infinity would stop the app
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%02d:%02d", t / 60, t % 60)
    }

    /// The language to recognize: `id` when set, else the first of the Mac's preferred languages that this Mac
    /// can recognize offline.
    static func recognizer(_ id: String) -> SFSpeechRecognizer? {
        let ids = id.isEmpty ? Locale.preferredLanguages : [id]
        return ids.lazy.compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }.first { $0.supportsOnDeviceRecognition }
    }

    /// Languages the Mac can recognize offline, for the Preferences pop-up: (identifier, name).
    static func languages() -> [(id: String, name: String)] {
        SFSpeechRecognizer.supportedLocales()
            .filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }
            .map { ($0.identifier, Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) }
            .sorted { $0.name < $1.name }
    }

    /// Writes the .txt next to `video` from its sound track. Returns the file, or nil when there is no sound
    /// track, speech recognition is not allowed or not available offline, or nothing was recognized.
    static func write(for video: URL, language: String) async -> URL? {
        guard let pieces = await recognizeAny(video, language: language) else { return nil }
        let text = lines(pieces)
        guard !text.isEmpty else { log.notice("nothing recognized in \(pieces.count) pieces"); return nil }
        let url = video.deletingPathExtension().appendingPathExtension("txt")
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    /// macOS 26 and later: SpeechAnalyzer (made for long sound; on the test files of 2026-11-02 it kept every
    /// sentence where SFSpeechRecognizer dropped some). Earlier macOS, or if it fails: SFSpeechRecognizer in parts.
    private static func recognizeAny(_ video: URL, language: String) async -> [SpokenPiece]? {
        if #available(macOS 26, *), let p = await analyze(video, language: language) { return p }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { log.error("speech recognition not allowed"); return nil }
        guard let r = recognizer(language) else { log.error("no offline recognizer for '\(language, privacy: .public)'"); return nil }
        guard let pieces = await recognize(video, with: r) else { log.error("sound track not readable"); return nil }
        return pieces
    }

    /// SpeechAnalyzer + SpeechTranscriber on this Mac. The language model is a macOS asset: macOS downloads it
    /// once if it is missing (Pointbit itself sends nothing). One piece per word, from the audio time ranges.
    /// nil when the language is not supported or the analysis fails (the caller then uses SFSpeechRecognizer).
    @available(macOS 26, *)
    private static func analyze(_ video: URL, language: String) async -> [SpokenPiece]? {
        let ids = language.isEmpty ? Locale.preferredLanguages : [language]
        var locale: Locale?
        for id in ids { if let l = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) { locale = l; break } }
        guard SpeechTranscriber.isAvailable, let locale else { log.notice("SpeechTranscriber: no supported locale"); return nil }
        // AVAudioFile reads from the first sound sample, so its times start there; the sound track starts a little
        // after the video (the microphone starts after the first frame). The offset moves the times into the video.
        let offset = await soundStart(video)
        let length = (try? await AVURLAsset(url: video).load(.duration).seconds) ?? 0
        let t = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        // The language model first, with its own limit (a first download can take minutes). If it does not
        // finish, the older engine is used this time. Whether macOS keeps a download that was cancelled at the
        // limit is not checked yet (to test on a Mac without the model).
        let modelReady: Bool? = await within(downloadLimit, "model download") {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await request.downloadAndInstall() }
            return true
        }
        guard modelReady == true else { return nil }
        // Then the analysis: 3 × the video's length + 30 s, like the older engine.
        let words: [SpokenPiece]? = await within(timeLimit(length), "analysis") {
            let file = try AVAudioFile(forReading: video)
            let analyzer = SpeechAnalyzer(modules: [t])
            let collect = Task { () throws -> [SpokenPiece] in
                var out: [SpokenPiece] = []
                for try await r in t.results {
                    for run in r.text.runs {
                        guard let tr = run.audioTimeRange else { continue }
                        let word = String(r.text[run.range].characters).trimmingCharacters(in: .whitespaces)
                        if !word.isEmpty { out.append(SpokenPiece(start: tr.start.seconds, duration: tr.duration.seconds, text: word)) }
                    }
                }
                return out
            }
            do {
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
                return try await withTaskCancellationHandler { try await collect.value } onCancel: { collect.cancel() }
            } catch { collect.cancel(); throw error }
        }
        guard let words else { return nil }
        let pieces = shifted(words, by: offset)
        log.notice("SpeechTranscriber \(locale.identifier, privacy: .public): \(pieces.count) words, sound starts at \(offset, privacy: .public) s")
        return pieces
    }

    /// Seconds the first language model download may take.
    static let downloadLimit = 600.0

    /// Runs `op`; answers its result, or nil when it throws or runs past `seconds` (then it is cancelled and left
    /// to end on its own). Whichever ends first answers, once.
    static func within<T: Sendable>(_ seconds: Double, _ what: String,
                                            _ op: @escaping @Sendable () async throws -> T) async -> T? {
        let work = Task { try await op() }
        return await withCheckedContinuation { done in
            let once = Once()
            let timer = Task {
                try await Task.sleep(nanoseconds: nanoseconds(seconds))
                if once.claim() { log.error("SpeechTranscriber \(what, privacy: .public) ran past \(seconds, privacy: .public) s"); work.cancel(); done.resume(returning: nil) }
            }
            Task {
                do {
                    let v = try await work.value
                    timer.cancel()
                    if once.claim() { done.resume(returning: v) }
                } catch {
                    timer.cancel()
                    let n = error as NSError
                    log.error("SpeechTranscriber \(what, privacy: .public) failed: \(n.domain, privacy: .public) \(n.code)")
                    if once.claim() { done.resume(returning: nil) }
                }
            }
        }
    }

    /// Seconds a recognition may take: 3 × `length` + 30, at most one day. A length that is not a finite number
    /// of seconds ≥ 0 (an unreadable or open-ended file: NaN or ±infinity) counts as 0.
    static func timeLimit(_ length: Double) -> Double {
        let l = length.isFinite && length > 0 ? length : 0
        return min(l * 3 + 30, 86_400)
    }

    /// `seconds` as nanoseconds for Task.sleep, inside UInt64 (0 for NaN or a negative value).
    static func nanoseconds(_ seconds: Double) -> UInt64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let ns = seconds * 1e9
        return ns >= Double(UInt64.max) ? UInt64.max : UInt64(ns)
    }

    /// Pieces moved later by `seconds` (sound-file time to video time).
    static func shifted(_ pieces: [SpokenPiece], by seconds: Double) -> [SpokenPiece] {
        pieces.map { var p = $0; p.start += seconds; return p }
    }

    /// Where the sound track's first sample is in the video, in seconds (0 when it cannot be read): the length
    /// of an empty edit at the start of the track, else the track's start time.
    private static func soundStart(_ video: URL) async -> Double {
        guard let track = try? await AVURLAsset(url: video).loadTracks(withMediaType: .audio).first else { return 0 }
        if let segments = try? await track.load(.segments), let first = segments.first, first.isEmpty {
            let s = first.timeMapping.target.duration.seconds
            return s.isFinite ? max(0, s) : 0
        }
        let s = ((try? await track.load(.timeRange))?.start.seconds) ?? 0
        return s.isFinite ? max(0, s) : 0
    }

    /// Seconds of sound per recognition request. Apple's documentation limits one recognition task to about
    /// one minute, so the sound track goes in parts; a word cut at a part's edge can be lost.
    static let partSeconds = 50.0

    /// Reads the sound track as PCM in parts of `partSeconds` and recognizes each part offline. Times are in the
    /// video (each part's offset = its first sample's time). nil when the track cannot be read.
    private static func recognize(_ video: URL, with r: SFSpeechRecognizer) async -> [SpokenPiece]? {
        let asset = AVURLAsset(url: video)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1])
        guard reader.canAdd(out) else { return nil }
        reader.add(out)
        guard reader.startReading(),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)
        else { return nil }

        var parts: [PartResult] = [], part: [AVAudioPCMBuffer] = [], partStart = 0.0, partFrames = 0.0, readTo = 0.0
        func send() async {
            guard !part.isEmpty else { return }
            parts.append(await recognizePart(part, from: partStart, to: partStart + partFrames / format.sampleRate, with: r))
            part = []; partFrames = 0
        }
        while let sb = out.copyNextSampleBuffer() {
            let at = CMTimeGetSeconds(sb.presentationTimeStamp), length = CMTimeGetSeconds(sb.duration)
            readTo = at + (length.isFinite ? length : 0)
            guard let b = pcm(sb, format: format) else {   // this stretch cannot be converted: say so
                await send(); addFailure(&parts, start: at, end: readTo); continue
            }
            if part.isEmpty { partStart = at }
            part.append(b); partFrames += Double(b.frameLength)
            if partFrames >= partSeconds * format.sampleRate { await send() }
        }
        await send()
        // nil from copyNextSampleBuffer is the end of the track or a read error; only .completed is the end.
        let total = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)
        return pieces(finished(parts, completed: reader.status == .completed, readTo: readTo, total: total))
    }

    /// Adds a failed stretch; joins it to a failed stretch just before it.
    static func addFailure(_ parts: inout [PartResult], start: Double, end: Double) {
        if case .failed(let a, let b, let why) = parts.last, start - b < 0.5 {
            parts[parts.count - 1] = .failed(start: a, end: max(b, end), why: why); return
        }
        parts.append(.failed(start: start, end: end))
    }

    /// The parts after reading stopped: unchanged when the reader completed; otherwise the rest of the track,
    /// from where reading stopped to its end, is a failed stretch.
    static func finished(_ parts: [PartResult], completed: Bool, readTo: Double, total: Double) -> [PartResult] {
        guard !completed else { return parts }
        var p = parts; addFailure(&p, start: readTo, end: max(readTo, total)); return p
    }

    /// Speech framework error for "nothing was said" (kAFAssistantErrorDomain 1110): silence, not a failure.
    private static func isNoSpeech(_ e: Error) -> Bool {
        let n = e as NSError
        return n.domain == "kAFAssistantErrorDomain" && n.code == 1110
    }

    /// What the user can do about a recognition error, when it is known. kLSRErrorDomain 201 =
    /// "Siri and Dictation are disabled": offline recognition needs Dictation on (seen 2026-11-02, macOS 26.5).
    static func why(_ e: Error) -> String {
        let n = e as NSError
        return n.domain == "kLSRErrorDomain" && n.code == 201 ? "turn on Dictation: System Settings → Keyboard → Dictation" : ""
    }

    /// Joins recognition results. A result can repeat earlier words (one growing text) or hold only the newest
    /// sentence (macOS sends one result per sentence on long sound); either way a result replaces the pieces
    /// it covers in time, and pieces outside it stay.
    static func merge(_ pieces: [SpokenPiece], with result: [SpokenPiece]) -> [SpokenPiece] {
        guard let first = result.first?.start, let last = result.last.map({ $0.start + $0.duration }) else { return pieces }
        return (pieces.filter { $0.start + $0.duration <= first || $0.start >= last } + result).sorted { $0.start < $1.start }
    }

    /// One recognition request for `buffers`, the sound from `start` to `end` seconds of the video.
    /// On long sound macOS sends one final-looking result per sentence, so every result is kept (merge) and the
    /// part ends when the task completes, fails, or runs past `3 × length + 30 s`.
    private static func recognizePart(_ buffers: [AVAudioPCMBuffer], from start: Double, to end: Double,
                                      with r: SFSpeechRecognizer) async -> PartResult {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let box = RecognitionBox()
        let task = r.recognitionTask(with: request) { result, error in
            box.add(result?.bestTranscription.segments.map {
                SpokenPiece(start: start + $0.timestamp, duration: $0.duration, text: $0.substring) }, error: error)
        }
        buffers.forEach(request.append)
        request.endAudio()
        let deadline = Date().addingTimeInterval((end - start) * 3 + 30)
        while task.state != .completed && box.error == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if task.state == .completed { try? await Task.sleep(nanoseconds: 200_000_000) }   // a last result still on its way
        let (heard, error) = (box.heard, box.error)
        let n = error.map { $0 as NSError }
        log.notice("part \(start, privacy: .public)–\(end, privacy: .public) s: \(heard.count) pieces, state \(task.state.rawValue), error \(n?.domain ?? "-", privacy: .public) \(n?.code ?? 0)")
        if task.state != .completed && error == nil { task.cancel() }
        if let error, isNoSpeech(error) { return heard.isEmpty ? .silent : .heard(heard) }
        if error == nil && task.state == .completed { return heard.isEmpty ? .silent : .heard(heard) }
        // A real error or no end in time: keep what was heard, mark the rest of this part.
        let reason = error.map(why) ?? "recognition did not finish"
        let from = heard.last.map { $0.start + $0.duration } ?? start
        if heard.isEmpty { return .failed(start: start, end: end, why: reason) }
        return .heard(heard + pieces([.failed(start: from, end: max(from, end), why: reason)]))
    }

    /// One sample buffer as an AVAudioPCMBuffer in `format`.
    private static func pcm(_ sb: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sb))
        guard frames > 0, let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        b.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(frames), into: b.mutableAudioBufferList)
        return status == noErr ? b : nil
    }
}

/// Results of one recognition task, written by the Speech framework's handler and read by recognizePart.
private final class RecognitionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _heard: [SpokenPiece] = [], _error: Error?
    var heard: [SpokenPiece] { lock.withLock { _heard } }
    var error: Error? { lock.withLock { _error } }
    func add(_ pieces: [SpokenPiece]?, error: Error?) {
        lock.withLock {
            if let pieces { _heard = Transcript.merge(_heard, with: pieces) }
            if let error, _error == nil { _error = error }
        }
    }
}

/// True for the first caller only (the first of two racing tasks answers a continuation).
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func claim() -> Bool { lock.withLock { defer { taken = true }; return !taken } }
}
