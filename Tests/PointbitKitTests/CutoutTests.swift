// Background removal on a drawn picture: a subject on a plain background comes out cropped, with transparency.
import AppKit
import Foundation
import CoreVideo
import Testing
@testable import PointbitKit

struct CutoutTests {
    /// The picker's path: the scene of `url`, the subject at `at` (nil: every subject), cut into `url`.
    private func cutOut(_ url: URL, at: CGPoint? = nil, write: (CGImage, URL, CFDictionary?) -> Bool = Cutout.writePNG) -> Bool {
        guard #available(macOS 14, *), let scene = CutoutScene(url) else { return false }
        return scene.cut(at.flatMap(scene.subject(at:)), into: url, write: write)
    }

    private func ballPicture() throws -> (URL, NSBitmapImageRep) {
        let size = NSSize(width: 600, height: 400)
        let image = NSImage(size: size, flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            NSColor(srgbRed: 0.85, green: 0.2, blue: 0.15, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 220, y: 110, width: 160, height: 180)).fill()   // a red ball
            NSColor(srgbRed: 0.2, green: 0.5, blue: 0.2, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 290, y: 60, width: 20, height: 60)).fill()        // its stand
            return true
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pointbit-cutout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("TACS-test.png")
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        rep.size = NSSize(width: rep.pixelsWide / 2, height: rep.pixelsHigh / 2)   // 144 dpi, like a Retina capture
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return (url, rep)
    }

    @Test func aSubjectOnAPlainBackgroundIsCutOut() throws {
        guard Cutout.isAvailable else { return }   // macOS 13: nothing to test
        let (url, rep) = try ballPicture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        guard cutOut(url) else { Issue.record("Vision found no subject in the test picture"); return }
        let out = NSBitmapImageRep(data: try Data(contentsOf: url))!
        #expect(out.hasAlpha && out.pixelsWide < rep.pixelsWide, "transparent, cropped to the subject")
        #expect((out.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05, "a corner outside the ball is transparent")
        #expect((out.colorAt(x: out.pixelsWide / 2, y: out.pixelsHigh / 3)?.alphaComponent ?? 0) > 0.95, "the ball is kept")
        #expect(abs(out.size.width * 2 - CGFloat(out.pixelsWide)) < 1, "144 dpi kept: points = pixels / 2")
        let left = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(left == ["TACS-test.png"], "no temporary file left")
    }

    @Test func aFailedWriteKeepsTheOriginal() throws {
        // The original picture must survive a failed write.
        guard Cutout.isAvailable else { return }
        let (url, _) = try ballPicture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = try Data(contentsOf: url)
        #expect(cutOut(url, write: { _, temp, _ in try? Data("partial".utf8).write(to: temp); return false }) == false)
        #expect(try Data(contentsOf: url) == before, "original bytes unchanged")
        let left = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(left == ["TACS-test.png"], "the half-written temporary file is removed")
    }

    @Test func noSubjectKeepsThePlainPicture() throws {
        guard Cutout.isAvailable else { return }
        let image = NSImage(size: NSSize(width: 400, height: 300), flipped: false) { r in NSColor.white.setFill(); r.fill(); return true }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pointbit-cutout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("blank.png")
        try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: url)
        let before = try Data(contentsOf: url)
        #expect(cutOut(url) == false, "a blank picture has no subject")
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func theSubjectUnderThePointerIsTheOneKept() throws {
        guard Cutout.isAvailable else { return }
        // Two balls on a diagonal, red at the top left and blue at the bottom right, so a pointer read upside down
        // or mirrored lands on the other ball (or on the background).
        let image = NSImage(size: NSSize(width: 800, height: 800), flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            NSColor(srgbRed: 0.85, green: 0.2, blue: 0.15, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 80, y: 540, width: 180, height: 180)).fill()
            NSColor(srgbRed: 0.15, green: 0.35, blue: 0.85, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 540, y: 80, width: 180, height: 180)).fill()
            return true
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pointbit-cutout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        func cut(_ name: String, at point: CGPoint?) throws -> NSBitmapImageRep? {
            let url = dir.appendingPathComponent(name)
            try data.write(to: url)
            guard cutOut(url, at: point) else { return nil }
            return NSBitmapImageRep(data: try Data(contentsOf: url))
        }
        guard let both = try cut("all.png", at: nil) else { Issue.record("Vision found no subject"); return }
        // Pointer shares have a top-left origin: red's centre is at (170, 170) of 800, blue's at (630, 630).
        for (name, point, red) in [("red.png", CGPoint(x: 170.0 / 800, y: 170.0 / 800), true),
                                   ("blue.png", CGPoint(x: 630.0 / 800, y: 630.0 / 800), false)] {
            guard let one = try cut(name, at: point) else { Issue.record("\(name): nothing cut"); continue }
            guard both.pixelsWide > one.pixelsWide * 2 else {
                Issue.record("Vision saw the two balls as one subject: \(both.pixelsWide) vs \(one.pixelsWide)"); continue
            }
            #expect(one.pixelsHigh < both.pixelsHigh / 2, "\(name): only one ball")
            let centre = one.colorAt(x: one.pixelsWide / 2, y: one.pixelsHigh / 2)
            #expect(((red ? centre?.redComponent : centre?.blueComponent) ?? 0) > 0.6, "\(name): the ball under the pointer")
        }
    }

    @Test func eachSubjectsExtentComesFromTheMask() {
        // A 10 × 4 mask: subject 1 in columns 1-2 of rows 0-1, subject 2 in column 7 of row 3.
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 10, 4, kCVPixelFormatType_OneComponent8, nil, &pb)
        let mask = pb!
        CVPixelBufferLockBaseAddress(mask, [])
        let base = CVPixelBufferGetBaseAddress(mask)!, row = CVPixelBufferGetBytesPerRow(mask)
        for y in 0..<4 { for x in 0..<10 { base.storeBytes(of: 0, toByteOffset: y * row + x, as: UInt8.self) } }
        for (x, y) in [(1, 0), (2, 0), (1, 1), (2, 1)] { base.storeBytes(of: 1, toByteOffset: y * row + x, as: UInt8.self) }
        base.storeBytes(of: 2, toByteOffset: 3 * row + 7, as: UInt8.self)
        CVPixelBufferUnlockBaseAddress(mask, [])
        let e = Cutout.extents(in: mask)
        #expect(e[1] == CGRect(x: 0.1, y: 0, width: 0.2, height: 0.5))
        #expect(e[2] == CGRect(x: 0.7, y: 0.75, width: 0.1, height: 0.25) && e.count == 2)
    }

    @Test func pointerShareOfAWindow() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 200)
        #expect(Cutout.share(of: CGPoint(x: 200, y: 250), in: frame) == CGPoint(x: 0.25, y: 0.25), "top-left origin")
        #expect(Cutout.share(of: CGPoint(x: 50, y: 50), in: frame) == nil, "outside")
        #expect(Cutout.pixel(at: CGPoint(x: 0.5, y: 0.25), width: 100, height: 40)! == (50, 10))
        #expect(Cutout.pixel(at: CGPoint(x: 1, y: 0.5), width: 100, height: 40) == nil)
    }
}
