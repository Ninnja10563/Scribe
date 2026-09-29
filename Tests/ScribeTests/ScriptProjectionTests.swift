#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ScriptProjectionTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testEmptyParagraphCharacterFormattingIsUndoableAndSurvivesReopening() throws {
        let document = ScribeFileDocument()
        document.makeWindowControllers(); defer { document.close() }
        let view = document.editorController!.editor.activeTextView
        document.undoManager?.removeAllActions()
        view.transformLogicalFonts(action: "Font Size") { NSFontManager.shared.convert($0, toSize: 24) }
        XCTAssertTrue(document.isDocumentEdited)
        XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].format.fontSize, 24)
        document.undoManager?.undo(); XCTAssertNil(document.snapshot().paragraphs[0].runs[0].format.fontSize)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].format.fontSize, 24)
        view.superscript(nil)
        let restored = ScribeFileDocument()
        restored.model = try NativeFormat.decode(document.data(ofType: "org.scribe.document"))
        restored.makeWindowControllers(); defer { restored.close() }
        let reopenedView = restored.editorController!.editor.activeTextView
        XCTAssertEqual(ScriptProjection.logicalFont(in: reopenedView.typingAttributes)?.pointSize, 24)
        XCTAssertEqual(ScriptProjection.level(in: reopenedView.typingAttributes), 1)
        reopenedView.insertText("Raised", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(restored.snapshot().paragraphs[0].runs[0].format.fontSize, 24)
        XCTAssertEqual(restored.snapshot().paragraphs[0].runs[0].format.baseline, 1)
        reopenedView.unscript(nil)
        reopenedView.insertText(" normal", replacementRange: reopenedView.selectedRange())
        XCTAssertEqual(restored.snapshot().paragraphs[0].runs.last?.format.baseline, nil)
        XCTAssertEqual(restored.snapshot().paragraphs[0].runs.last?.format.fontSize, 24)
    }
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
        editor.select(NSRange(location: 0, length: editor.storage.length))
        editor.activeTextView.updateFontPanel()
        XCTAssertEqual(NSFontManager.shared.selectedFont?.pointSize, 20)
        XCTAssertFalse(NSFontManager.shared.isMultiple, "Script rendering must not turn one logical font into a mixed-size selection")
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
    func testScriptRunsFlowAcrossPagesWithoutClippingOrLosingReferences() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = (0..<90).map { index in
            let suffix = String(format: "%03d", index)
            var paragraph = Paragraph()
            var up = TextRun("UP" + suffix); up.format.baseline = 1
            var down = TextRun("DOWN" + suffix); down.format.baseline = -1
            paragraph.runs = [TextRun("Paragraph " + suffix + ": " + String(repeating: "Flowing text with references. ", count: 4)), up, TextRun(" and "), down, TextRun(" continue in the same paragraph.")]
            return paragraph
        }
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        editor.paginate(); XCTAssertNil(editor.layoutWarning); XCTAssertGreaterThan(editor.canvas.pageCount, 2)
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ScriptTypography-Pages.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Script pagination", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, editor.canvas.pageCount)
        let p = document.model.sections[0].page
        let writingArea = NSRect(x: p.left, y: p.bottom, width: p.contentWidth, height: p.contentHeight).insetBy(dx: -2, dy: -2)
        for index in 0..<90 { for prefix in ["UP", "DOWN"] {
            let matches = pdf.findString(prefix + String(format: "%03d", index), withOptions: [])
            XCTAssertEqual(matches.count, 1)
            let match = try XCTUnwrap(matches.first), page = try XCTUnwrap(matches.first?.pages.first)
            XCTAssertTrue(writingArea.contains(match.bounds(for: page)), "Script reference escaped its page writing area")
        } }
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
