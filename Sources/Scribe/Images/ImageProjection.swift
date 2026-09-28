#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum ImageProjection {
    static func attachment(_ image: InlineImage) -> NSTextAttachment? {
        guard let bitmap = NSImage(data: image.data) else { return nil }
        bitmap.size = NSSize(width: image.width, height: image.height)
        bitmap.accessibilityDescription = image.altText
        let wrapper = FileWrapper(regularFileWithContents: image.data)
        wrapper.preferredFilename = "\(image.id).\(image.fileExtension)"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: bitmap)
        return attachment
    }
    static func image(from data: Data, maximumWidth: Double, maximumHeight: Double, altText: String = "") throws -> InlineImage {
        guard data.count <= 32 * 1024 * 1024, let image = NSImage(data: data), image.size.width > 0, image.size.height > 0,
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { throw DocumentError.invalid("could not read the image") }
        let scale = min(1, maximumWidth / image.size.width, maximumHeight / image.size.height)
        return InlineImage(data: png, fileExtension: "png", width: image.size.width * scale, height: image.size.height * scale, altText: altText)
    }
}
#endif
