#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum ExternalEquationProjection {
    /// Standard rich-text recipients receive a visible PNG; Scribe's parallel JSON
    /// clipboard representation retains the original mathematical source.
    static func render(_ value: NSAttributedString) throws -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        var failure: Error?
        value.enumerateAttribute(.scribeEquation, in: NSRange(location: 0, length: value.length)) { data, range, stop in
            guard let data = data as? Data, let equation = try? JSONDecoder().decode(Equation.self, from: data) else { return }
            do { result.addAttribute(.attachment, value: try flattenedAttachment(equation), range: range) }
            catch { failure = error; stop.pointee = true }
        }
        if let failure { throw failure }
        result.removeAttribute(.scribeEquation, range: NSRange(location: 0, length: result.length))
        return result
    }
    static func flattenedAttachment(_ equation: Equation) throws -> NSTextAttachment {
        let layout = EquationLayout(equation: equation)
        let width = layout.width + 4, height = layout.height + 4
        guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 16000, height <= 16000 else { throw DocumentError.invalid("equation is too large for rich-text copying") }
        let scale = min(2, sqrt(16_000_000 / (width * height)))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: max(1, Int(ceil(width * scale))), pixelsHigh: max(1, Int(ceil(height * scale))), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw DocumentError.invalid("could not allocate equation clipboard image") }
        context.cgContext.scaleBy(x: scale, y: scale)
        layout.draw(in: context.cgContext, baseline: CGPoint(x: 2, y: 2 + layout.descent))
        bitmap.size = NSSize(width: width, height: height)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw DocumentError.invalid("could not encode equation clipboard image") }
        let wrapper = FileWrapper(regularFileWithContents: data); wrapper.preferredFilename = UUID().uuidString + ".png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let image = NSImage(size: bitmap.size); image.addRepresentation(bitmap)
        image.accessibilityDescription = equation.expression.accessibilityText
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        return attachment
    }
}
#endif
