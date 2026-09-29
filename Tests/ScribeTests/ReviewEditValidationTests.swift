#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ReviewEditValidationTests: XCTestCase {
    private func document() -> ScribeFileDocument {
        _ = NSApplication.shared
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = [Paragraph("Body")]
        document.makeWindowControllers(); document.editorController!.editor.reviewEditing.author = .init(name: "Reviewer")
        return document
    }
    func testScopedInsertionRejectsInvalidFormattingWithoutChangingDocument() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, original = NSAttributedString(attributedString: document.editorController!.editor.storage)
        let invalid = NSAttributedString(string: "x", attributes: [.font: NSFont.systemFont(ofSize: 5000)])
        XCTAssertThrowsError(try editor.reviewEditing.replacement(in: editor, range: NSRange(location: 0, length: 0), with: invalid))
        XCTAssertTrue(editor.storage.isEqual(to: original))
    }
    func testUnicodeInsertionKeepsOtherParagraphAndNoteIdentities() throws {
        let document = document(); defer { document.close() }
        let note = DocumentNote(kind: .footnote, text: "Citation")
        document.performEdit("Note") { model in
            model.notes = [note]
            var reference = TextRun("\u{fffc}"); reference.noteID = note.id
            model.sections[0].paragraphs.append(Paragraph("Reference "))
            model.sections[0].paragraphs[1].runs.append(reference)
        }
        let editor = document.editorController!.editor, before = document.snapshot()
        editor.activeTextView.insertText("👩🏽‍💻 café ", replacementRange: NSRange(location: 0, length: 0))
        let after = document.snapshot(); try NativeFormat.validate(after)
        XCTAssertEqual(after.paragraphs.map(\.id), before.paragraphs.map(\.id))
        XCTAssertEqual(after.paragraphs[1], before.paragraphs[1]); XCTAssertEqual(after.notes, before.notes)
        XCTAssertTrue(after.paragraphs[0].text.hasPrefix("👩🏽‍💻 café "))
        XCTAssertEqual(after.pendingRevisionIDs.count, 1)
    }
    func testObjectInsertionStillRejectsInvalidReferencePayload() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, original = NSAttributedString(attributedString: document.editorController!.editor.storage)
        let note = DocumentNote(kind: .footnote, text: "Citation")
        let numbered = try NoteNumbering.resolve(referenceIDs: [note.id], notes: [note])[0]
        // Two references sharing one note identity are invalid, even when each
        // object would be valid in isolation.
        let attributes: [NSAttributedString.Key: Any] = [.attachment: NoteProjection.attachment(numbered, baseFont: .systemFont(ofSize: 12)), .scribeNote: try JSONEncoder().encode(note)]
        let duplicate = NSAttributedString(string: "\u{fffc}\u{fffc}", attributes: attributes)
        XCTAssertThrowsError(try editor.reviewEditing.replacement(in: editor, range: NSRange(location: 0, length: 0), with: duplicate))
        XCTAssertTrue(editor.storage.isEqual(to: original))
    }
}
#endif
