#if canImport(AppKit)
import AppKit
import DocumentCore

extension EditorWindowController {
    func setLineHeightMultiple(_ multiple: Double) {
        guard [1, 1.15, 1.5, 2, 2.5, 3].contains(multiple) else { return }
        editSelectedParagraphs("Line Spacing") { paragraph, style in
            var format = paragraph.formatting ?? style.paragraph
            format.lineSpacing = 0; format.lineHeight = .init(rule: .multiple, value: multiple)
            paragraph.formatting = format
        }
    }
    @objc func clearParagraphFormatting() {
        editSelectedParagraphs("Clear Paragraph Formatting") { paragraph, _ in paragraph.formatting = nil }
    }
    @objc func increaseIndent() { changeParagraphIndent(by: 24) }
    @objc func decreaseIndent() { changeParagraphIndent(by: -24) }
    func changeParagraphIndent(by amount: Double) {
        let width = editor.canvas.pageSettings.contentWidth
        editSelectedParagraphs(amount > 0 ? "Increase Indent" : "Decrease Indent") { paragraph, style in
            if var list = paragraph.list {
                list.level = max(0, min(8, list.level + (amount > 0 ? 1 : -1))); paragraph.list = list
            } else {
                var format = paragraph.formatting ?? style.paragraph
                let delta = max(-min(format.headIndent, format.firstLineIndent), min(amount, width - 30 - format.tailIndent - max(format.headIndent, format.firstLineIndent)))
                format.headIndent += delta; format.firstLineIndent += delta; paragraph.formatting = format
            }
        }
    }
    @objc func togglePageBreakBefore() {
        let selected = editor.selectedParagraphIndices(), paragraphs = fileDocument.snapshot().sections[0].paragraphs
        let enabled = !selected.allSatisfy { paragraphs.indices.contains($0) && paragraphs[$0].pageBreakBefore }
        editSelectedParagraphs("Page Break Before") { paragraph, _ in paragraph.pageBreakBefore = enabled }
    }
    func editSelectedParagraphs(_ name: String, change: (inout Paragraph, ParagraphStyle) -> Void) {
        let indices = editor.selectedParagraphIndices()
        fileDocument.performEdit(name) { model in
            for index in indices where model.sections[0].paragraphs.indices.contains(index) {
                let style = model.style(for: model.sections[0].paragraphs[index])
                change(&model.sections[0].paragraphs[index], style)
            }
        }
    }
    @objc func copyCharacterFormatting() {
        copiedCharacterAppearance = CharacterAppearance.extract(editor.activeTextView.currentCharacterAttributes)
        showStatus("Character formatting copied. Select destination text, then Paste Character Formatting.")
    }
    @objc func pasteCharacterFormatting() {
        guard let appearance = copiedCharacterAppearance else { NSSound.beep(); return }
        editor.activeTextView.applyCharacterAppearance(appearance)
    }
}
#endif
