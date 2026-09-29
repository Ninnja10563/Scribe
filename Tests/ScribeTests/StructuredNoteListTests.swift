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
    func testPastingListsIntoInitiallyPlainNoteKeepsSemanticEditingAvailable() throws {
        _ = NSApplication.shared
        let options = NoteOptions(note: DocumentNote(kind: .footnote), styles: ParagraphStyle.defaults)
        defer { options.close() }
        var pasted = ScribeDocument(); pasted.sections[0].paragraphs = note(.footnote).paragraphs
        options.text.replaceSelection(AttributedDocument.render(pasted), action: "Paste")
        let before = try options.note()
        XCTAssertEqual(before.paragraphs.map(\.text), ["First", "Second"])
        XCTAssertTrue(before.paragraphs.allSatisfy { $0.list != nil })
        options.text.undoManager?.removeAllActions()
        let separator = (options.text.string as NSString).range(of: "\n").location
        options.text.setSelectedRange(NSRange(location: separator, length: 0))
        options.text.deleteForward(nil)
        XCTAssertEqual(try options.note().paragraphs.map(\.text), ["FirstSecond"])
        options.text.undoManager?.undo(); XCTAssertEqual(try options.note(), before)
    }
    func testNoteListKeyboardIndentAndOutdentUseNativeUndo() async throws {
        _ = NSApplication.shared
        let original = note(.endnote)
        let options = NoteOptions(note: original, styles: ParagraphStyle.defaults)
        defer { options.close() }
        let start = (options.text.string as NSString).range(of: "Second").location
        options.text.setSelectedRange(NSRange(location: start, length: 0))
        options.text.insertTab(nil)
        XCTAssertEqual(try options.note().paragraphs[1].list?.level, 1)
        // Distinct key events close AppKit's event-based Undo group.
        try await Task.sleep(nanoseconds: 30_000_000)
        options.text.insertBacktab(nil)
        XCTAssertEqual(try options.note().paragraphs[1].list?.level, 0)
        try await Task.sleep(nanoseconds: 30_000_000)
        options.text.undoManager?.undo()
        XCTAssertEqual(try options.note().paragraphs[1].list?.level, 1)
        options.text.undoManager?.undo()
        XCTAssertEqual(try options.note(), original)
    }
    func testApplyCommitsOrdinaryMarkedInputInPlainNote() throws {
        _ = NSApplication.shared
        let options = NoteOptions(note: DocumentNote(kind: .footnote, text: "Citation"), styles: ParagraphStyle.defaults)
        defer { options.close() }
        options.text.setSelectedRange(NSRange(location: 8, length: 0))
        options.text.setMarkedText("語", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(options.text.hasMarkedText())
        let applied = try options.note()
        XCTAssertFalse(options.text.hasMarkedText())
        XCTAssertEqual(applied.plainText, "Citation語")
        XCTAssertTrue(applied.paragraphs[0].runs.allSatisfy { $0.review == nil })
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
