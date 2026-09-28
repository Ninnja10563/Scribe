#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class EditorTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
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
