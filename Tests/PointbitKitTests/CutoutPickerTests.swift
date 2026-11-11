// ⌘ ⌘ R while the picture is still being taken cancels it, and the late result is dropped.
import Foundation
import Testing
@testable import PointbitKit

@MainActor
struct CutoutPickerTests {
    @Test func aSecondKeyWhilePreparingCancelsAndTheLateResultIsDropped() async throws {
        guard #available(macOS 14, *) else { return }
        let picker = CutoutPicker()
        var finishTaking: (@Sendable (Bool) -> Void)?
        var taken: URL?
        picker.takePicture = { _, url, done in taken = url; finishTaking = done }   // not taken yet
        var saved = false
        picker.open(window: 1, frame: .zero) { _, _, _ in saved = true }
        #expect(picker.isBusy && !picker.isOpen, "preparing")
        picker.confirm()   // what ⌘ ⌘ R does while busy (WindowShot)
        #expect(!picker.isBusy, "cancelled")
        let url = try #require(taken)
        try Data("picture".utf8).write(to: url)
        finishTaking?(true)   // the picture arrives late
        try await Task.sleep(nanoseconds: 300_000_000)   // the main-queue hop after Vision
        #expect(!picker.isOpen && !saved, "nothing opens, nothing is saved")
        #expect(!FileManager.default.fileExists(atPath: url.path), "the late picture is removed")
    }

    @Test func aLateFirstRoundDoesNotTouchTheSecond() async throws {
        guard #available(macOS 14, *) else { return }
        let picker = CutoutPicker()
        var rounds: [(URL, @Sendable (Bool) -> Void)] = []
        picker.takePicture = { _, url, done in rounds.append((url, done)) }
        picker.open(window: 1, frame: CGRect(x: 0, y: 0, width: 200, height: 100)) { _, _, _ in }
        picker.confirm()   // cancel the first while preparing
        picker.open(window: 1, frame: CGRect(x: 0, y: 0, width: 200, height: 100)) { _, _, _ in }
        #expect(rounds.count == 2 && picker.isBusy)
        try Data("first".utf8).write(to: rounds[0].0)
        rounds[0].1(true)   // the first round's late result
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(picker.isBusy, "the second round goes on")
        #expect(picker.isPreparing, "and still shows that it is preparing")
        #expect(!FileManager.default.fileExists(atPath: rounds[0].0.path))
        picker.cancel()
    }
}
