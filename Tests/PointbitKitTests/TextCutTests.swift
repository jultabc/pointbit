// ⌘ ⌘ R on text: lines found, the one under the pointer, the background colour taken out.
import AppKit
import Testing
@testable import PointbitKit

struct TextCutTests {
    @Test func thePlainBackgroundGoesAndTheInkStays() {
        // 6 × 4 white with a black 2 × 2 in the middle.
        let w = 6, h = 4
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for (x, y) in [(2, 1), (3, 1), (2, 2), (3, 2)] { let i = (y * w + x) * 4; px[i] = 0; px[i + 1] = 0; px[i + 2] = 0 }
        TextCut.keyOut(&px, width: w, height: h, near: 0.12, far: 0.35)
        #expect(px[3] == 0, "a white corner is transparent")
        #expect(px[(1 * w + 2) * 4 + 3] == 255, "the black ink is kept")
    }

    @Test func theSmallestLineUnderThePointerIsPicked() {
        let texts = [CutoutText(box: CGRect(x: 0, y: 0, width: 1, height: 0.5), string: "big"),
                     CutoutText(box: CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.05), string: "small")]
        #expect(TextCut.line(at: CGPoint(x: 0.5, y: 0.22), in: texts) == 1)
        #expect(TextCut.line(at: CGPoint(x: 0.1, y: 0.1), in: texts) == 0)
        #expect(TextCut.line(at: CGPoint(x: 0.5, y: 0.9), in: texts) == nil)
    }

    @Test func vision_readsALineOfText() throws {
        let image = NSImage(size: NSSize(width: 800, height: 200), flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            ("Pointbit 2026" as NSString).draw(at: NSPoint(x: 40, y: 60),
                                              withAttributes: [.font: NSFont.systemFont(ofSize: 72), .foregroundColor: NSColor.black])
            return true
        }
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let lines = TextCut.lines(in: cg)
        #expect(lines.contains { $0.string.contains("Pointbit") }, "read: \(lines.map(\.string))")
        let line = try #require(lines.first)
        #expect(line.box.minY > 0.2 && line.box.maxY < 0.8, "top-left origin: the line is in the middle band")
        let cut = try #require(TextCut.cut(cg, box: line.box))
        #expect(cut.width < cg.width, "cropped to the line")
    }
}
