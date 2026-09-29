#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ScriptProjectionTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testProjectionKeepsLogicalFontSizeAndRendersRaisedAndLoweredGlyphs() throws {
        let document = ScribeFileDocument()
        document.model.styles[0].text.fontSize = 20
        var up = TextRun("SUP"); up.format.baseline = 1
        var down = TextRun("SUB"); down.format.baseline = -1
        document.model.sections[0].paragraphs[0].runs = [TextRun("Base "), up, TextRun(" Base "), down, TextRun(" Base")]
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        for token in ["SUP", "SUB"] {
            let range = (editor.storage.string as NSString).range(of: token)
            let attributes = editor.storage.attributes(at: range.location, effectiveRange: nil)
            XCTAssertEqual((attributes[.font] as? NSFont)?.pointSize, 13)
            XCTAssertEqual(ScriptProjection.logicalFont(in: attributes)?.pointSize, 20)
        }
        let snapshot = document.snapshot()
        XCTAssertTrue(snapshot.paragraphs[0].runs.allSatisfy { $0.format.fontSize == nil })
        XCTAssertEqual(snapshot.paragraphs[0].runs.first { $0.text == "SUP" }?.format.baseline, 1)
        XCTAssertEqual(snapshot.paragraphs[0].runs.first { $0.text == "SUB" }?.format.baseline, -1)
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ScriptTypography.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Script typography", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url)), page = try XCTUnwrap(pdf.page(at: 0))
        let base = try XCTUnwrap(pdf.findString("Base", withOptions: []).first).bounds(for: page)
        let sup = try XCTUnwrap(pdf.findString("SUP", withOptions: []).first).bounds(for: page)
        let sub = try XCTUnwrap(pdf.findString("SUB", withOptions: []).first).bounds(for: page)
        XCTAssertLessThan(sup.height, base.height * 0.8); XCTAssertLessThan(sub.height, base.height * 0.8)
        XCTAssertGreaterThan(sup.midY, base.midY); XCTAssertLessThan(sub.midY, base.midY)
        XCTAssertTrue(page.bounds(for: .mediaBox).contains(sup)); XCTAssertTrue(page.bounds(for: .mediaBox).contains(sub))
    }
    func testRepeatedScriptFontChangesUndoAndRichClipboardKeepLogicalSize() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs[0].runs = [TextRun("Selected")]
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor, view = document.editorController!.editor.activeTextView
        editor.select(NSRange(location: 0, length: editor.storage.length))
        view.superscript(nil); view.superscript(nil)
        var attributes = editor.storage.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual((attributes[.font] as? NSFont)?.pointSize ?? 0, 7.8, accuracy: 0.01)
        XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].format.baseline, 1)
        view.toggleBold(nil)
        view.transformLogicalFonts(action: "Font Size") { NSFontManager.shared.convert($0, toSize: 24) }
        attributes = editor.storage.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual((attributes[.font] as? NSFont)?.pointSize ?? 0, 15.6, accuracy: 0.01)
        XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].format.fontSize, 24)
        XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].format.bold, true)
        let pasteboard = NSPasteboard.withUniqueName(); defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        for type in [NSPasteboard.PasteboardType.rtf, .rtfd] {
            let data = try XCTUnwrap(pasteboard.data(forType: type))
            let value = try NSAttributedString(data: data, options: [.documentType: type == .rtfd ? NSAttributedString.DocumentType.rtfd : .rtf], documentAttributes: nil)
            let imported = AttributedDocument.capture(value, preserving: ScribeDocument())
            XCTAssertEqual(imported.paragraphs[0].runs[0].format.fontSize, 24)
            XCTAssertEqual(imported.paragraphs[0].runs[0].format.baseline, 1)
        }
        document.undoManager?.removeAllActions()
        view.unscript(nil)
        XCTAssertEqual((editor.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 24)
        document.undoManager?.undo()
        XCTAssertEqual((editor.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0, 15.6, accuracy: 0.01)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document.snapshot())).paragraphs[0].runs[0].format.fontSize, 24)
    }
}
#endif
