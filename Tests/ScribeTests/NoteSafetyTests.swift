#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NativeNoteSafetyTests: XCTestCase {
    func testIncompleteNoteEditorRejectsOpeningAndRecoveryWithoutChangingSource() throws {
        _ = NSApplication.shared
        var model = ScribeDocument()
        let note = DocumentNote(kind: .footnote, text: "Preserve this citation.")
        model.notes = [note]
        var reference = TextRun("\u{FFFC}"); reference.noteID = note.id
        model.sections[0].paragraphs[0].runs = [reference]
        let bytes = try NativeFormat.encode(model)
        let document = ScribeFileDocument(); defer { document.close() }
        let before = document.model
        XCTAssertThrowsError(try document.read(from: bytes, ofType: ScribeFileDocument.typeName))
        XCTAssertEqual(document.model, before)
        XCTAssertEqual(try NativeFormat.decode(bytes), model)
        XCTAssertThrowsError(try ScribeFileDocument.recovering(RecoverySnapshot(document: model, originalURL: nil)))
    }
}
#endif
