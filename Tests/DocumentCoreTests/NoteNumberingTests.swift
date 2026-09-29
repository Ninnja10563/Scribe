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
    func testDanglingDuplicateAndEmptyNotesAreRejected() throws {
        var note = DocumentNote(kind: .footnote)
        XCTAssertThrowsError(try NoteNumbering.resolve(referenceIDs: [UUID()], notes: [note]))
        XCTAssertThrowsError(try NoteNumbering.resolve(referenceIDs: [note.id, note.id], notes: [note]))
        XCTAssertThrowsError(try NoteNumbering.resolve(referenceIDs: [note.id], notes: [note, note]))
        note.paragraphs = []
        XCTAssertThrowsError(try NoteNumbering.resolve(referenceIDs: [note.id], notes: [note]))
    }
}
