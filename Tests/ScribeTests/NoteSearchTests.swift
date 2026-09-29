#if canImport(AppKit)
import AppKit
import XCTest
import PDFKit
import DocumentCore
@testable import Scribe

@MainActor final class NoteSearchTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func document() -> ScribeFileDocument {
        let document = ScribeFileDocument()
        var foot = DocumentNote(kind: .footnote, text: "café 👩🏽‍💻 citation")
        foot.paragraphs[0].runs[0].format.bold = true
        foot.paragraphs[0].list = .init(kind: .upperRoman, start: 4)
        let end = DocumentNote(kind: .endnote, text: "café end citation")
        document.model.notes = [foot, end]
        var first = TextRun("\u{fffc}"), second = TextRun("\u{fffc}")
        first.noteID = foot.id; second.noteID = end.id
        document.model.sections[0].paragraphs[0].runs = [TextRun("café body "), first, TextRun(" after "), second]
        document.makeWindowControllers()
        return document
    }
    func testSearchOrderUnicodeAndGeneratedLabels() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor
        let matches = editor.semanticText.documentMatches(query: "café")
        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(matches.first, .body(NSRange(location: 0, length: 4)))
        guard case .note(let id, let range, _) = matches[1] else { return XCTFail("Missing footnote match") }
        XCTAssertEqual(id, document.model.notes[0].id); XCTAssertEqual(range, NSRange(location: 0, length: 4))
        XCTAssertTrue(editor.semanticText.documentMatches(query: "IV.").isEmpty)
        let unicode = editor.semanticText.documentMatches(query: "👩🏽‍💻")
        XCTAssertEqual(unicode.count, 1)
        let presentation = NoteSearchPresentation()
        XCTAssertEqual(presentation.reveal(unicode[0], in: editor), 1)
        presentation.highlight(matches, in: editor)
        let foot = try XCTUnwrap(editor.canvas.footnotes[0]?.notes.first?.note)
        let source = (foot.storage.string as NSString).range(of: "café")
        XCTAssertNotNil(foot.layout.temporaryAttribute(.backgroundColor, atCharacterIndex: source.location, effectiveRange: nil))
        XCTAssertNil(foot.layout.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil))
        XCTAssertEqual(presentation.reveal(matches[2], in: editor), editor.canvas.bodyPageCount + 1)
        presentation.clear()
    }
    func testReplaceAllPreservesFormattingListsAndSingleUndo() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, before = document.snapshot()
        document.undoManager?.removeAllActions()
        try DocumentSearchReplacement.apply(editor.semanticText.documentMatches(query: "café"), replacement: "Coffee", in: editor, action: "Replace All")
        let changed = document.snapshot()
        XCTAssertTrue(changed.paragraphs[0].text.hasPrefix("Coffee body"))
        XCTAssertEqual(changed.notes[0].paragraphs[0].text, "Coffee 👩🏽‍💻 citation")
        XCTAssertEqual(changed.notes[1].paragraphs[0].text, "Coffee end citation")
        XCTAssertEqual(changed.notes[0].paragraphs[0].runs[0].format.bold, true)
        XCTAssertEqual(changed.notes[0].paragraphs[0].list, before.notes[0].paragraphs[0].list)
        XCTAssertEqual(changed.notes.map(\.id), before.notes.map(\.id))
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().notes, before.notes)
        XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().notes, changed.notes)
    }
    func testSearchHighlightDoesNotChangePDFRendering() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plain = directory.appendingPathComponent("NoteSearch-plain.pdf")
        let highlighted = directory.appendingPathComponent("NoteSearch-highlighted.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: plain, title: "Find notes", author: "")
        let presentation = NoteSearchPresentation()
        presentation.highlight(editor.semanticText.documentMatches(query: "café"), in: editor)
        try PrintRenderer(editor: editor).exportPDF(to: highlighted, title: "Find notes", author: "")
        let first = try XCTUnwrap(PDFDocument(url: plain)), second = try XCTUnwrap(PDFDocument(url: highlighted))
        XCTAssertEqual(first.pageCount, second.pageCount)
        for index in 0..<first.pageCount {
            let size = NSSize(width: 600, height: 800)
            XCTAssertEqual(first.page(at: index)?.thumbnail(of: size, for: .mediaBox).tiffRepresentation,
                           second.page(at: index)?.thumbnail(of: size, for: .mediaBox).tiffRepresentation)
        }
        presentation.clear()
    }
    func testFindRevealsContinuationPage() throws {
        let document = document(); defer { document.close() }
        var note = document.model.notes[0]
        note.paragraphs = (0..<90).map { Paragraph("Citation paragraph \($0) continues with useful source information.") }
        note.paragraphs.append(Paragraph("Unique continuation target"))
        try document.editorController!.applyNote(note, replacing: NSRange(location: 10, length: 1), action: "Edit Note")
        let editor = document.editorController!.editor
        let match = try XCTUnwrap(editor.semanticText.documentMatches(query: "Unique continuation target").first)
        let page = try XCTUnwrap(NoteSearchPresentation().reveal(match, in: editor))
        XCTAssertGreaterThan(page, 1)
        XCTAssertLessThanOrEqual(page, editor.canvas.bodyPageCount)
    }
    func testInvalidNoteReplacementIsAtomic() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor
        let original = NSAttributedString(attributedString: editor.storage)
        XCTAssertThrowsError(try DocumentSearchReplacement.apply(editor.semanticText.documentMatches(query: "café"), replacement: "\u{c}Break", in: editor, action: "Replace All"))
        XCTAssertTrue(original.isEqual(to: editor.storage))
    }
    func testFindNavigationAndSingleNoteReplacement() throws {
        let document = document(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor, search = controller.searchBar
        search.isHidden = false; search.query.stringValue = "café"
        editor.select(NSRange(location: 0, length: 4))
        search.next()
        guard case .note(let id, _, _) = search.currentMatch else { return XCTFail("Find did not navigate into footnote") }
        XCTAssertEqual(id, document.model.notes[0].id)
        search.replacement.stringValue = "Tea"; search.replace()
        XCTAssertEqual(document.snapshot().notes[0].paragraphs[0].text, "Tea 👩🏽‍💻 citation")
        XCTAssertTrue(document.snapshot().paragraphs[0].text.hasPrefix("café"))
        search.close()
    }
}
#endif
