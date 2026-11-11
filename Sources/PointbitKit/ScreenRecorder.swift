// Records part of a display to a .mov file with ScreenCaptureKit and AVAssetWriter. Video only, or video and the
// microphone when `voice` is on (AVCaptureSession; system and app sounds are never recorded). The sound is written
// to its own file and joined with the video when the recording stops (RecordingJoin), so a failing sound keeps the video.
// The whole display is captured and cropped to the plan's rect, so Pointbit's click marks are in the video.
// Main actor, except the sample callbacks, which run on `queue`; writer state is only touched on `queue`.
import AVFoundation
import AppKit
import ScreenCaptureKit
import os

private let log = Logger(subsystem: "si.codegg.pointbit", category: "recorder")

/// An error as its domain and code (and the underlying one's), for the log: never its text or user info, which can
/// hold the file path.
func logCode(_ error: Error?) -> String {
    guard let e = error as NSError? else { return "none" }
    let under = (e.userInfo[NSUnderlyingErrorKey] as? NSError).map { " (\($0.domain) \($0.code))" } ?? ""
    return "\(e.domain) \(e.code)\(under)"
}

@MainActor
final class ScreenRecorder: NSObject, SCStreamOutput, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var stream: SCStream?
    private var mic: AVCaptureSession?
    private var plan: RecordingPlan?, config: SCStreamConfiguration?
    private(set) var screenFrame = CGRect.zero   // the recorded screen, Cocoa global
    /// The recorded rect without the zoom (display points, top-left origin); the zoom shows a part of it.
    private(set) var base: CGRect?
    /// The zoom and following a window change the recorded rect one at a time (RecordingZoom).
    let gate = ConfigGate()
    private(set) var url: URL?
    private nonisolated let queue = DispatchQueue(label: "Pointbit.recorder")
    // On `queue` only.
    private nonisolated(unsafe) var writer: AVAssetWriter?
    private nonisolated(unsafe) var input: AVAssetWriterInput?
    private nonisolated(unsafe) var frames: AVAssetWriterInputPixelBufferAdaptor?
    private nonisolated(unsafe) var audioInput: AVAssetWriterInput?
    private nonisolated(unsafe) var soundWriter: AVAssetWriter?   // the sound's own file (RecordingJoin)
    private nonisolated(unsafe) var soundStarted = false
    private nonisolated(unsafe) var started = false
    private nonisolated(unsafe) var appendFailed = false   // logged once per recording
    private nonisolated(unsafe) var soundFailed = false    // the sound file failed: the video goes on without it
    private nonisolated(unsafe) var appended = 0           // frames given to the writer, for the log
    private nonisolated(unsafe) var soundEnd = CMTime.invalid   // end of the last sound appended (host time)
    private nonisolated(unsafe) var sounds = 0, overlaps = 0    // sound buffers appended, and dropped for going back in time
    private nonisolated(unsafe) var sessionStart = CMTime.invalid
    private nonisolated(unsafe) var micClock: CMClock?   // the microphone session's clock; samples are converted to host time

    /// Starts recording `area` (Cocoa global rect) on `screen` into `url`, at the screen's full pixel size
    /// (`fullSize`) or at its point size (half each way on Retina, smaller files). Throws when ScreenCaptureKit or the
    /// writer refuses; then no file is left. With `voice`, also the microphone; when the microphone cannot be
    /// used (none, or not allowed) the video is recorded without sound. Returns whether the sound is recorded.
    @discardableResult
    func start(area: CGRect, screen: NSScreen, url: URL, voice: Bool = false, fullSize: Bool = false,
               leavingOut hidden: [CGWindowID] = []) async throws -> Bool {
        guard stream == nil else { return mic != nil }
        guard let plan = RecordingPlan(area: area, screen: screen.frame, scale: fullSize ? screen.backingScaleFactor : 1),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { throw RecorderError.nothingToRecord }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == number }) else { throw RecorderError.nothingToRecord }

        let config = SCStreamConfiguration()
        config.sourceRect = plan.sourceRect
        config.width = plan.width; config.height = plan.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA

        // H.264 above about 4K can exceed the hardware encoder; HEVC there.
        let codec: AVVideoCodecType = plan.width * plan.height > 3840 * 2160 ? .hevc : .h264
        let parts = RecordingJoin.parts(of: url)
        let w = try AVAssetWriter(outputURL: parts.video, fileType: RecordingJoin.partType)
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec, AVVideoWidthKey: plan.width, AVVideoHeightKey: plan.height])
        i.expectsMediaDataInRealTime = true
        guard w.canAdd(i) else { throw RecorderError.writer }
        w.add(i)
        let f = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: nil)
        var session: AVCaptureSession?, a: AVAssetWriterInput?, sw: AVAssetWriter?
        if voice, let (s, ai) = try? makeMic(), let sound = try? AVAssetWriter(outputURL: parts.sound, fileType: RecordingJoin.partType),
           sound.canAdd(ai) {
            sound.add(ai)
            if sound.startWriting() { session = s; a = ai; sw = sound }
        }
        guard w.startWriting() else { sw?.cancelWriting(); throw w.error ?? RecorderError.writer }
        log.notice("start \(plan.width)x\(plan.height) source \(plan.sourceRect.debugDescription, privacy: .public) codec \(codec.rawValue, privacy: .public)")

        let left = content.windows.filter { hidden.contains($0.windowID) }   // the box around the recorded rect
        let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: left), configuration: config, delegate: nil)
        queue.sync {
            writer = w; input = i; frames = f; audioInput = a; soundWriter = sw; soundStarted = false; soundFailed = false
            started = false; appendFailed = false; appended = 0; soundEnd = .invalid; sounds = 0; overlaps = 0
            sessionStart = .invalid; micClock = nil
        }
        do {
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await s.startCapture()
        } catch {   // nothing recorded: drop the writer and its file
            log.error("capture did not start: \(logCode(error), privacy: .public)")
            queue.sync { writer = nil; input = nil; frames = nil; audioInput = nil; soundWriter = nil }
            w.cancelWriting(); sw?.cancelWriting()
            try? FileManager.default.removeItem(at: parts.video); try? FileManager.default.removeItem(at: parts.sound)
            throw error
        }
        if let session {
            session.startRunning()
            // The session's clock is known once it runs; samples that come before this are dropped.
            let clock = session.synchronizationClock
            queue.sync { micClock = clock }
        }
        stream = s; mic = session; self.url = url
        self.plan = plan; self.config = config; screenFrame = screen.frame; base = plan.sourceRect
        return session != nil
    }

    /// What is being recorded (without the zoom), Cocoa global; nil when not recording.
    var recordedArea: CGRect? {
        guard stream != nil, let r = base else { return nil }
        return Zoom.global(r, on: screenFrame)
    }

    /// Shows `rect` (display points, top-left origin; a part of `base`) in the video, at the video's size: the zoom.
    /// False when not recording, refused, or asked for in an older `epoch` (a follow or a stop came first).
    func show(_ rect: CGRect, epoch: Int) async -> Bool {
        await gate.run(in: epoch) {
            // Never outside the recorded rect as it is now (a step computed against the old place).
            guard let s = stream, let config, let base, Zoom.inside(rect, base) else { return false }
            return await Self.move(config, to: rect) { try await s.updateConfiguration($0) }
        } ?? false
    }

    /// The recorded window moved to `area` (Cocoa global): the recorded rect goes with it, same size, inside the screen.
    /// True when the recorded rect is where `area` puts it (also when that is where it already was); false when
    /// not recording or ScreenCaptureKit refused the change (the rect then stays where it was).
    func follow(_ area: CGRect) async -> Bool {
        gate.newEpoch()   // zoom steps asked for before this would show the old place
        return await gate.run {
            guard let s = stream, let plan, let config, let old = base else { return false }
            let rect = plan.following(area, on: screenFrame)
            guard await Self.move(config, to: rect, update: { try await s.updateConfiguration($0) }) else {
                // Refused: at least drop a zoom, back to the unzoomed rect where it was.
                _ = await Self.move(config, to: old) { try await s.updateConfiguration($0) }
                return false
            }
            base = rect
            gate.newEpoch()   // and steps asked for while it moved were made against the old place
            return true
        } ?? false
    }

    /// Sets `config`'s source rect to `rect` and hands it to `update`; when `update` throws, puts the old rect back,
    /// so `recordedArea` always tells what the stream records.
    static func move(_ config: SCStreamConfiguration, to rect: CGRect,
                     update: (SCStreamConfiguration) async throws -> Void) async -> Bool {
        let old = config.sourceRect
        guard rect != old else { return true }
        config.sourceRect = rect
        do { try await update(config); return true } catch {
            config.sourceRect = old
            log.error("recorded rect change failed: \(logCode(error), privacy: .public)")
            return false
        }
    }

    /// The microphone session and the writer's AAC input. Throws when there is no microphone or no permission.
    private func makeMic() throws -> (AVCaptureSession, AVAssetWriterInput) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let device = AVCaptureDevice.default(for: .audio) else { throw RecorderError.microphone }
        let session = AVCaptureSession()
        let deviceInput = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        guard session.canAddInput(deviceInput), session.canAddOutput(output) else { throw RecorderError.microphone }
        session.addInput(deviceInput); session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        // The microphone's own format varies (2017 MacBook Pro, macOS 13: the AAC writer refused it, -12737, and the
        // whole file was lost). Ask the capture output for 48 kHz mono 16-bit PCM, the writer's input as it expects.
        output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
                                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                                AVLinearPCMIsNonInterleaved: false]
        let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000])
        a.expectsMediaDataInRealTime = true
        return (session, a)
    }

    /// Whether the last finished recording has sound (false when the sound part failed or there was none).
    private(set) var lastHasSound = false

    /// Stops and finishes the file. Returns the file when it was written; `lastHasSound` tells whether it has sound.
    /// `captured` runs as soon as nothing more goes into the video, before the file is finished and joined (that can
    /// take a few seconds), so what is drawn on the screen can go at once.
    func stop(captured: () -> Void = {}) async -> URL? {
        lastHasSound = false
        guard let s = stream else { captured(); return nil }
        stream = nil; plan = nil; config = nil; base = nil; gate.newEpoch()
        mic?.stopRunning(); mic = nil
        try? await s.stopCapture()
        captured()
        // Frames come only when the screen changes: end the session now, not at the last changed frame,
        // so a still screen at the end stays in the video.
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        let (w, i, a, sw, heard, hadFrames, sound) = queue.sync {
            () -> (AVAssetWriter?, AVAssetWriterInput?, AVAssetWriterInput?, AVAssetWriter?, Bool, Bool, String) in
            let tail = soundEnd.isValid ? CMTimeGetSeconds(CMTimeSubtract(end, soundEnd)) : .nan
            let r = (writer, input, audioInput, soundWriter, soundStarted && !soundFailed, started,
                     "\(sounds) sounds, \(overlaps) dropped, end - last sound \(tail) s")
            writer = nil; input = nil; frames = nil; audioInput = nil; soundWriter = nil
            return r
        }
        guard let w, let i, let url else { return nil }
        i.markAsFinished(); a?.markAsFinished()
        log.notice("stop frames \(hadFrames) (\(sound, privacy: .public)) status \(w.status.rawValue) error \(logCode(w.error), privacy: .public)")
        guard hadFrames else {
            w.cancelWriting(); sw?.cancelWriting()
            _ = await RecordingJoin.finish(url, videoDone: false, soundDone: false)   // removes the parts
            return nil
        }
        w.endSession(atSourceTime: end)
        await w.finishWriting()
        if w.status != .completed { log.error("finish failed status \(w.status.rawValue) error \(logCode(w.error), privacy: .public)") }
        var soundDone = false
        if let sw {
            if heard, sw.status == .writing {
                sw.endSession(atSourceTime: end)
                await sw.finishWriting()
                soundDone = sw.status == .completed
            } else { sw.cancelWriting() }
            if !soundDone { log.error("sound left out: status \(sw.status.rawValue) error \(logCode(sw.error), privacy: .public)") }
        }
        let has = await RecordingJoin.finish(url, videoDone: w.status == .completed, soundDone: soundDone)
        if soundDone, has == false { log.error("join failed: the video is kept without sound") }
        lastHasSound = has == true
        return has == nil ? nil : url
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let w = writer, let i = input, let f = frames, sb.isValid,
              let pixels = CMSampleBufferGetImageBuffer(sb),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete   // skip idle frames
        else { return }
        if !started { w.startSession(atSourceTime: sb.presentationTimeStamp); sessionStart = sb.presentationTimeStamp; started = true }
        guard i.isReadyForMoreMediaData else { return }
        func size() -> String { "\(CVPixelBufferGetWidth(pixels))x\(CVPixelBufferGetHeight(pixels)) format \(CVPixelBufferGetPixelFormatType(pixels))" }
        // The pixels only, through the adaptor, not ScreenCaptureKit's sample buffer itself: tried first on a 2017
        // MacBook Pro (macOS 13) for random -11800 / -12737 failures. Those turned out to come from the microphone's
        // format (see makeMic); the adaptor stayed, as it does the same work.
        if f.append(pixels, withPresentationTime: sb.presentationTimeStamp) { appended += 1 } else if !appendFailed {
            appendFailed = true
            log.error("""
                append failed after \(self.appended) frames, buffer \(size(), privacy: .public), \
                status \(w.status.rawValue) error \(logCode(w.error), privacy: .public)
                """)
        }
    }

    /// Microphone samples. Their times are on the capture session's clock; they are moved to host time, the clock
    /// of the screen frames, so the voice lines up with the video. Samples from before the first video frame are
    /// dropped (the file's timeline starts there).
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard started, !soundFailed, let a = audioInput, let sw = soundWriter, sb.isValid,
              let host = Self.onHostClock(sb, from: micClock),
              CMTimeCompare(host.presentationTimeStamp, sessionStart) >= 0 else { return }
        // The sound file starts where the video does, so the two line up when joined.
        if !soundStarted {
            sw.startSession(atSourceTime: sessionStart); soundStarted = true
            log.notice("first sound \(CMTimeGetSeconds(CMTimeSubtract(host.presentationTimeStamp, self.sessionStart))) s after the first frame")
        }
        guard a.isReadyForMoreMediaData else { return }
        // The microphone's clock, moved to host time, can step back a little; the writer fails on sound that goes back
        // in time (2017 MacBook Pro: -16364 when finishing). Such a buffer is dropped.
        if soundEnd.isValid, CMTimeCompare(host.presentationTimeStamp, CMTimeSubtract(soundEnd, CMTime(value: 1, timescale: 1000))) < 0 {
            overlaps += 1; return
        }
        if a.append(host) {
            sounds += 1; soundEnd = CMTimeAdd(host.presentationTimeStamp, CMSampleBufferGetDuration(host))
        } else {
            soundFailed = true   // its file is lost; the video file is not touched
            let after = CMTimeGetSeconds(CMTimeSubtract(host.presentationTimeStamp, sessionStart))
            log.error("""
                audio append failed: \(CMSampleBufferGetNumSamples(sb)) samples, \(after) s after start, \
                status \(sw.status.rawValue) error \(logCode(sw.error), privacy: .public)
                """)
        }
    }

    /// `sb` with its times converted from `clock` to the host time clock; nil while the clock is not known yet.
    /// Each timing entry keeps its own duration (one sample's length for sound); only the times move.
    private nonisolated static func onHostClock(_ sb: CMSampleBuffer, from clock: CMClock?) -> CMSampleBuffer? {
        guard let clock, var timing = try? sb.sampleTimingInfos(), !timing.isEmpty else { return nil }
        let pts = sb.presentationTimeStamp
        let shift = CMTimeSubtract(CMSyncConvertTime(pts, from: clock, to: CMClockGetHostTimeClock()), pts)
        for k in timing.indices {
            timing[k].presentationTimeStamp = CMTimeAdd(timing[k].presentationTimeStamp, shift)
            if timing[k].decodeTimeStamp.isValid { timing[k].decodeTimeStamp = CMTimeAdd(timing[k].decodeTimeStamp, shift) }
        }
        var out: CMSampleBuffer?
        return CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sb, sampleTimingEntryCount: timing.count,
                                                    sampleTimingArray: &timing, sampleBufferOut: &out) == noErr ? out : nil
    }
}

enum RecorderError: Error { case nothingToRecord, writer, microphone }
