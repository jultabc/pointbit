// Transcript text: lines by pause and sentence end, times as mm:ss.
import Foundation
import Testing
@testable import PointbitKit

struct TranscriptTests {
    @Test func linesBreakAtPausesAndSentenceEnds() {
        let pieces = [
            SpokenPiece(start: 0.5, duration: 0.4, text: "여기"),
            SpokenPiece(start: 1.0, duration: 0.5, text: "버튼이"),
            SpokenPiece(start: 1.6, duration: 0.5, text: "안"),
            SpokenPiece(start: 2.2, duration: 0.6, text: "눌려요."),      // sentence end
            SpokenPiece(start: 3.0, duration: 0.5, text: "그리고"),
            SpokenPiece(start: 65.0, duration: 0.5, text: "끝"),          // after a long pause
            SpokenPiece(start: 66.0, duration: 0.1, text: ""),            // empty pieces are skipped
        ]
        #expect(Transcript.lines(pieces) == "[00:00] 여기 버튼이 안 눌려요.\n[00:03] 그리고\n[01:05] 끝\n")
    }

    @Test func nothingSaidIsEmpty() {
        #expect(Transcript.lines([]) == "")
        #expect(Transcript.lines([SpokenPiece(start: 1, duration: 1, text: "")]) == "")
    }

    @Test func aFailedPartIsMarkedNotSkipped() {
        let parts: [PartResult] = [
            .heard([SpokenPiece(start: 10, duration: 1, text: "첫 조각.")]),
            .failed(start: 50, end: 100),
            .silent,
            .heard([SpokenPiece(start: 151, duration: 1, text: "셋째")]),
        ]
        #expect(Transcript.lines(Transcript.pieces(parts)) ==
                "[00:10] 첫 조각.\n[00:50] (not recognized: 00:50–01:40)\n[02:31] 셋째\n")
    }

    @Test func aGapBreaksTheLineAroundIt() {
        let pieces = [SpokenPiece(start: 0, duration: 0.5, text: "말"),
                      SpokenPiece(start: 0.6, duration: 50, text: "(not recognized: 00:00–00:50)", gap: true),
                      SpokenPiece(start: 50.7, duration: 0.5, text: "이어서")]
        #expect(Transcript.lines(pieces) == "[00:00] 말\n[00:00] (not recognized: 00:00–00:50)\n[00:50] 이어서\n")
    }

    @Test func aReadErrorMarksTheRestOfTheTrack() {
        let read: [PartResult] = [.heard([SpokenPiece(start: 1, duration: 1, text: "앞")])]
        #expect(Transcript.finished(read, completed: true, readTo: 30, total: 30) == read, "completed: nothing added")
        #expect(Transcript.finished(read, completed: false, readTo: 30, total: 120) == read + [.failed(start: 30, end: 120)],
                "stopped at 0:30 of 2:00: the rest is marked")
    }

    @Test func neighbouringFailuresJoin() {
        var parts: [PartResult] = []
        Transcript.addFailure(&parts, start: 10, end: 10.02)
        Transcript.addFailure(&parts, start: 10.02, end: 10.04)
        #expect(parts == [.failed(start: 10, end: 10.04)], "two short unreadable buffers in a row: one line")
        Transcript.addFailure(&parts, start: 20, end: 21)
        #expect(parts.count == 2, "a later failure is its own line")
    }

    @Test func resultsPerSentenceAreAllKept() {
        // macOS on long sound: one result per sentence (seen 2026-11-02: only the last word was kept before).
        var heard: [SpokenPiece] = []
        heard = Transcript.merge(heard, with: [SpokenPiece(start: 1, duration: 1, text: "첫"), SpokenPiece(start: 2, duration: 1, text: "문장.")])
        heard = Transcript.merge(heard, with: [SpokenPiece(start: 10, duration: 1, text: "둘째.")])
        #expect(heard.map(\.text) == ["첫", "문장.", "둘째."])
    }

    @Test func aGrowingResultReplacesWhatItCovers() {
        var heard = Transcript.merge([], with: [SpokenPiece(start: 1, duration: 1, text: "여기")])
        heard = Transcript.merge(heard, with: [SpokenPiece(start: 1, duration: 1, text: "여기"), SpokenPiece(start: 2, duration: 1, text: "버튼")])
        #expect(heard.map(\.text) == ["여기", "버튼"], "no word twice")
        #expect(Transcript.merge(heard, with: []) == heard)
    }

    @Test func dictationOffSaysWhatToDo() {
        let off = NSError(domain: "kLSRErrorDomain", code: 201)
        #expect(Transcript.why(off).contains("Dictation"))
        #expect(Transcript.why(NSError(domain: "x", code: 1)) == "")
        #expect(Transcript.lines(Transcript.pieces([.failed(start: 0, end: 50, why: Transcript.why(off))])) ==
                "[00:00] (not recognized: 00:00–00:50 — turn on Dictation: System Settings → Keyboard → Dictation)\n")
    }

    @Test func soundFileTimesMoveIntoVideoTime() {
        // The new engine counts from the first sound sample; a track that starts 3 s in is 3 s late.
        let p = [SpokenPiece(start: 0, duration: 1, text: "첫"), SpokenPiece(start: 2, duration: 1, text: "말.")]
        #expect(Transcript.shifted(p, by: 3).map(\.start) == [3, 5])
        #expect(Transcript.lines(Transcript.shifted(p, by: 3)) == "[00:03] 첫 말.\n")
        #expect(Transcript.shifted(p, by: 0) == p)
    }

    @Test func timeLimitSurvivesStrangeLengths() {
        // AVAsset duration can be NaN or infinite; UInt64(NaN) would stop the app.
        #expect(Transcript.timeLimit(60) == 210)
        for bad in [Double.nan, .infinity, -.infinity, -5] { #expect(Transcript.timeLimit(bad) == 30, "\(bad) counts as 0") }
        #expect(Transcript.timeLimit(1e12) == 86_400, "at most one day")
        #expect(Transcript.nanoseconds(1.5) == 1_500_000_000)
        #expect(Transcript.nanoseconds(.nan) == 0 && Transcript.nanoseconds(-1) == 0 && Transcript.nanoseconds(.infinity) == 0)
        #expect(Transcript.nanoseconds(1e30) == UInt64.max)
    }

    @Test func withinAnswersOnceAndStopsAtTheLimit() async {
        // The time-limit path had no test.
        let quick = await Transcript.within(5, "test") { 7 }
        #expect(quick == 7, "a quick result comes back")
        let failed: Int? = await Transcript.within(5, "test") { throw CancellationError() }
        #expect(failed == nil, "an error gives nil")
        let start = Date()
        let slow: Int? = await Transcript.within(0.2, "test") { try await Task.sleep(nanoseconds: 5_000_000_000); return 1 }
        #expect(slow == nil, "past the limit gives nil")
        #expect(Date().timeIntervalSince(start) < 2, "answered at the limit, not when the work ends")
    }

    @Test func clock() {
        #expect(Transcript.clock(0) == "00:00")
        #expect(Transcript.clock(59.9) == "00:59")
        #expect(Transcript.clock(61) == "01:01")
        #expect(Transcript.clock(3725) == "1:02:05")
        #expect(Transcript.clock(-3) == "00:00")
        #expect(Transcript.clock(.nan) == "00:00" && Transcript.clock(.infinity) == "00:00", "no crash")
    }
}
