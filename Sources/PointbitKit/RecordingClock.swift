// While recording, the menu bar shows the seconds recorded (0, 1, 2 …, no minutes, no unit) in place of its icon
// as one number. One change of the title a second; the digits keep one width, so the item does not jitter.
import AppKit

@MainActor
final class RecordingClock {
    private var timer: Timer?, began = Date(), shown = -1
    private weak var item: NSStatusItem?

    /// Whole seconds from `began` to `now`, never below 0 (the clock going back).
    nonisolated static func seconds(from began: Date, to now: Date) -> Int { max(0, Int(now.timeIntervalSince(began))) }

    /// Shows the count in `item` from 0, in place of its icon.
    func start(in item: NSStatusItem) {
        stop()
        self.item = item; began = Date(); shown = -1
        item.length = NSStatusItem.variableLength
        item.button?.image = nil
        tick()
        // Twice a second, so a second is never skipped when a tick comes a little late.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(t, forMode: .common)   // also while the menu is open
        timer = t
    }

    /// Back to the icon `image`.
    func stop(showing image: NSImage? = nil) {
        timer?.invalidate(); timer = nil
        guard let item else { return }
        item.button?.attributedTitle = NSAttributedString(string: "")
        item.button?.setAccessibilityLabel(nil)   // back to the icon's own description
        item.button?.image = image
        item.length = NSStatusItem.squareLength
        self.item = nil
    }

    private func tick() {
        let s = Self.seconds(from: began, to: Date())
        guard s != shown, let button = item?.button else { return }
        shown = s
        // The menu bar's own text colour (white on a dark bar, black on a light one): a red number was hard to read
        // in the menu bar.
        button.attributedTitle = NSAttributedString(string: "\(s)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)])
        button.setAccessibilityLabel("\(appName) — recording, \(s) seconds")
    }
}
