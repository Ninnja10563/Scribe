#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NoteClipboardTests: XCTestCase {
    func testLineHeightNotesUseVersionedClipboardAndRestoreFormatting() throws {
        _ = NSApplication.shared
        for height in [nil, ParagraphLineHeight(rule: .exact, value: 24)] {
            var source = ScribeDocument(), note = DocumentNote(kind: .footnote, text: "Citation")
            var format = ParagraphFormatting(); format.lineHeight = height
            note.paragraphs[0].formatting = format
            source.notes = [note]
            var reference = TextRun("\u{fffc}"); reference.noteID = note.id
            source.sections[0].paragraphs[0].runs = [reference]
            let projection = AttributedDocument.render(source)
            let data = try InlineObjectClipboard.encode(projection)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(payload["version"] as? Int, height == nil ? 2 : 3)
            let restored = try InlineObjectClipboard.restore(data, in: NSAttributedString(string: NoteClipboard.fallback(note)))
            let noteData = try XCTUnwrap(restored.attribute(.scribeNote, at: 0, effectiveRange: nil) as? Data)
            let copy = try JSONDecoder().decode(DocumentNote.self, from: noteData)
            XCTAssertEqual(copy.paragraphs[0].formatting?.lineHeight, height)
            XCTAssertNotEqual(copy.id, note.id)
        }
    }
    func testNativeCopyPreservesContentCreatesIndependentNotesAndKeepsExternalTextReadable() throws {
        _ = NSApplication.shared
        let source = ScribeFileDocument()
        var note = DocumentNote(kind: .footnote, text: "Citation résumé with a second paragraph.")
        note.paragraphs[0].runs[0].format.italic = true
        note.paragraphs.append(Paragraph("Another source detail."))
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        source.model.notes = [note]; source.model.sections[0].paragraphs[0].runs = [TextRun("Before "), reference, TextRun(" after")]
        source.makeWindowControllers(); defer { source.close() }
        let sourceEditor = source.editorController!.editor
        sourceEditor.select(NSRange(location: 0, length: sourceEditor.storage.length))
        let board = NSPasteboard.general; board.clearContents()
        sourceEditor.activeTextView.copy(nil)
        let fallback = "Before " + NoteClipboard.fallback(note) + " after"
        XCTAssertEqual(board.string(forType: .string), fallback)
        let rich = try NSAttributedString(data: XCTUnwrap(board.data(forType: .rtfd)), options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        XCTAssertEqual(rich.string, fallback)
        let payload = try XCTUnwrap(board.data(forType: InlineObjectClipboard.type))
        XCTAssertThrowsError(try InlineObjectClipboard.restore(payload, in: NSAttributedString(string: "Modified clipboard")))
        let destination = ScribeFileDocument()
        let normal = try XCTUnwrap(destination.model.styles.firstIndex { $0.id == "normal" })
        destination.model.styles[normal].text.fontSize = 30
        destination.makeWindowControllers(); defer { destination.close() }
        let editor = destination.editorController!.editor
        editor.activeTextView.paste(nil); editor.paginate()
        let first = try XCTUnwrap(destination.snapshot().notes.first)
        XCTAssertNotEqual(first.id, note.id)
        XCTAssertEqual(first.plainText, note.plainText)
        XCTAssertEqual(first.paragraphs[0].runs[0].format.italic, true)
        XCTAssertEqual(first.paragraphs[0].runs[0].format.fontSize, ParagraphStyle.defaults.first { $0.id == "normal" }?.text.fontSize)
        XCTAssertTrue(Set(first.paragraphs.map(\.id)).isDisjoint(with: Set(note.paragraphs.map(\.id))))
        // Separate native user events close the implicit undo group.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        editor.activeTextView.paste(nil); editor.paginate()
        let pasted = destination.snapshot()
        XCTAssertEqual(pasted.notes.count, 2)
        XCTAssertEqual(Set(pasted.notes.map(\.id)).count, 2)
        try NativeFormat.validate(pasted)
        destination.undoManager?.undo(); XCTAssertEqual(destination.snapshot().notes.count, 1)
        destination.undoManager?.redo(); XCTAssertEqual(destination.snapshot().notes.count, 2)
    }
}
#endif
