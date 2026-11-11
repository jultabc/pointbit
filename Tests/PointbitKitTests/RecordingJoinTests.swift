// The picture and the sound are written apart and joined at the end; a failed sound keeps the video.
import AVFoundation
import Foundation
import Testing
@testable import PointbitKit

struct RecordingJoinTests {
    /// A 1 s, 64 × 64 video of 30 frames at `url`.
    private func video(at url: URL) async throws {
        let w = try AVAssetWriter(outputURL: url, fileType: .mov)
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                                                                       AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let f = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: nil)
        w.add(i); #expect(w.startWriting()); w.startSession(atSourceTime: .zero)
        for n in 0..<30 {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pb)
            try await ready(i)
            f.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(n), timescale: 30))
        }
        i.markAsFinished(); w.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
        await w.finishWriting()
        #expect(w.status == .completed)
    }

    /// Waits for `i`, at most 2 s (a failed writer never gets ready).
    private func ready(_ i: AVAssetWriterInput) async throws {
        for _ in 0..<2000 where !i.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        try #require(i.isReadyForMoreMediaData)
    }

    /// 1 s of silence as AAC at `url` (a .mov, like the recorder's part), starting `late` s after the session start.
    private func sound(at url: URL, late: Double = 0) async throws {
        let w = try AVAssetWriter(outputURL: url, fileType: RecordingJoin.partType)   // as the recorder writes it
        let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                                       AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1])
        w.add(i); #expect(w.startWriting()); w.startSession(atSourceTime: .zero)
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
                                               mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        for n in 0..<48 {   // 48 buffers of 1000 samples
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: 2000, blockAllocator: nil,
                                               customBlockSource: nil, offsetToData: 0, dataLength: 2000, flags: 0, blockBufferOut: &block)
            CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: 2000)
            var sb: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: format!,
                sampleCount: 1000, presentationTimeStamp: CMTime(value: CMTimeValue(n * 1000 + Int(late * 48_000)), timescale: 48_000),
                packetDescriptions: nil, sampleBufferOut: &sb)
            try await ready(i)
            i.append(sb!)
        }
        i.markAsFinished(); w.endSession(atSourceTime: CMTime(seconds: 1 + late, preferredTimescale: 48_000))
        await w.finishWriting()
        #expect(w.status == .completed)
    }

    private func folder() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pointbit-join-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func tracks(_ url: URL, _ type: AVMediaType) async throws -> Int {
        try await AVURLAsset(url: url).loadTracks(withMediaType: type).count
    }

    @Test func goodSoundIsJoinedIntoTheRecording() async throws {
        let d = try folder(); defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("TACS-1.mov"), (v, s) = RecordingJoin.parts(of: url)
        try await video(at: v); try await sound(at: s)
        let has = await RecordingJoin.finish(url, videoDone: true, soundDone: true)
        let pictures = try await tracks(url, .video), sounds = try await tracks(url, .audio)
        #expect(has == true && pictures == 1 && sounds == 1)
        #expect(!FileManager.default.fileExists(atPath: v.path) && !FileManager.default.fileExists(atPath: s.path), "parts removed")
    }

    @Test func aLateSoundStaysWhereItWas() async throws {
        // The microphone starts after the first frame; the voice must not move to the start.
        let d = try folder(); defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("TACS-6.mov"), (v, s) = RecordingJoin.parts(of: url)
        try await video(at: v); try await sound(at: s, late: 0.5)
        let has = await RecordingJoin.finish(url, videoDone: true, soundDone: true)
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first)
        let segments = try await track.load(.segments)
        let start = segments.first { !$0.isEmpty }.map { CMTimeGetSeconds($0.timeMapping.target.start) }
        #expect(has == true && start.map { abs($0 - 0.5) < 0.05 } == true, "sound starts at \(start ?? -1) s, not 0.5")
    }

    @Test func aFailedSoundKeepsTheVideoWithoutIt() async throws {
        let d = try folder(); defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("TACS-2.mov"), (v, s) = RecordingJoin.parts(of: url)
        try await video(at: v)
        try Data("broken".utf8).write(to: s)   // what a failed sound writer leaves
        let has = await RecordingJoin.finish(url, videoDone: true, soundDone: false)
        let pictures = try await tracks(url, .video), sounds = try await tracks(url, .audio)
        #expect(has == false && pictures == 1 && sounds == 0)
        #expect(!FileManager.default.fileExists(atPath: s.path))
    }

    @Test func anUnreadableSoundStillKeepsTheVideo() async throws {
        let d = try folder(); defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("TACS-3.mov"), (v, s) = RecordingJoin.parts(of: url)
        try await video(at: v)
        try Data("broken".utf8).write(to: s)
        let has = await RecordingJoin.finish(url, videoDone: true, soundDone: true)
        let pictures = try await tracks(url, .video)
        #expect(has == false && pictures == 1, "the join fails, the video stays")
    }

    @Test func aVideoThatCannotBePutInPlaceIsKept() async throws {
        // The final name is taken (another app wrote it meanwhile): the finished video must stay.
        let d = try folder(); defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("TACS-5.mov"), (v, s) = RecordingJoin.parts(of: url)
        try await video(at: v); try await sound(at: s)
        try Data("someone else".utf8).write(to: url)
        let has = await RecordingJoin.finish(url, videoDone: true, soundDone: true)
        #expect(has == nil)
        #expect(FileManager.default.fileExists(atPath: v.path) && FileManager.default.fileExists(atPath: s.path), "both parts kept")
        #expect(try Data(contentsOf: url) == Data("someone else".utf8), "the other file is not touched")
    }

    @Test func partsLeftByAQuitAreRecoveredAtTheirName() async throws {
        let d = try folder(); defer { try? FileManager.default.removeItem(at: d) }
        let lost = d.appendingPathComponent("TACS-7.mov"), done = d.appendingPathComponent("TACS-8.mov")
        try await video(at: RecordingJoin.parts(of: lost).video); try await sound(at: RecordingJoin.parts(of: lost).sound)
        try await video(at: RecordingJoin.parts(of: done).video); try Data("finished".utf8).write(to: done)
        #expect(RecordingJoin.leftovers(in: d) == [lost], "a recording that is already there is not a leftover")
        let back = await RecordingJoin.recover(RecordingJoin.leftovers(in: d))
        let sounds = try await tracks(lost, .audio)
        #expect(back == [lost] && sounds == 1 && RecordingJoin.leftovers(in: d).isEmpty)
    }

    @Test func aVideoPartCutOffWhileWritingIsLeftAlone() async throws {
        // The app died while writing: the part has no index; recovering it made an unplayable
        // recording and removed the sound part.
        let d = try folder(); defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("TACS-9.mov"), (v, s) = RecordingJoin.parts(of: url)
        try await video(at: v)
        let whole = try Data(contentsOf: v)
        try whole.prefix(whole.count / 2).write(to: v)   // cut off: no moov
        try Data("half a sound".utf8).write(to: s)
        let back = await RecordingJoin.recover(RecordingJoin.leftovers(in: d))
        #expect(back.isEmpty && !FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: v.path) && FileManager.default.fileExists(atPath: s.path), "parts left as they are")
    }

    @Test func noVideoLeavesNothing() async throws {
        let d = try folder(); defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("TACS-4.mov"), (v, s) = RecordingJoin.parts(of: url)
        try Data().write(to: v); try Data().write(to: s)
        let has = await RecordingJoin.finish(url, videoDone: false, soundDone: false)
        #expect(has == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path).isEmpty)
    }
}
