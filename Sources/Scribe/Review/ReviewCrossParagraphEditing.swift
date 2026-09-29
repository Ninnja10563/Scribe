#if canImport(AppKit)
import AppKit
import DocumentCore

extension ScribeTextView {
    func replaceTrackedParagraphRange(_ value: NSAttributedString, range: NSRange, action: String) -> Bool {
        if value.string == "\n", action != "Typing", action != "Paste" { return false }
        guard !hasMarkedText(), (!value.string.contains("\n") || value.string == "\n"), let editor, let owner = editor.owner,
              let author = editor.reviewEditing.author, range.location >= 0, range.length > 0,
              range.location <= editor.storage.length, range.length <= editor.storage.length - range.location,
              (editor.storage.string as NSString).substring(with: range).contains("\n"),
              let first = listContext(for: NSRange(location: range.location, length: 0)),
              let last = listContext(for: NSRange(location: NSMaxRange(range), length: 0)), first.index != last.index else { return false }
        do {
            let before = owner.snapshot(), paragraphs = before.paragraphs
            guard paragraphs.indices.contains(first.index), paragraphs.indices.contains(last.index) else {
                throw DocumentError.invalid("the selected paragraphs are unavailable")
            }
            func contentStart(_ context: (index: Int, start: Int, contentStart: Int, end: Int)) -> Int {
                let paragraph = paragraphs[context.index]
                return paragraph.list == nil ? context.start + (paragraph.pageBreakBefore ? 1 : 0) : context.contentStart
            }
            var anchor = TextAnchor(paragraphID: paragraphs[first.index].id,
                                    offset: max(0, range.location - contentStart(first)), length: 0)
            anchor.endParagraphID = paragraphs[last.index].id
            anchor.endOffset = max(0, NSMaxRange(range) - contentStart(last))
            let isParagraphBreak = value.string == "\n"
            let inline = NSMutableAttributedString(attributedString: isParagraphBreak ? NSAttributedString(string: "") : value)
            let full = NSRange(location: 0, length: inline.length)
            for key in [NSAttributedString.Key.scribeParagraphID, .scribeParagraphReview, .scribeBreakReview,
                        .scribeReview, .scribeList, .scribeCell, .scribeTOC, .scribePageBreakMarker, .scribeComments] {
                inline.removeAttribute(key, range: full)
            }
            // Preserve the incoming character appearance while interpreting its
            // overrides relative to the destination paragraph's style.
            inline.addAttribute(.scribeStyle, value: paragraphs[last.index].styleID, range: full)
            var isolated = ScribeDocument(); isolated.styles = before.styles
            let fragment = AttributedDocument.capture(inline, preserving: isolated)
            var updated = before
            var caret = try updated.replaceTrackedRange(anchor, with: fragment.paragraphs[0].runs,
                                                       author: author, insertedNotes: fragment.notes)
            if isParagraphBreak {
                let next = try updated.splitTrackedParagraph(id: caret.paragraphID,
                    range: NSRange(location: caret.offset, length: 0), author: author, allowEmptyListExit: false)
                caret = TextAnchor(paragraphID: next, offset: 0, length: 0)
            }
            owner.applyReviewedStructure(updated, replacing: before, name: action)
            editor.reviewEditing.resetGrouping()
            editor.jump(to: caret.paragraphID)
            if let context = listContext(), let paragraph = updated.paragraphs.first(where: { $0.id == caret.paragraphID }) {
                let start = paragraph.list == nil ? context.start + (paragraph.pageBreakBefore ? 1 : 0) : context.contentStart
                editor.select(NSRange(location: start + caret.offset, length: 0))
                if paragraph.text.isEmpty { editor.activeTextView.typingAttributes = AttributedDocument.editingAttributes(for: paragraph, in: updated) }
            }
        } catch { presentError(error) }
        return true
    }
}
#endif
