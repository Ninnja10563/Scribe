#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum NoteProjection {
    static func attachment(_ note: NumberedNote, baseFont: NSFont) -> NSTextAttachment {
        let font = NSFont(descriptor: baseFont.fontDescriptor, size: max(6, baseFont.pointSize * 0.7)) ?? .systemFont(ofSize: 8)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let number = String(note.number) as NSString
        let size = number.size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: ceil(size.width) + 1, height: ceil(size.height)), flipped: false) { rect in
            number.draw(at: rect.origin, withAttributes: attributes); return true
        }
        let label = "\(note.note.kind == .footnote ? "Footnote" : "Endnote") \(note.number)"
        image.accessibilityDescription = label
        let attachment = NSTextAttachment()
        let cell = NoteReferenceCell(imageCell: image); cell.rise = baseFont.pointSize * 0.3
        cell.setAccessibilityLabel(label); attachment.attachmentCell = cell
        return attachment
    }
}
private final class NoteReferenceCell: NSTextAttachmentCell {
    var rise: CGFloat = 0
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: rise) }
}
#endif
