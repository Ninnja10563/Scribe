#if canImport(AppKit)
import AppKit
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
    func testProjectionPreservesStylesAndUnicode() {
        var doc = ScribeDocument()
        doc.sections[0].paragraphs = [Paragraph("Heading 👩🏽‍💻", style: "heading1"), Paragraph("Body café"), Paragraph("")]
        let rendered = AttributedDocument.render(doc)
        let roundTrip = AttributedDocument.capture(rendered, preserving: doc)
        XCTAssertEqual(roundTrip.plainText, doc.plainText)
        XCTAssertEqual(roundTrip.paragraphs[0].id, doc.paragraphs[0].id)
        XCTAssertEqual(roundTrip.paragraphs[0].styleID, "heading1")
        XCTAssertNil(roundTrip.paragraphs[0].runs[0].format.fontSize)
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
        document.model.sections[0].paragraphs = [Paragraph("First page"), second]
        let editor = PaginatedEditor(document: document)
        XCTAssertGreaterThanOrEqual(editor.textViews.count, 2)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Test", author: "Scribe")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
        XCTAssertGreaterThan(data.count, 1000)
    }
}
#else
import XCTest
final class PlatformTests: XCTestCase {
    func testNativeEditorRequiresMacOS() throws { throw XCTSkip("AppKit pagination and UI tests run on macOS CI") }
}
#endif
