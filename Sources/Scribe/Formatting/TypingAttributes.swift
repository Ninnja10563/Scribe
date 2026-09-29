#if canImport(AppKit)
import AppKit
import DocumentCore

extension ScribeTextView {
    /// An empty paragraph still has a character-format definition worth saving.
    /// Edit that definition transactionally; nonempty insertion points remain typing state.
    func applyTypingAttributes(_ attributes: [NSAttributedString.Key: Any], action: String) {
        guard let editor, let owner = editor.owner else { typingAttributes = attributes; return }
        let indices = editor.selectedParagraphIndices(), snapshot = owner.snapshot()
        guard indices.count == 1, let index = indices.first, snapshot.sections[0].paragraphs.indices.contains(index), snapshot.sections[0].paragraphs[index].text.isEmpty else { typingAttributes = attributes; return }
        let paragraph = snapshot.sections[0].paragraphs[index]
        let format = AttributedDocument.captureTextFormat(attributes, style: snapshot.style(for: paragraph))
        owner.performEdit(action) { document in
            var run = document.sections[0].paragraphs[index].runs.first ?? TextRun("")
            run.format = format; document.sections[0].paragraphs[index].runs = [run]
        }
    }
}
#endif
