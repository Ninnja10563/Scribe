#if canImport(AppKit)
import AppKit
import DocumentCore

extension EditorWindowController {
    @objc func editStyle() {
        updateStatus()
        let index = stylePicker.indexOfSelectedItem
        guard fileDocument.model.styles.indices.contains(index) else { return }
        showStyleEditor(fileDocument.model.styles[index], creating: false)
    }
    @objc func createStyle() {
        let view = editor.activeTextView, selection = view.selectedRange()
        let attributes = selection.location < editor.storage.length ? editor.storage.attributes(at: selection.location, effectiveRange: nil) : view.typingAttributes
        let sourceID = attributes[.scribeStyle] as? String ?? "normal"
        var style = fileDocument.model.styles.first { $0.id == sourceID } ?? .normal
        style.id = UUID().uuidString; style.name = "Custom Style"; style.isBuiltIn = false
        if let font = attributes[.font] as? NSFont {
            style.text.fontFamily = font.familyName; style.text.fontFace = attributes[.scribeFontFace] as? String ?? font.fontName; style.text.fontSize = font.pointSize
            let traits = NSFontManager.shared.traits(of: font)
            style.text.bold = traits.contains(.boldFontMask); style.text.italic = traits.contains(.italicFontMask)
        }
        style.text.underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
        style.text.strikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
        style.text.foreground = (attributes[.foregroundColor] as? NSColor)?.hex
        style.text.highlight = (attributes[.backgroundColor] as? NSColor)?.hex
        style.text.baseline = attributes[.superscript] as? Int
        if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle { style.paragraph = AttributedDocument.paragraphFormatting(paragraph) }
        showStyleEditor(style, creating: true)
    }
    private func showStyleEditor(_ style: ParagraphStyle, creating: Bool) {
        let options = StyleEditorOptions(style: style), alert = NSAlert()
        alert.messageText = creating ? "Create Paragraph Style" : "Modify \(style.name)"
        alert.informativeText = creating ? "Start from the current text formatting. The new style is applied to the selected paragraphs." : "Paragraphs using this style update together. Direct formatting is preserved. Measurements are in points."
        alert.accessoryView = options.view
        alert.addButton(withTitle: creating ? "Create" : "Apply"); alert.addButton(withTitle: "Cancel")
        while !isClosing, alert.runModal() == .alertFirstButtonReturn {
            do { try saveStyleDefinition(options.value(contentWidth: editor.canvas.pageSettings.contentWidth), applying: creating); return }
            catch { alert.informativeText = error.localizedDescription }
        }
    }
    func saveStyleDefinition(_ style: ParagraphStyle, applying: Bool) throws {
        guard !isClosing else { return }
        var checked = fileDocument.snapshot()
        guard !checked.styles.contains(where: { $0.id != style.id && $0.name.caseInsensitiveCompare(style.name) == .orderedSame }) else { throw DocumentError.invalid("another style already uses that name") }
        checked.updateStyle(style); try NativeFormat.validate(checked)
        let indices = applying ? editor.selectedParagraphIndices() : []
        fileDocument.performEdit(applying ? "Create Style" : "Modify Style") { model in
            model.updateStyle(style)
            for index in indices where model.sections[0].paragraphs.indices.contains(index) {
                model.sections[0].paragraphs[index].styleID = style.id
                model.sections[0].paragraphs[index].formatting = nil
            }
        }
    }
}
#endif
