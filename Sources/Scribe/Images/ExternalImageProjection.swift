#if canImport(AppKit)
import AppKit
import DocumentCore

/// RTFD has no reversible crop/rotation model. Bake only the external copy, never editor storage.
@MainActor enum ExternalImageProjection {
    static func render(_ value: NSAttributedString) throws -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        var replacements: [(NSRange, NSTextAttachment)] = []
        var failure: Error?
        value.enumerateAttribute(.scribeImage, in: NSRange(location: 0, length: value.length)) { encoded, range, stop in
            guard let data = encoded as? Data, let image = try? JSONDecoder().decode(InlineImage.self, from: data), image.adjustments != nil else { return }
            do { replacements.append((range, try flattenedAttachment(image))) }
            catch { failure = error; stop.pointee = true }
        }
        if let failure { throw failure }
        for (range, attachment) in replacements { result.addAttribute(.attachment, value: attachment, range: range) }
        result.removeAttribute(.scribeImage, range: NSRange(location: 0, length: result.length))
        return result
    }
    static func flattenedAttachment(_ image: InlineImage) throws -> NSTextAttachment {
        guard let attachment = ImageProjection.attachment(image), let cell = attachment.attachmentCell as? NSTextAttachmentCell, let bitmap = cell.image else { throw DocumentError.invalid("could not prepare the image for rich-text copying") }
        // External copies use 144 dpi, limited to 16 million pixels. Native/PDF/DOCX retain source resolution.
        let scale = min(2, sqrt(16_000_000 / (image.width * image.height)))
        let width = max(1, Int((image.width * scale).rounded())), height = max(1, Int((image.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: rep) else { throw DocumentError.invalid("could not allocate the rich-text image") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        bitmap.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = NSSize(width: image.width, height: image.height)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw DocumentError.invalid("could not encode the rich-text image") }
        let wrapper = FileWrapper(regularFileWithContents: data); wrapper.preferredFilename = UUID().uuidString + ".png"
        let result = NSTextAttachment(fileWrapper: wrapper)
        result.attachmentCell = NSTextAttachmentCell(imageCell: bitmap)
        return result
    }
}
#endif
