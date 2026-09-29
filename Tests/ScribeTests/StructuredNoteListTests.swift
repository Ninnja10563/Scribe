#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class StructuredNoteListTests: XCTestCase {
    private func note(_ kind: DocumentNote.Kind) -> DocumentNote {
        var note = DocumentNote(kind: kind)
        note.paragraphs = ["First", "Second"].enumerated().map { index, text in
            var paragraph = Paragraph(text)
            paragraph.list = .init(kind: .decimal, start: 4, restart: index == 0 ? true : nil)
            return paragraph
        }
        return note
    }
    func testOrdinaryNoteListJoinAndUndoPreserveSemanticContent() throws {
        _ = NSApplication.shared
        for kind in [DocumentNote.Kind.footnote, .endnote] {
            let original = note(kind)
            let options = NoteOptions(note: original, styles: ParagraphStyle.defaults)
            defer { options.close() }
            XCTAssertNotNil(options.text.editor)
            let separator = (options.text.string as NSString).range(of: "\n").location
            options.text.setSelectedRange(NSRange(location: separator, length: 0))
            options.text.deleteForward(nil)
            let joined = try options.note()
            XCTAssertEqual(joined.paragraphs.map(\.text), ["FirstSecond"])
            XCTAssertEqual(joined.id, original.id)
            XCTAssertEqual(joined.paragraphs[0].list, original.paragraphs[0].list)
            options.text.undoManager?.undo(); XCTAssertEqual(try options.note(), original)
            options.text.undoManager?.redo(); XCTAssertEqual(try options.note(), joined)
        }
    }
    func testOrdinaryNoteListReturnContinuesNumberingAndUndoRestores() throws {
        _ = NSApplication.shared
        let original = note(.footnote)
        let options = NoteOptions(note: original, styles: ParagraphStyle.defaults)
        defer { options.close() }
        let end = (options.text.string as NSString).range(of: "First").location + 5
        options.text.setSelectedRange(NSRange(location: end, length: 0))
        options.text.insertNewline(nil)
        let split = try options.note()
        XCTAssertEqual(split.paragraphs.map(\.text), ["First", "", "Second"])
        XCTAssertTrue(options.text.string.contains("\t6.\tSecond"))
        options.text.undoManager?.undo(); XCTAssertEqual(try options.note(), original)
    }
}
#endif
