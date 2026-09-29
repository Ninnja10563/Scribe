#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class LineHeightNativeTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testProjectionAndCapturePreserveInheritedHeight() throws {
        for rule in ParagraphLineHeight.Rule.allCases {
            var source = ScribeDocument()
            let height = ParagraphLineHeight(rule: rule, value: rule == .multiple ? 1.5 : 24)
            source.styles[0].paragraph.lineHeight = height
            source.styles[0].paragraph.lineSpacing = 0
            source.sections[0].paragraphs = [Paragraph("First line\u{2028}Second line")]
            let rendered = AttributedDocument.render(source)
            let native = try XCTUnwrap(rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            XCTAssertEqual(AttributedDocument.paragraphFormatting(native).lineHeight, height)
            let captured = AttributedDocument.capture(rendered, preserving: source)
            XCTAssertNil(captured.paragraphs[0].formatting)
            XCTAssertEqual(captured.styles[0].paragraph.lineHeight, height)
        }
    }
    func testParagraphHeightUndoAndRedo() throws {
        for text in ["Text", ""] {
            let document = ScribeFileDocument()
            document.model.sections[0].paragraphs = [Paragraph(text)]
            document.makeWindowControllers(); defer { document.close() }
            document.undoManager?.removeAllActions()
            let controller = try XCTUnwrap(document.editorController)
            let before = document.snapshot()
            let height = ParagraphLineHeight(rule: .exact, value: 24)
            try controller.applyParagraphGeometry([0, 0, 0, 0, 0, 0], lineHeight: height)
            XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.lineHeight, height)
            document.undoManager?.undo()
            XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
            document.undoManager?.redo()
            XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.lineHeight, height)
        }
    }
    func testStyleControlsValidateAndPreserveHeight() throws {
        var style = ParagraphStyle(id: "height", name: "Height")
        style.paragraph.lineHeight = .init(rule: .minimum, value: 22)
        let options = StyleEditorOptions(style: style)
        XCTAssertEqual(try options.value(contentWidth: 450).paragraph.lineHeight, style.paragraph.lineHeight)
        options.lineHeight.mode.selectItem(at: 1)
        if let action = options.lineHeight.mode.action { NSApp.sendAction(action, to: options.lineHeight.mode.target, from: options.lineHeight.mode) }
        XCTAssertEqual(try options.value(contentWidth: 450).paragraph.lineHeight, .init(rule: .multiple, value: 1.5))
        XCTAssertEqual(try options.value(contentWidth: 450).paragraph.lineSpacing, 0)
        options.lineHeight.amount.stringValue = "nan"
        XCTAssertThrowsError(try options.value(contentWidth: 450))
    }
    func testParagraphDialogAppliesExactHeight() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = [Paragraph("Dialog spacing")]
        document.makeWindowControllers(); defer { document.close() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            guard let content = NSApp.modalWindow?.contentView else { XCTFail("Missing paragraph dialog"); NSApp.abortModal(); return }
            let views = descendants(content)
            guard let mode = views.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.identifier?.rawValue == "Line height mode" }),
                  let amount = views.compactMap({ $0 as? NSTextField }).first(where: { $0.identifier?.rawValue == "Line height value" }),
                  let apply = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Apply" }) else { XCTFail("Missing controls"); NSApp.abortModal(); return }
            mode.selectItem(at: 3)
            if let action = mode.action { NSApp.sendAction(action, to: mode.target, from: mode) }
            amount.stringValue = "24"
            NativeDialogCapture.save(content, name: "LineHeightParagraphDialog")
            apply.performClick(nil)
        }
        document.editorController!.paragraphSettings()
        XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.lineHeight, .init(rule: .exact, value: 24))
        XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.lineSpacing, 0)
    }
    func testExportMeasuredLineHeightFixtures() throws {
        let modes: [(String, ParagraphLineHeight?)] = [("natural", nil), ("multiple", .init(rule: .multiple, value: 1.5)), ("minimum", .init(rule: .minimum, value: 24)), ("exact", .init(rule: .exact, value: 24))]
        for (name, height) in modes {
            var source = ScribeDocument()
            source.sections[0].paragraphs = [Paragraph("First line\u{2028}Second line\u{2028}Third line")]
            source.styles[0].text.fontFamily = "Helvetica"; source.styles[0].text.fontSize = 12
            source.styles[0].paragraph.lineHeight = height; source.styles[0].paragraph.lineSpacing = 0
            source.styles[0].paragraph.spaceBefore = 0; source.styles[0].paragraph.spaceAfter = 0
            let session = try ReviewOutputSession(source: source, mode: .accepted); defer { session.close() }
            XCTAssertNil(session.editor.layoutWarning)
            if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try session.renderer.exportPDF(to: folder.appendingPathComponent("LineHeightNative-" + name + ".pdf"), title: name, author: "Scribe")
            }
        }
    }
}
#endif
