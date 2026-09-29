#if canImport(AppKit)
import AppKit
import DocumentCore

/// A native rich-text editing session. Cancel never changes the document model.
@MainActor final class NoteOptions {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 240))
    let text = ScribeTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 220))
    private let original: DocumentNote
    private let model: ScribeDocument
    init(note: DocumentNote, styles: [ParagraphStyle]) {
        original = note
        var isolated = ScribeDocument(); isolated.styles = styles; isolated.sections[0].paragraphs = note.paragraphs
        model = isolated
        text.isRichText = true; text.importsGraphics = false; text.allowsUndo = true
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.isContinuousSpellCheckingEnabled = true
        text.textStorage?.setAttributedString(AttributedDocument.render(isolated))
        text.typingAttributes = AttributedDocument.editingAttributes(for: note.paragraphs[0], in: isolated)
        text.setAccessibilityLabel("Note text"); text.identifier = NSUserInterfaceItemIdentifier("Note Text")
        let scroll = NSScrollView(frame: view.bounds)
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true; scroll.documentView = text
        view.addSubview(scroll)
    }
    func note() throws -> DocumentNote {
        var result = original
        result.paragraphs = AttributedDocument.capture(text.textStorage ?? NSTextStorage(), preserving: model, typingAttributes: text.typingAttributes).paragraphs
        var check = ScribeDocument(); check.styles = model.styles; check.notes = [result]
        var reference = TextRun("\u{fffc}"); reference.noteID = result.id
        check.sections[0].paragraphs[0].runs = [reference]
        try NativeFormat.validate(check)
        return result
    }
}
#endif
