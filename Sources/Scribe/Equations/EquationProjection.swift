#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum EquationProjection {
    static func attachment(_ equation: Equation) -> NSTextAttachment {
        let layout = EquationLayout(equation: equation)
        let padding: CGFloat = 2
        let image = NSImage(size: NSSize(width: max(1, layout.width + 2 * padding), height: max(1, layout.height + 2 * padding)), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            layout.draw(in: context, baseline: CGPoint(x: rect.minX + padding, y: rect.minY + padding + layout.descent))
            return true
        }
        image.accessibilityDescription = equation.expression.accessibilityText
        let attachment = NSTextAttachment()
        let cell = EquationAttachmentCell(imageCell: image)
        cell.baselineDescent = layout.descent + padding
        cell.setAccessibilityLabel(equation.expression.accessibilityText)
        attachment.attachmentCell = cell
        return attachment
    }
}

private final class EquationAttachmentCell: NSTextAttachmentCell {
    var baselineDescent: CGFloat = 0
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -baselineDescent) }
}
#endif
