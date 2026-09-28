#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class TableOfContentsTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    func testContentsUsesActualPagesAndUpdatesWithSingleUndo() throws {
        let document = ScribeFileDocument()
        var paragraphs = [Paragraph("Cover")]
        for index in 1...30 {
            paragraphs.append(Paragraph("Section \(index): " + String(repeating: "Detailed heading ", count: 3), style: index.isMultiple(of: 3) ? "heading2" : "heading1"))
            paragraphs.append(Paragraph(String(repeating: "Body text with substantial content. ", count: 20)))
        }
        document.model.sections[0].paragraphs = paragraphs
        document.model.sections[0].pageNumbering = PageNumbering(format: .roman, start: 4)
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        editor.select(NSRange(location: 0, length: 0)); document.undoManager?.removeAllActions()
        controller.addTableOfContents(title: "Contents", maximumLevel: 2)
        var model = document.snapshot()
        XCTAssertEqual(model.tablesOfContents.count, 1)
        let entries = model.paragraphs.filter { $0.toc?.kind == .entry }
        XCTAssertEqual(entries.count, 30)
        let pages = controller.contentsPageLabels(model)
        for entry in entries {
            let id = try XCTUnwrap(entry.toc?.headingID)
            XCTAssertTrue(entry.text.hasSuffix("\t" + (pages[id] ?? "MISSING")))
        }
        XCTAssertNoThrow(try NativeFormat.validate(model))
        document.undoManager?.undo()
        XCTAssertTrue(document.snapshot().tablesOfContents.isEmpty)
        XCTAssertEqual(document.snapshot().paragraphs.map(\.text), paragraphs.map(\.text))
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().tablesOfContents.count, 1)
        let target = paragraphs[1].id
        document.performEdit("Rename heading") { value in
            let index = value.sections[0].paragraphs.firstIndex(where: { $0.id == target })!
            value.sections[0].paragraphs[index].runs = [TextRun("Renamed section")]
        }
        document.undoManager?.removeAllActions(); controller.updateTableOfContents()
        model = document.snapshot()
        XCTAssertTrue(model.paragraphs.first(where: { $0.toc?.headingID == target })!.text.hasPrefix("Renamed section\t"))
        document.undoManager?.undo()
        XCTAssertTrue(document.snapshot().paragraphs.first(where: { $0.toc?.headingID == target })!.text.hasPrefix("Section 1:"))
    }

    func testNewParagraphAfterGeneratedEntrySurvivesRefresh() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = [Paragraph("Cover"), Paragraph("Heading", style: "heading1")]
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        controller.addTableOfContents(title: "Contents", maximumLevel: 3)
        let model = document.snapshot(), entry = try XCTUnwrap(model.paragraphs.first(where: { $0.toc?.kind == .entry }))
        let range = (editor.storage.string as NSString).range(of: entry.text)
        editor.select(NSRange(location: NSMaxRange(range), length: 0))
        editor.activeTextView.insertNewline(nil); editor.activeTextView.insertText("Keep my note", replacementRange: editor.activeTextView.selectedRange())
        XCTAssertNil(document.snapshot().paragraphs.first(where: { $0.text == "Keep my note" })?.toc)
        controller.updateTableOfContents()
        XCTAssertTrue(document.snapshot().paragraphs.contains(where: { $0.text == "Keep my note" && $0.toc == nil }))
    }
}
#endif
