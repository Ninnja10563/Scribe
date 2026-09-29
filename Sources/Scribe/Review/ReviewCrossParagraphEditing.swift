#if canImport(AppKit)
import AppKit
import DocumentCore

extension ScribeTextView {
    func replaceSemanticParagraphRange(_ value: NSAttributedString, range: NSRange, action: String) -> Bool {
        if value.string == "\n", action != "Typing", action != "Paste" { return false }
        let multilineTyping = action == "Typing" && value.string.contains("\n") && value.string != "\n"
        let multilinePaste = action == "Paste" && value.string.contains("\n")
        guard !hasMarkedText(), (!value.string.contains("\n") || value.string == "\n" || multilineTyping || multilinePaste),
              let editor, let owner = editor.owner,
              range.location >= 0, range.length >= 0,
              range.location <= editor.storage.length, range.length <= editor.storage.length - range.location,
              multilineTyping || multilinePaste || (editor.storage.string as NSString).substring(with: range).contains("\n"),
              let first = listContext(for: NSRange(location: range.location, length: 0)),
              let last = listContext(for: NSRange(location: NSMaxRange(range), length: 0)) else { return false }
        let author = editor.reviewEditing.author
        if author == nil {
            var containsList = false
            let extent = NSRange(location: range.location, length: min(editor.storage.length - range.location, max(1, range.length)))
            editor.storage.enumerateAttribute(.scribeList, in: extent) { value, _, stop in
                if value != nil { containsList = true; stop.pointee = true }
            }
            if !containsList, NSMaxRange(range) < editor.storage.length {
                containsList = editor.storage.attribute(.scribeList, at: NSMaxRange(range), effectiveRange: nil) != nil
            }
            guard containsList else { return false }
        }
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
            let inline = NSMutableAttributedString(attributedString: value)
            let full = NSRange(location: 0, length: inline.length)
            if multilinePaste {
                var hasCells = false
                inline.enumerateAttributes(in: full) { attributes, _, stop in
                    if attributes[.scribeCell] != nil || ((attributes[.paragraphStyle] as? NSParagraphStyle)?.textBlocks.isEmpty == false) {
                        hasCells = true; stop.pointee = true
                    }
                }
                guard !hasCells else { throw DocumentError.invalid("tracked table paste requires a table transaction") }
            }
            for key in [NSAttributedString.Key.scribeParagraphID, .scribeParagraphReview, .scribeBreakReview,
                        .scribeReview, .scribeCell, .scribeTOC, .scribeComments] {
                inline.removeAttribute(key, range: full)
            }
            if !multilinePaste {
                for key in [NSAttributedString.Key.scribeList, .scribePageBreakMarker] { inline.removeAttribute(key, range: full) }
                // Inline/typed content contributes character appearance, while
                // multiline rich paste also contributes paragraph properties.
                inline.addAttribute(.scribeStyle, value: paragraphs[last.index].styleID, range: full)
            }
            var isolated = ScribeDocument(); isolated.styles = before.styles
            let fragment = AttributedDocument.capture(inline, preserving: isolated)
            var updated = before
            let caret: TextAnchor
            if let author {
                caret = try updated.replaceTrackedRange(anchor, withLines: fragment.paragraphs.map(\.runs),
                    paragraphProperties: multilinePaste ? fragment.paragraphs.map(ParagraphRevisionState.init) : nil,
                    author: author, insertedNotes: fragment.notes)
            } else {
                caret = try updated.replaceUntrackedRange(anchor, withLines: fragment.paragraphs.map(\.runs),
                    paragraphProperties: multilinePaste ? fragment.paragraphs.map(ParagraphRevisionState.init) : nil,
                    insertedNotes: fragment.notes)
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
