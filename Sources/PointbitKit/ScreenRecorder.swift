// Records part of a display to a .mov file with ScreenCaptureKit and AVAssetWriter (video only, no audio).
// The whole display is captured and cropped to the plan's rect, so Pointbit's click marks are in the video.
// Main actor, except the frame callback, which runs on `queue`; writer state is only touched on `queue`.
import AVFoundation
import AppKit
import ScreenCaptureKit

@MainActor
final class ScreenRecorder: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private(set) var url: URL?
    private nonisolated let queue = DispatchQueue(label: "Pointbit.recorder")
    // On `queue` only.
    private nonisolated(unsafe) var writer: AVAssetWriter?
    private nonisolated(unsafe) var input: AVAssetWriterInput?
    private nonisolated(unsafe) var started = false

    /// Starts recording `area` (Cocoa global rect) on `screen` into `url`. Throws when ScreenCaptureKit or the
    /// writer refuses (for example without Screen Recording permission); then no file is left.
    func start(area: CGRect, screen: NSScreen, url: URL) async throws {
        guard stream == nil else { return }
        guard let plan = RecordingPlan(area: area, screen: screen.frame, scale: screen.backingScaleFactor),
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
        let w = try AVAssetWriter(outputURL: url, fileType: .mov)
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec, AVVideoWidthKey: plan.width, AVVideoHeightKey: plan.height])
        i.expectsMediaDataInRealTime = true
        guard w.canAdd(i) else { throw RecorderError.writer }
        w.add(i)
        guard w.startWriting() else { throw w.error ?? RecorderError.writer }

        let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: nil)
        queue.sync { writer = w; input = i; started = false }
        do {
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await s.startCapture()
        } catch {   // nothing recorded: drop the writer and its file
            queue.sync { writer = nil; input = nil }
            w.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        stream = s; self.url = url
    }

    /// Stops and finishes the file. Returns the file when it was written.
    func stop() async -> URL? {
        guard let s = stream else { return nil }
        stream = nil
        try? await s.stopCapture()
        // Frames come only when the screen changes: end the session now, not at the last changed frame,
        // so a still screen at the end stays in the video.
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        let (w, i, hadFrames) = queue.sync { () -> (AVAssetWriter?, AVAssetWriterInput?, Bool) in
            let r = (writer, input, started); writer = nil; input = nil; return r
        }
        guard let w, let i else { return nil }
        i.markAsFinished()
        guard hadFrames else { w.cancelWriting(); try? FileManager.default.removeItem(at: w.outputURL); return nil }
        w.endSession(atSourceTime: end)
        await w.finishWriting()
        return w.status == .completed ? w.outputURL : nil
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let w = writer, let i = input, sb.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete   // skip idle frames
        else { return }
        if !started { w.startSession(atSourceTime: sb.presentationTimeStamp); started = true }
        if i.isReadyForMoreMediaData { i.append(sb) }
    }
}

enum RecorderError: Error { case nothingToRecord, writer }
