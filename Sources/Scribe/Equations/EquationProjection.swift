#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum EquationProjection {
    static func warning(in editor: PaginatedEditor) -> String? {
        var warning: String?
        editor.storage.enumerateAttribute(.scribeEquation, in: NSRange(location: 0, length: editor.storage.length)) { value, range, stop in
            guard value != nil, let attachment = editor.storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
                  let cell = attachment.attachmentCell else { return }
            let glyph = editor.layout.glyphIndexForCharacter(at: range.location)
            guard glyph < editor.layout.numberOfGlyphs else { return }
            editor.layout.ensureLayout(forGlyphRange: NSRange(location: glyph, length: 1))
            let line = editor.layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let size = cell.cellSize()
            if (cell as? EquationAttachmentCell)?.exceedsDisplayLimit == true || size.width > line.width + 0.5 || size.height > editor.canvas.pageSettings.contentHeight - 1 {
                warning = "An equation is larger than its writing area. Reduce its size or widen the paragraph or table cell before PDF export or printing."
                stop.pointee = true
            }
        }
        return warning
    }
    static func attachment(_ equation: Equation) -> NSTextAttachment {
        let layout = EquationLayout(equation: equation)
        let padding: CGFloat = 2
        let exceedsDisplayLimit = layout.width > 4000 || layout.height > 4000 || layout.width * layout.height > 16_000_000
        let imageSize = exceedsDisplayLimit ? NSSize(width: 320, height: 32) : NSSize(width: max(1, layout.width + 2 * padding), height: max(1, layout.height + 2 * padding))
        let image = NSImage(size: imageSize, flipped: false) { rect in
            if exceedsDisplayLimit {
                ("Equation exceeds display limits — edit its size" as NSString).draw(at: CGPoint(x: 4, y: 10), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray])
                return true
            }
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            layout.draw(in: context, baseline: CGPoint(x: rect.minX + padding, y: rect.minY + padding + layout.descent))
            return true
        }
        image.accessibilityDescription = equation.expression.accessibilityText
        let attachment = NSTextAttachment()
        let cell = EquationAttachmentCell(imageCell: image)
        cell.baselineDescent = exceedsDisplayLimit ? 0 : layout.descent + padding
        cell.exceedsDisplayLimit = exceedsDisplayLimit
        cell.setAccessibilityLabel(equation.expression.accessibilityText)
        attachment.attachmentCell = cell
        return attachment
    }
}

private final class EquationAttachmentCell: NSTextAttachmentCell {
    var baselineDescent: CGFloat = 0
    var exceedsDisplayLimit = false
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -baselineDescent) }
}
#endif
