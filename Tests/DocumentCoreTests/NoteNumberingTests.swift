import XCTest
@testable import DocumentCore

final class NoteNumberingTests: XCTestCase {
    func testEachNoteKindRenumbersFromReferenceOrderAfterMoveAndDelete() throws {
        let first = DocumentNote(kind: .footnote, text: "First reference")
        let second = DocumentNote(kind: .footnote, text: "Second reference")
        let end = DocumentNote(kind: .endnote, text: "Collected reference")
        let notes = [first, second, end]
        let initial = try NoteNumbering.resolve(referenceIDs: [first.id, end.id, second.id], notes: notes)
        XCTAssertEqual(initial.map(\.number), [1, 1, 2])
        XCTAssertEqual(initial.map(\.id), [first.id, end.id, second.id])
        let moved = try NoteNumbering.resolve(referenceIDs: [second.id, first.id, end.id], notes: notes)
        XCTAssertEqual(moved.map(\.number), [1, 2, 1])
        let deleted = try NoteNumbering.resolve(referenceIDs: [second.id, end.id], notes: notes)
        XCTAssertEqual(deleted.map(\.number), [1, 1])
        XCTAssertEqual(deleted[0].note.paragraphs[0].text, "Second reference")
    }
    func testNoteParagraphsAndUnicodeRoundTripWithoutSharingBodyIdentity() throws {
        var note = DocumentNote(kind: .footnote, text: "Citation — résumé 👩🏽‍💻")
        note.paragraphs.append(Paragraph("Additional explanation."))
        note.paragraphs[1].runs[0].format.italic = true
        let copy = try JSONDecoder().decode(DocumentNote.self, from: JSONEncoder().encode(note))
        XCTAssertEqual(copy, note)
        XCTAssertNotEqual(copy.paragraphs[0].id, copy.paragraphs[1].id)
        XCTAssertEqual(copy.plainText, "Citation — résumé 👩🏽‍💻\nAdditional explanation.")
    }
    func testNativeNotesRetainStructuredContentAndMigrateVersionTwelve() throws {
        var document = ScribeDocument()
        let note = DocumentNote(kind: .footnote, text: "A source citation.")
        document.notes = [note]
        var reference = TextRun("\u{FFFC}"); reference.noteID = note.id
        document.sections[0].paragraphs[0].runs = [TextRun("A statement."), reference]
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        XCTAssertTrue(document.plainText.contains("[Footnote 1]"))
        XCTAssertTrue(document.plainText.contains("1. A source citation."))
        document.notes[0].paragraphs[0].runs[0].noteID = note.id
        XCTAssertThrowsError(try NativeFormat.encode(document), "Recursive notes must be rejected")
        let legacy = ScribeDocument()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: NativeFormat.encode(legacy)) as? [String: Any])
        json["formatVersion"] = 12; json.removeValue(forKey: "notes")
        let source = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try NativeFormat.decode(source), legacy)
        XCTAssertNil((try JSONSerialization.jsonObject(with: source) as? [String: Any])?["notes"])
    }
    func testOrphanedAndDuplicatedNoteReferencesCannotBeSaved() throws {
        var document = ScribeDocument()
        let note = DocumentNote(kind: .endnote, text: "A final reference.")
        document.notes = [note]
        XCTAssertThrowsError(try NativeFormat.encode(document))
        var reference = TextRun("\u{FFFC}"); reference.noteID = note.id
        document.sections[0].paragraphs[0].runs = [reference, reference]
        XCTAssertThrowsError(try NativeFormat.encode(document))
        document.sections[0].paragraphs[0].runs = [reference]
        document.notes[0].paragraphs[0].id = document.paragraphs[0].id
        XCTAssertThrowsError(try NativeFormat.encode(document))
    }
    func testDanglingDuplicateAndEmptyNotesAreRejected() throws {
        var note = DocumentNote(kind: .footnote)
        XCTAssertThrowsError(try NoteNumbering.resolve(referenceIDs: [UUID()], notes: [note]))
        XCTAssertThrowsError(try NoteNumbering.resolve(referenceIDs: [note.id, note.id], notes: [note]))
        XCTAssertThrowsError(try NoteNumbering.resolve(referenceIDs: [note.id], notes: [note, note]))
        note.paragraphs = []
        XCTAssertThrowsError(try NoteNumbering.resolve(referenceIDs: [note.id], notes: [note]))
    }
}
