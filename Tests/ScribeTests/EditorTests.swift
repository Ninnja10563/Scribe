#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class EditorTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testEmptyDocumentStyleAndFormattingUndo() throws {
        let document = ScribeFileDocument(); document.makeWindowControllers()
        defer { document.close() }
        let editor = document.editorController!.editor
        editor.applyStyle("heading1")
        XCTAssertEqual(document.snapshot().paragraphs[0].styleID, "heading1")
        let view = editor.activeTextView
        view.insertText("A heading", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(document.snapshot().paragraphs[0].styleID, "heading1")
        XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, 22)
        document.undoManager?.removeAllActions()
        document.performEdit("Landscape") { $0.sections[0].page = PageSettings(paper: .letter, landscape: true) }
        XCTAssertEqual(document.model.sections[0].page.width, 792)
        document.undoManager?.undo()
        XCTAssertEqual(document.model.sections[0].page.width, 595.276)
        document.undoManager?.redo()
        XCTAssertEqual(document.model.sections[0].page.width, 792)
    }
    func testListsAreVisibleAndRemainSemanticAfterRoundTrip() {
        var document = ScribeDocument()
        document.sections[0].paragraphs = [Paragraph("First"), Paragraph("Second")]
        for i in 0...1 { document.sections[0].paragraphs[i].list = ListDescriptor(kind: .decimal) }
        let rendered = AttributedDocument.render(document)
        XCTAssertTrue(rendered.string.contains("1.\tFirst"))
        XCTAssertTrue(rendered.string.contains("2.\tSecond"))
        let captured = AttributedDocument.capture(rendered, preserving: document)
        XCTAssertEqual(captured.plainText, "First\nSecond")
        XCTAssertEqual(captured.paragraphs[1].list?.kind, .decimal)
    }
    func testListReturnBackspaceAndUndo() throws {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs[0] = Paragraph("FirstSecond")
        document.model.sections[0].paragraphs[0].list = .init(kind: .decimal, start: 4, restart: true)
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: 9, length: 0)) // tab + 4. + tab + First
        document.undoManager?.removeAllActions()
        editor.activeTextView.insertNewline(nil)
        XCTAssertEqual(document.snapshot().paragraphs.map(\.text), ["First", "Second"])
        XCTAssertTrue(editor.storage.string.contains("5.\tSecond"))
        XCTAssertEqual(editor.activeTextView.selectedRange().location, 14)
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().plainText, "FirstSecond")
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().paragraphs.count, 2)
        editor.selectListContent(id: document.model.paragraphs[1].id)
        editor.activeTextView.deleteBackward(nil)
        XCTAssertNil(document.snapshot().paragraphs[1].list)
        XCTAssertEqual(document.snapshot().paragraphs[1].text, "Second")
    }
    func testTableAndImageProjectionPreservesNativeObjects() throws {
        var document = ScribeDocument()
        document.insertTable(rows: 3, columns: 3, after: document.paragraphs[0].id)
        document.sections[0].paragraphs[1].runs = [TextRun("Header")]
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNwSev4DwAEVgIy41TneAAAAABJRU5ErkJggg==")!
        var run = TextRun("\u{FFFC}"); run.image = InlineImage(data: data, fileExtension: "png", width: 40, height: 40, altText: "Example")
        document.sections[0].paragraphs[document.paragraphs.count - 1].runs = [run]
        let rendered = AttributedDocument.render(document)
        XCTAssertTrue(rendered.containsAttachments)
        let captured = AttributedDocument.capture(rendered, preserving: document)
        XCTAssertEqual(captured.tables, document.tables)
        XCTAssertEqual(captured.paragraphs.filter { $0.tableCell != nil }.count, 9)
        XCTAssertEqual(captured.paragraphs.last?.runs.last?.image, run.image)
        try NativeFormat.validate(captured)
        let file = ScribeFileDocument(); file.model = captured
        let editor = PaginatedEditor(document: file)
        XCTAssertGreaterThan(editor.layout.numberOfGlyphs, 0)
        XCTAssertLessThan(editor.textViews.count, 4)
    }
    func testNativeDocumentControllerCreatesAndReopensFile() throws {
        let controller = ScribeDocumentController()
        print("Document lifecycle: creating untitled")
        let document = try controller.makeUntitledDocument(ofType: ScribeFileDocument.typeName) as! ScribeFileDocument
        document.model.sections[0].paragraphs = [Paragraph("Saved through NSDocument", style: "heading1")]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".scribe")
        defer { try? FileManager.default.removeItem(at: url) }
        print("Document lifecycle: writing")
        try document.write(to: url, ofType: ScribeFileDocument.typeName)
        print("Document lifecycle: reopening")
        let reopened = try ScribeFileDocument(contentsOf: url, ofType: ScribeFileDocument.typeName)
        XCTAssertEqual(reopened.model.plainText, "Saved through NSDocument")
        XCTAssertEqual(reopened.model.outline.count, 1)
    }
    func testSearchNavigationAfterDeletingMatchesIsSafe() {
        let file = ScribeFileDocument(); file.makeWindowControllers()
        defer { file.close() }
        let controller = file.editorController!, view = file.editorController!.editor.activeTextView
        view.insertText("needle needle", replacementRange: NSRange(location: 0, length: 0))
        controller.searchBar.query.stringValue = "needle"
        controller.searchBar.next()
        XCTAssertEqual(view.selectedRange().length, 6)
        view.insertText("x", replacementRange: NSRange(location: 0, length: controller.editor.storage.length))
        controller.searchBar.next()
        XCTAssertLessThanOrEqual(NSMaxRange(view.selectedRange()), controller.editor.storage.length)
    }
    func testUndecodableImageRetainsOriginalBytes() throws {
        var document = ScribeDocument()
        var run = TextRun("\u{FFFC}")
        run.image = InlineImage(data: Data("damaged PNG".utf8), fileExtension: "png", width: 120, height: 50, altText: "Preserve me")
        document.sections[0].paragraphs[0].runs = [run]
        let rendered = AttributedDocument.render(document)
        XCTAssertTrue(rendered.containsAttachments)
        XCTAssertEqual(AttributedDocument.capture(rendered, preserving: document).paragraphs[0].runs[0].image, run.image)
    }
    func testProjectionPreservesStylesAndUnicode() {
        var doc = ScribeDocument()
        doc.sections[0].paragraphs = [Paragraph("Heading 👩🏽‍💻", style: "heading1"), Paragraph("Body café"), Paragraph("")]
        let rendered = AttributedDocument.render(doc)
        let roundTrip = AttributedDocument.capture(rendered, preserving: doc)
        XCTAssertEqual(roundTrip.plainText, doc.plainText)
        XCTAssertEqual(roundTrip.paragraphs[0].id, doc.paragraphs[0].id)
        XCTAssertEqual(roundTrip.paragraphs[0].styleID, "heading1")
        XCTAssertNil(roundTrip.paragraphs[0].runs[0].format.fontSize)
        XCTAssertNil(roundTrip.paragraphs[0].runs[0].format.foreground)
    }
    func testTextFlowsAndRepaginatesAfterGeometryChanges() {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = (0..<200).map { Paragraph("Paragraph \($0). " + String(repeating: "Text flows between physical pages. ", count: 10)) }
        let editor = PaginatedEditor(document: document)
        editor.paginate()
        XCTAssertGreaterThan(editor.textViews.count, 10)
        let count = editor.textViews.count
        var page = document.model.sections[0].page; page.left = 130; page.right = 130
        editor.setPageSettings(page); XCTAssertGreaterThan(editor.textViews.count, count)
        var covered = 0
        for container in editor.layout.textContainers {
            let range = editor.layout.glyphRange(for: container)
            XCTAssertEqual(range.location, covered); covered = NSMaxRange(range)
        }
        XCTAssertEqual(covered, editor.layout.numberOfGlyphs)
        editor.storage.setAttributedString(NSAttributedString(string: "Short")); editor.paginate()
        XCTAssertEqual(editor.textViews.count, 1)
    }
    func testTwoHundredPageLayoutReusesExistingContainers() {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = (0..<1600).map { Paragraph("Paragraph \($0). " + String(repeating: "Document layout must preserve glyph coverage and page continuity. ", count: 6)) }
        let start = Date()
        let editor = PaginatedEditor(document: document)
        XCTAssertGreaterThan(editor.textViews.count, 200)
        let first = editor.textViews[0]
        let initialTime = Date().timeIntervalSince(start)
        let editStart = Date()
        editor.storage.replaceCharacters(in: NSRange(location: editor.storage.length - 1, length: 0), with: "x")
        editor.paginate()
        XCTAssertTrue(editor.textViews[0] === first)
        XCTAssertEqual(NSMaxRange(editor.layout.glyphRange(for: editor.layout.textContainers.last!)), editor.layout.numberOfGlyphs)
        print("Large layout: \(editor.textViews.count) pages; initial \(initialTime)s; end edit \(Date().timeIntervalSince(editStart))s")
    }
    func testPageBreakAndPDFOutput() throws {
        let document = ScribeFileDocument()
        var second = Paragraph("Second page"); second.pageBreakBefore = true
        var first = Paragraph("First page"); first.runs[0].link = "https://example.com"
        document.model.sections[0].paragraphs = [first, second]
        let editor = PaginatedEditor(document: document)
        XCTAssertGreaterThanOrEqual(editor.textViews.count, 2)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Test", author: "Scribe")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
        XCTAssertGreaterThan(data.count, 1000)
        let pdf = PDFDocument(url: url)
        XCTAssertEqual(pdf?.pageCount, editor.textViews.count)
        XCTAssertTrue(pdf?.page(at: 0)?.annotations.contains(where: { $0.action is PDFActionURL }) == true)
    }
}
#else
import XCTest
final class PlatformTests: XCTestCase {
    func testNativeEditorRequiresMacOS() throws { throw XCTSkip("AppKit pagination and UI tests run on macOS CI") }
}
#endif
