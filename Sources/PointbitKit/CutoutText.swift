// ⌘ ⌘ R on text: Vision's text recognizer finds the lines, the picker can choose one, and its picture is saved with
// the background colour taken out (and its text in a .txt next to it). The background colour is the line's border
// pixels' average, so this works best on a plain background.
import CoreGraphics
import Vision

/// One recognized line of text: where it is (share of the picture, 0…1, top-left origin) and what it says.
struct CutoutText: Equatable {
    var box: CGRect
    var string: String
}

enum TextCut {
    /// The lines Vision reads in `image` (Korean and English), top to bottom.
    static func lines(in image: CGImage) -> [CutoutText] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        // Language correction off, to keep codes and numbers as written. Misreadings remain either way
        // ("timing 0" read "timing O" with it on; "1l0O" read "100" with it off, another size).
        request.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { o -> CutoutText? in
            guard let s = o.topCandidates(1).first?.string, !s.isEmpty else { return nil }
            let b = o.boundingBox   // bottom-left origin
            return CutoutText(box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height), string: s)
        }.sorted { $0.box.minY < $1.box.minY }
    }

    /// The line whose box (grown by `slack` of its height) holds `p`; the smallest when boxes overlap.
    static func line(at p: CGPoint, in texts: [CutoutText], slack: CGFloat = 0.2) -> Int? {
        texts.indices.filter { i in
            let b = texts[i].box
            return b.insetBy(dx: -b.height * slack, dy: -b.height * slack).contains(p)
        }.min { texts[$0].box.width * texts[$0].box.height < texts[$1].box.width * texts[$1].box.height }
    }

    /// `image` cropped to `box` (share, top-left origin) with a margin of a third of its height, and the background
    /// colour made transparent: alpha grows from 0 at `near` of the largest colour distance to 1 at `far`.
    static func cut(_ image: CGImage, box: CGRect, near: CGFloat = 0.12, far: CGFloat = 0.35) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height), m = box.height * h / 3
        let r = CGRect(x: box.minX * w - m, y: box.minY * h - m, width: box.width * w + 2 * m, height: box.height * h + 2 * m)
            .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !r.isEmpty, let crop = image.cropping(to: r) else { return nil }
        let cw = crop.width, ch = crop.height
        var px = [UInt8](repeating: 0, count: cw * ch * 4)
        guard let ctx = CGContext(data: &px, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: cw, height: ch))
        keyOut(&px, width: cw, height: ch, near: near, far: far)
        return ctx.makeImage()
    }

    /// Makes the background of an RGBA (premultiplied, opaque) pixel grid transparent. The background colour is
    /// the average of the border pixels.
    static func keyOut(_ px: inout [UInt8], width w: Int, height h: Int, near: CGFloat, far: CGFloat) {
        guard w > 1, h > 1 else { return }
        var sum = (0.0, 0.0, 0.0), n = 0.0
        for y in 0..<h { for x in 0..<w where x == 0 || y == 0 || x == w - 1 || y == h - 1 {
            let i = (y * w + x) * 4
            sum.0 += Double(px[i]); sum.1 += Double(px[i + 1]); sum.2 += Double(px[i + 2]); n += 1
        } }
        let bg = (sum.0 / n, sum.1 / n, sum.2 / n), maxD = 255 * 3.0.squareRoot()
        for i in stride(from: 0, to: px.count, by: 4) {
            let d = ((Double(px[i]) - bg.0) * (Double(px[i]) - bg.0) + (Double(px[i + 1]) - bg.1) * (Double(px[i + 1]) - bg.1)
                     + (Double(px[i + 2]) - bg.2) * (Double(px[i + 2]) - bg.2)).squareRoot() / maxD
            let a = min(1, max(0, (d - Double(near)) / Double(far - near)))
            // Premultiplied: colour scales with alpha.
            px[i] = UInt8(Double(px[i]) * a); px[i + 1] = UInt8(Double(px[i + 1]) * a); px[i + 2] = UInt8(Double(px[i + 2]) * a)
            px[i + 3] = UInt8(255 * a)
        }
    }
}
