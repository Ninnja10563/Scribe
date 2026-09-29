#if canImport(AppKit)
import AppKit
import ImageIO
import DocumentCore

@MainActor enum ImageProjection {
    static func attachment(_ image: InlineImage, forceInline: Bool = false) -> NSTextAttachment? {
        if image.placement != nil, !forceInline {
            let wrapper = FileWrapper(regularFileWithContents: image.data)
            wrapper.preferredFilename = "\(image.id).\(image.fileExtension)"
            let attachment = NSTextAttachment(fileWrapper: wrapper)
            attachment.attachmentCell = FloatingImageAnchorCell(image)
            return attachment
        }
        let bitmap: NSImage
        if validPixelSize(image.data), let decoded = NSImage(data: image.data) {
            if let adjustments = image.adjustments {
                bitmap = NSImage(size: NSSize(width: image.width, height: image.height), flipped: false) { rect in
                    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
                    NSGraphicsContext.current?.imageInterpolation = .high
                    let transform = NSAffineTransform()
                    transform.translateX(by: rect.midX, yBy: rect.midY)
                    transform.rotate(byDegrees: -adjustments.rotation); transform.concat()
                    let size = adjustments.unrotatedSize(frameWidth: rect.width, frameHeight: rect.height)
                    let target = NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
                    let crop = adjustments.crop
                    let source = NSRect(x: decoded.size.width * crop.left, y: decoded.size.height * crop.bottom, width: decoded.size.width * crop.visibleWidth, height: decoded.size.height * crop.visibleHeight)
                    decoded.draw(in: target, from: source, operation: .sourceOver, fraction: adjustments.opacity, respectFlipped: false, hints: nil)
                    return true
                }
            } else { bitmap = decoded }
        }
        else {
            bitmap = NSImage(size: NSSize(width: image.width, height: image.height), flipped: false) { rect in
                NSColor(white: 0.94, alpha: 1).setFill(); rect.fill()
                ("Image unavailable" as NSString).draw(at: NSPoint(x: 8, y: max(4, rect.height / 2)), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray])
                return true
            }
        }
        bitmap.size = NSSize(width: image.width, height: image.height)
        bitmap.accessibilityDescription = image.altText
        let wrapper = FileWrapper(regularFileWithContents: image.data)
        wrapper.preferredFilename = "\(image.id).\(image.fileExtension)"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: bitmap)
        return attachment
    }
    static func image(from data: Data, maximumWidth: Double, maximumHeight: Double, altText: String = "") throws -> InlineImage {
        guard data.count <= 32 * 1024 * 1024, validPixelSize(data), let image = NSImage(data: data), image.size.width > 0, image.size.height > 0,
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { throw DocumentError.invalid("could not read the image") }
        let scale = min(1, maximumWidth / image.size.width, maximumHeight / image.size.height)
        return InlineImage(data: png, fileExtension: "png", width: image.size.width * scale, height: image.size.height * scale, altText: altText)
    }
    private static func validPixelSize(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return false }
        return width.doubleValue > 0 && height.doubleValue > 0 && width.doubleValue * height.doubleValue <= 64_000_000
    }
}
#endif
