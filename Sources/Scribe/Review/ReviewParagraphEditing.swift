#if canImport(AppKit)
import AppKit
import DocumentCore

extension ScribeTextView {
    /// Native Return and newline-only replacements share the semantic split
    /// path. A range spanning paragraphs is handled by the general replacement
    /// path until multi-paragraph transactions are integrated here.
    func insertTrackedParagraphBreak(replacing range: NSRange, action: String) -> Bool {
        guard !hasMarkedText(), let editor, let owner = editor.owner,
              let author = editor.reviewEditing.author, range.location >= 0, range.length >= 0,
              let context = listContext(for: range) else { return false }
        var model = owner.snapshot()
        guard model.paragraphs.indices.contains(context.index) else { return false }
        let paragraph = model.paragraphs[context.index]
        // Literal tabs in ordinary text are content, unlike generated markers.
        let start = paragraph.list == nil ? context.start + (paragraph.pageBreakBefore ? 1 : 0) : context.contentStart
        guard range.location >= start, range.location <= context.end,
              range.length <= context.end - range.location else { return false }
        do {
            let target = try model.splitTrackedParagraph(id: paragraph.id,
                range: NSRange(location: range.location - start, length: range.length), author: author)
            owner.performEdit(action == "Typing" ? "New Paragraph" : action, recordReview: false) { $0 = model }
            editor.reviewEditing.resetGrouping()
            editor.jump(to: target)
            if let next = listContext(), let paragraph = model.paragraphs.first(where: { $0.id == target }) {
                let point = paragraph.list == nil ? next.start + (paragraph.pageBreakBefore ? 1 : 0) : next.contentStart
                editor.select(NSRange(location: point, length: 0))
                if paragraph.text.isEmpty {
                    editor.activeTextView.typingAttributes = AttributedDocument.editingAttributes(for: paragraph, in: model)
                }
            }
        } catch { presentError(error) }
        return true
    }
}
#endif
