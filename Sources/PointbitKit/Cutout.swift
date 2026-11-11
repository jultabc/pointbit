// ⌘ ⌘ R: a picture of the window under the pointer with its background removed (the subject only, on a
// transparent background). Vision's foreground mask, on this Mac (macOS 14 or later; earlier R is not a shortcut: it goes on to the front app).
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

enum Cutout {
    /// Whether this Mac can remove backgrounds.
    static var isAvailable: Bool { if #available(macOS 14, *) { return true } else { return false } }

    /// Each subject's extent in Vision's instance mask, as a share of the picture (0…1, top-left origin).
    static func extents(in mask: CVPixelBuffer) -> [Int: CGRect] {
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
        CVPixelBufferLockBaseAddress(mask, .readOnly); defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask), w > 0, h > 0 else { return [:] }
        let row = CVPixelBufferGetBytesPerRow(mask)
        var lo: [Int: (Int, Int)] = [:], hi: [Int: (Int, Int)] = [:]
        for y in 0..<h {
            for x in 0..<w {
                let label = Int(base.load(fromByteOffset: y * row + x, as: UInt8.self))
                guard label > 0 else { continue }
                let l = lo[label] ?? (x, y), u = hi[label] ?? (x, y)
                lo[label] = (min(l.0, x), min(l.1, y)); hi[label] = (max(u.0, x), max(u.1, y))
            }
        }
        return lo.reduce(into: [:]) { out, e in
            let u = hi[e.key]!
            out[e.key] = CGRect(x: CGFloat(e.value.0) / CGFloat(w), y: CGFloat(e.value.1) / CGFloat(h),
                                width: CGFloat(u.0 - e.value.0 + 1) / CGFloat(w), height: CGFloat(u.1 - e.value.1 + 1) / CGFloat(h))
        }
    }

    /// The subject number under `p` (share of the picture, top-left origin) in Vision's instance mask, or nil
    /// for the background or a point outside.
    static func instance(in mask: CVPixelBuffer, at p: CGPoint) -> Int? {
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
        guard let (x, y) = pixel(at: p, width: w, height: h) else { return nil }
        CVPixelBufferLockBaseAddress(mask, .readOnly); defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let label = Int(base.load(fromByteOffset: y * CVPixelBufferGetBytesPerRow(mask) + x, as: UInt8.self))
        return label > 0 ? label : nil
    }

    /// The pixel at `p` (share of the picture, 0…1, top-left origin) in a `width` × `height` grid; nil outside.
    static func pixel(at p: CGPoint, width: Int, height: Int) -> (Int, Int)? {
        guard p.x >= 0, p.x < 1, p.y >= 0, p.y < 1, width > 0, height > 0 else { return nil }
        return (Int(p.x * CGFloat(width)), Int(p.y * CGFloat(height)))
    }

    /// The pointer as a share of a captured window (`frame`, Cocoa screen coordinates): top-left origin; nil outside.
    static func share(of pointer: CGPoint, in frame: CGRect) -> CGPoint? {
        guard frame.width > 0, frame.height > 0, frame.contains(pointer) else { return nil }
        return CGPoint(x: (pointer.x - frame.minX) / frame.width, y: (frame.maxY - pointer.y) / frame.height)
    }

    /// The source picture's dpi, as image properties for the new file (nil when it has none).
    static func density(_ source: CGImageSource) -> CFDictionary? {
        guard let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyDPIWidth], let h = p[kCGImagePropertyDPIHeight] else { return nil }
        return [kCGImagePropertyDPIWidth: w, kCGImagePropertyDPIHeight: h] as CFDictionary
    }

    /// Writes `image` as a PNG file at `url`, with `properties` (the dpi).
    static func writePNG(_ image: CGImage, _ url: URL, _ properties: CFDictionary?) -> Bool {
        guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(out, image, properties)
        return CGImageDestinationFinalize(out)
    }
}

/// One picture and the subjects Vision found in it, kept so that one can be picked (⌘ ⌘ R's picker) and cut later.
@available(macOS 14, *)
final class CutoutScene: @unchecked Sendable {   // not changed after init
    let size: CGSize   // pixels
    /// Each subject's extent, as a share of the picture (0…1, top-left origin).
    let extents: [Int: CGRect]
    /// The lines of text in the picture (TextCut).
    let texts: [CutoutText]
    private let source: CGImageSource
    private let image: CGImage
    private let handler: VNImageRequestHandler
    private let result: VNInstanceMaskObservation?   // nil when there is text but no subject

    /// Nil when the picture cannot be read, or has neither a subject nor text.
    init?(_ url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest(), handler = VNImageRequestHandler(cgImage: image)
        let found = (try? handler.perform([request])) != nil ? request.results?.first : nil
        result = found.flatMap { $0.allInstances.isEmpty ? nil : $0 }
        texts = TextCut.lines(in: image)
        guard result != nil || !texts.isEmpty else { return nil }
        self.source = source; self.image = image; self.handler = handler
        size = CGSize(width: image.width, height: image.height)
        extents = result.map { Cutout.extents(in: $0.instanceMask) } ?? [:]
    }

    /// Whether there is a subject (not only text).
    var hasSubjects: Bool { result != nil }

    /// The subject under `p` (share of the picture, top-left origin), or nil for the background.
    func subject(at p: CGPoint) -> Int? { result.flatMap { Cutout.instance(in: $0.instanceMask, at: p) } }

    /// The line of text under `p`, if any.
    func text(at p: CGPoint) -> Int? { TextCut.line(at: p, in: texts) }

    /// Writes line `text` with its background colour taken out to `url` (a new file).
    func cutText(_ text: Int, into url: URL) -> Bool {
        guard texts.indices.contains(text), let cut = TextCut.cut(image, box: texts[text].box) else { return false }
        return Cutout.writePNG(cut, url, Cutout.density(source))
    }

    /// What `subject` covers (nil: every subject), as a share of the picture.
    func extent(of subject: Int?) -> CGRect? {
        guard let subject else { return extents.values.reduce(nil) { $0?.union($1) ?? $1 } }
        return extents[subject]
    }

    /// Writes `subject` (nil: every subject) on a transparent background, cropped to it, to `url`. The new picture
    /// is written to a temporary file next to it first and swapped in only when complete, so on false a file
    /// already at `url` is unchanged.
    func cut(_ subject: Int?, into url: URL, write: (CGImage, URL, CFDictionary?) -> Bool = Cutout.writePNG) -> Bool {
        guard let result else { return false }
        let picked = subject.map { IndexSet(integer: $0) } ?? result.allInstances
        guard let masked = try? result.generateMaskedImage(ofInstances: picked, from: handler, croppedToInstancesExtent: true)
        else { return false }
        let ci = CIImage(cvPixelBuffer: masked)
        guard let cut = CIContext().createCGImage(ci, from: ci.extent) else { return false }
        // Keep the picture's pixel density (a Retina capture is 144 dpi), so it shows at its real size.
        let temp = url.deletingLastPathComponent().appendingPathComponent(".pointbit-cut-\(UUID().uuidString).png")
        guard write(cut, temp, Cutout.density(source)) else { try? FileManager.default.removeItem(at: temp); return false }
        if FileManager.default.fileExists(atPath: url.path) {
            do { _ = try FileManager.default.replaceItemAt(url, withItemAt: temp) }
            catch { try? FileManager.default.removeItem(at: temp); return false }
        } else {
            do { try FileManager.default.moveItem(at: temp, to: url) } catch { try? FileManager.default.removeItem(at: temp); return false }
        }
        return true
    }
}
