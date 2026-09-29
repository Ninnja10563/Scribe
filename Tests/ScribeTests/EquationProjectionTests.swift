#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class EquationProjectionTests: XCTestCase {
    func testNativeEquationDialogInsertionEditingAndCancellation() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument(); document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            guard let content = NSApp.modalWindow?.contentView,
                  let source = descendants(content).compactMap({ $0 as? NSTextView }).first(where: { $0.identifier?.rawValue == "Equation Source" }),
                  let button = descendants(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Insert" }) else {
                XCTFail("Missing equation controls"); NSApp.abortModal(); return
            }
            source.string = #"\frac{-b+\sqrt{b^2-4ac}}{2a}"#; source.didChangeText()
            NativeDialogCapture.save(content, name: "EquationDialog")
            XCTAssertTrue(button.isEnabled); button.performClick(nil)
        }
        controller.insertEquation()
        let inserted = document.snapshot()
        XCTAssertEqual(inserted.paragraphs[0].runs.compactMap(\.equation).count, 1)
        document.undoManager?.undo(); XCTAssertTrue(document.snapshot().paragraphs[0].runs.compactMap(\.equation).isEmpty)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs[0].runs.compactMap(\.equation), inserted.paragraphs[0].runs.compactMap(\.equation))
        controller.editor.select(NSRange(location: 0, length: 1))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.abortModal() }
        controller.editEquation(); XCTAssertEqual(document.snapshot(), inserted)
        let options = EquationOptions(equation: nil)
        options.source.string = #"\frac{1}"#; options.refresh()
        XCTAssertNil(options.preview.equationLayout); XCTAssertFalse(options.errorLabel.stringValue.isEmpty)
        XCTAssertThrowsError(try controller.applyEquation(Equation(source: String(repeating: "x", count: 1000), pointSize: 144), replacing: NSRange(location: 0, length: 1), action: "Edit Equation"))
        XCTAssertEqual(document.snapshot(), inserted)
    }
    func testEquationsFlowAcrossPagesAndNarrowTableCellsBlockClippedOutput() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = try (1...60).map { index in
            var paragraph = Paragraph()
            var run = TextRun("\u{FFFC}"); run.equation = try Equation(source: #"\frac{x^2+1}{\sqrt{y}}"#, pointSize: 24)
            paragraph.runs = [TextRun("Formula \(index): "), run, TextRun(" End \(index).")]; return paragraph
        }
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        XCTAssertGreaterThan(editor.textViews.count, 2); XCTAssertNil(editor.outputWarning)
        XCTAssertEqual(document.snapshot().paragraphs.flatMap(\.runs).compactMap(\.equation).count, 60)
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("EquationPagination.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Equation pagination", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, editor.textViews.count)
        for index in 1...60 { XCTAssertTrue(pdf.string?.contains("Formula \(index):") == true) }
        editor.storage.enumerateAttribute(.scribeEquation, in: NSRange(location: 0, length: editor.storage.length)) { value, range, _ in
            guard value != nil else { return }
            let glyph = editor.layout.glyphIndexForCharacter(at: range.location)
            let container = editor.layout.textContainer(forGlyphAt: glyph, effectiveRange: nil)!
            let box = editor.layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            XCTAssertGreaterThanOrEqual(box.minY, -1); XCTAssertLessThanOrEqual(box.maxY, container.containerSize.height + 1)
        }
        let tableDocument = ScribeFileDocument()
        tableDocument.model.insertTable(rows: 1, columns: 2, after: tableDocument.model.paragraphs[0].id)
        let index = try XCTUnwrap(tableDocument.model.sections[0].paragraphs.firstIndex { $0.tableCell != nil })
        var wide = TextRun("\u{FFFC}"); wide.equation = try Equation(source: String(repeating: "x", count: 24), pointSize: 30)
        tableDocument.model.sections[0].paragraphs[index].runs = [wide]
        let tableEditor = PaginatedEditor(document: tableDocument); defer { tableEditor.prepareForClose() }
        XCTAssertNotNil(tableEditor.outputWarning, "A wide equation must not silently overpaint the adjacent cell")
        let huge = EquationProjection.attachment(try Equation(source: String(repeating: "x", count: 1000), pointSize: 144))
        XCTAssertLessThanOrEqual(huge.attachmentCell!.cellSize().width, 4000, "Untrusted native files must not allocate an enormous cached image")
    }
    func testOversizedImportedEquationCannotOverwriteAnExistingPDF() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        var run = TextRun("\u{FFFC}"); run.equation = try Equation(source: String(repeating: "x", count: 100), pointSize: 30)
        document.model.sections[0].paragraphs[0].runs = [run]
        let editor = PaginatedEditor(document: document); defer { editor.prepareForClose() }
        XCTAssertNotNil(editor.outputWarning)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("Preserve previous export".utf8); try bytes.write(to: url)
        XCTAssertThrowsError(try PrintRenderer(editor: editor).exportPDF(to: url, title: "", author: ""))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testEquationsSurviveNativeProjectionEditingAndPDF() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        var equation = TextRun("\u{FFFC}")
        equation.equation = try Equation(source: #"\frac{a+1}{b^2}"#, pointSize: 22)
        document.model.sections[0].paragraphs[0].runs = [TextRun("Before "), equation, TextRun(" after")]
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        XCTAssertEqual(document.snapshot().paragraphs[0].runs.compactMap(\.equation), [equation.equation!])
        let encoded = try document.data(ofType: "org.scribe.document")
        XCTAssertEqual(try NativeFormat.decode(encoded).paragraphs[0].runs.compactMap(\.equation), [equation.equation!])
        editor.select(NSRange(location: 8, length: 0))
        editor.activeTextView.insertText("new", replacementRange: NSRange(location: 8, length: 0))
        XCTAssertEqual(document.snapshot().paragraphs[0].runs.compactMap(\.equation).count, 1)
        try NativeFormat.validate(document.snapshot())
        let attachment = try XCTUnwrap(editor.storage.attribute(.attachment, at: 7, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertLessThan(attachment.attachmentCell!.cellBaselineOffset().y, 0)
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("NativeEquation.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Equation projection", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("Before") == true)
        XCTAssertTrue(pdf.string?.contains("1") == true)
        editor.select(NSRange(location: 7, length: 1))
        editor.activeTextView.replaceSelection(NSAttributedString(string: ""), action: "Delete Equation")
        XCTAssertTrue(document.snapshot().paragraphs[0].runs.compactMap(\.equation).isEmpty)
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs[0].runs.compactMap(\.equation), [equation.equation!])
    }
}
#endif
