#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NativeNoteSafetyTests: XCTestCase {
    func testNativeNoteOpeningAndRecoveryPreserveContentAndSourceIdentity() throws {
        _ = NSApplication.shared
        var model = ScribeDocument()
        let note = DocumentNote(kind: .footnote, text: "Preserve this citation.")
        model.notes = [note]
        var reference = TextRun("\u{FFFC}"); reference.noteID = note.id
        model.sections[0].paragraphs[0].runs = [reference]
        let bytes = try NativeFormat.encode(model)
        let document = ScribeFileDocument(); defer { document.close() }
        try document.read(from: bytes, ofType: ScribeFileDocument.typeName)
        XCTAssertEqual(document.model, model)
        document.makeWindowControllers()
        XCTAssertNil(document.editorController?.editor.outputWarning)
        XCTAssertEqual(try NativeFormat.decode(document.data(ofType: ScribeFileDocument.typeName)).notes, [note])
        XCTAssertEqual(try NativeFormat.decode(bytes), model)
        let recovered = try ScribeFileDocument.recovering(RecoverySnapshot(document: model, originalURL: nil))
        defer { recovered.close() }
        XCTAssertNotEqual(recovered.model.id, model.id)
        XCTAssertEqual(recovered.model.notes, [note])
        recovered.makeWindowControllers()
        XCTAssertNil(recovered.editorController?.editor.outputWarning)
        XCTAssertEqual(recovered.snapshot().notes, [note])

    }
}
#endif
