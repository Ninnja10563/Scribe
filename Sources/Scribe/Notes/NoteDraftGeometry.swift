#if canImport(AppKit)
import AppKit
import DocumentCore

/// Draft geometry is disposable UI state. Existing objects must remain editable
/// at their authored size even when wider or taller than the compact dialog.
@MainActor enum NoteDraftGeometry {
    static func page(for document: ScribeDocument) -> PageSettings {
        var width = 376.0, height = 552.0
        for paragraph in document.paragraphs {
            let style = document.style(for: paragraph)
            let native = AttributedDocument.attributes(style: style, paragraph: paragraph)[.paragraphStyle] as? NSParagraphStyle
            let indent = max(0, native?.headIndent ?? 0, native?.firstLineHeadIndent ?? 0)
            let trailing = max(0, -(native?.tailIndent ?? 0))
            let spacing = max(0, native?.paragraphSpacingBefore ?? 0) + max(0, native?.paragraphSpacing ?? 0) + max(0, native?.lineSpacing ?? 0)
            for run in paragraph.runs {
                let size: CGSize
                if let image = run.image { size = CGSize(width: image.width, height: image.height) }
                else if let equation = run.equation {
                    let layout = EquationLayout(equation: equation)
                    size = CGSize(width: layout.width + 4, height: layout.height + 4)
                } else { continue }
                width = max(width, ceil(size.width + indent + trailing + 4))
                height = max(height, ceil(size.height + spacing + 32))
            }
        }
        var page = PageSettings()
        page.width = min(4000, width + 64); page.height = min(4000, height + 48)
        page.left = max(0, min(32, (page.width - width) / 2)); page.right = page.left
        page.top = max(0, min(24, (page.height - height) / 2)); page.bottom = page.top
        return page
    }
}
#endif
