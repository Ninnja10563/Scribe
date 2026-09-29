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
