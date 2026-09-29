#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ReviewDrawingTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func fixture() -> ScribeDocument {
        var document = ScribeDocument()
        let author = RevisionAuthor(name: "Writer")
        var insertion = RunReview(); insertion.insertion = .init(author: author)
        var deletion = RunReview(); deletion.deletion = .init(author: author)
        var a = TextRun("Inserted"), b = TextRun("Deleted")
        a.review = insertion; b.review = deletion
        var bold = TextFormatting(); bold.bold = true
        var formatting = RunReview(); formatting.formattingBase = TextFormatting()
        formatting.formatting = [FormattingRevision(identity: .init(author: author), before: TextFormatting(), after: bold)]
        var c = TextRun("Formatted", format: bold); c.review = formatting
        document.sections[0].paragraphs[0].runs = [a, TextRun(" / "), b, TextRun(" / Original / "), c]
        return document
    }
    func testNativeDrawingPreservesSearchAndNeverChangesStoredFormatting() throws {
        let document = ScribeFileDocument(); document.model = fixture(); document.makeWindowControllers()
        defer { document.close() }
        let editor = document.editorController!.editor, before = document.snapshot()
        let original = NSAttributedString(attributedString: editor.storage)
        var range = NSRange(location: 0, length: editor.storage.length)
        let search: [NSAttributedString.Key: Any] = [.backgroundColor: NSColor.yellow]
        let inserted = try XCTUnwrap(editor.layoutManager(editor.layout, shouldUseTemporaryAttributes: search, forDrawingToScreen: true, atCharacterIndex: 0, effectiveRange: &range))
        XCTAssertEqual(range, NSRange(location: 0, length: 8))
        XCTAssertEqual(inserted[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(inserted[.backgroundColor] as? NSColor, .yellow)
        range = NSRange(location: 0, length: editor.storage.length)
        let deleted = editor.layoutManager(editor.layout, shouldUseTemporaryAttributes: [:], forDrawingToScreen: true, atCharacterIndex: 11, effectiveRange: &range)
        XCTAssertEqual(deleted?[.strikethroughStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(range, NSRange(location: 11, length: 7))
        range = NSRange(location: 0, length: editor.storage.length)
        XCTAssertNil(editor.layoutManager(editor.layout, shouldUseTemporaryAttributes: search, forDrawingToScreen: false, atCharacterIndex: 0, effectiveRange: &range))
        XCTAssertTrue(editor.storage.isEqual(to: original))
        XCTAssertEqual(document.snapshot(), before)
        document.editorController?.window?.makeKeyAndOrderFront(nil)
        editor.paginate(); editor.canvas.layoutSubtreeIfNeeded()
        NativeDialogCapture.save(editor.textViews[0], name: "ReviewDrawing")
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try PrintRenderer(editor: editor).exportPDF(to: output.appendingPathComponent("ReviewDrawing.pdf"), title: "Review drawing", author: "Writer")
        }
        XCTAssertEqual(document.snapshot(), before)
    }
    func testFormattingMarksExcludeAcceptedHistoryAndNoteLabels() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph("Formatted")]
        let before = document, identity = RevisionIdentity(author: .init(name: "Writer"))
        document.sections[0].paragraphs[0].styleID = "heading1"
        try document.recordParagraphFormattingChanges(from: before, identity: identity)
        var note = DocumentNote(kind: .footnote); note.paragraphs = document.paragraphs
        let layout = try NoteTextLayout(note: try XCTUnwrap(NoteNumbering.resolve(referenceIDs: [note.id], notes: [note]).first), styles: document.styles, width: 450)
        let delegate = try XCTUnwrap(layout.layout.delegate as? ScreenTextAttributes)
        var range = NSRange(location: 0, length: layout.storage.length)
        let label = delegate.layoutManager(layout.layout, shouldUseTemporaryAttributes: [:], forDrawingToScreen: true, atCharacterIndex: 0, effectiveRange: &range)
        XCTAssertNil(label?[.underlineStyle])
        range = NSRange(location: 0, length: layout.storage.length)
        let marked = delegate.layoutManager(layout.layout, shouldUseTemporaryAttributes: [:], forDrawingToScreen: true, atCharacterIndex: 3, effectiveRange: &range)
        XCTAssertEqual(marked?[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue)
        XCTAssertEqual(range.location, 3)
        try document.resolveAllRevisions(accepting: true)
        let drawing = ReviewDrawingAttributes(), storage = AttributedDocument.render(document)
        range = NSRange(location: 0, length: storage.length)
        XCTAssertTrue(drawing.attributes([:], storage: storage, at: 0, effectiveRange: &range).isEmpty)
        XCTAssertNil(delegate.layoutManager(layout.layout, shouldUseTemporaryAttributes: [:], forDrawingToScreen: false, atCharacterIndex: 3, effectiveRange: &range))
    }
}
#endif
