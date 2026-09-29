#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class StyleEditorTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testModifyDefinitionUpdatesInheritedFormattingAndPreservesOverrides() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = [Paragraph("First heading", style: "heading1"), Paragraph("Second heading", style: "heading1"), Paragraph("Direct heading", style: "heading1")]
        document.model.sections[0].paragraphs[2].runs[0].format.fontSize = 31
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        editor.jump(to: document.model.paragraphs[0].id)
        document.undoManager?.removeAllActions()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            guard let content = NSApp.modalWindow?.contentView else { XCTFail("Missing style dialog"); NSApp.abortModal(); return }
            let views = descendants(content)
            guard let size = views.compactMap({ $0 as? NSTextField }).first(where: { $0.identifier?.rawValue == "Size (pt)" }) else { XCTFail("Missing size field"); NSApp.abortModal(); return }
            size.stringValue = "18"
            NativeDialogCapture.save(content, name: "StyleTextDialog")
            if let tabs = views.compactMap({ $0 as? NSTabView }).first {
                tabs.selectTabViewItem(at: 1)
                for field in descendants(content).compactMap({ $0 as? NSTextField }) where field.identifier?.rawValue == "Space before" { field.stringValue = "24" }
                NativeDialogCapture.save(content, name: "StyleParagraphDialog")
            }
            guard let button = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Apply" }) else { XCTFail("Missing Apply"); NSApp.abortModal(); return }
            button.performClick(nil)
        }
        controller.editStyle()
        func fontSize(_ text: String) -> CGFloat? {
            let range = (editor.storage.string as NSString).range(of: text)
            return (editor.storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.pointSize
        }
        XCTAssertEqual(fontSize("First heading"), 18); XCTAssertEqual(fontSize("Second heading"), 18); XCTAssertEqual(fontSize("Direct heading"), 31)
        XCTAssertEqual(document.snapshot().styles.first { $0.id == "heading1" }?.paragraph.spaceBefore, 24)
        document.undoManager?.undo(); XCTAssertEqual(fontSize("First heading"), 22); XCTAssertEqual(fontSize("Direct heading"), 31)
        document.undoManager?.redo(); XCTAssertEqual(fontSize("First heading"), 18)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document.snapshot())).styles, document.snapshot().styles)
    }
    func testCreateAndApplyIsOneUndoableOperationAndDuplicateNamesAreRejected() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = [Paragraph("First"), Paragraph("Second"), Paragraph("Third")]
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        editor.activeTextView.setSelectedRange(NSRange(location: 0, length: 12))
        document.undoManager?.removeAllActions()
        var style = ParagraphStyle(id: UUID().uuidString, name: "Report section", size: 19, bold: true, headingLevel: 2)
        style.paragraph.spaceBefore = 12
        try controller.saveStyleDefinition(style, applying: true)
        XCTAssertEqual(document.snapshot().paragraphs.map(\.styleID), [style.id, style.id, "normal"])
        XCTAssertEqual(document.snapshot().outline.count, 2)
        document.undoManager?.undo()
        XCTAssertFalse(document.snapshot().styles.contains { $0.id == style.id })
        XCTAssertEqual(document.snapshot().paragraphs.map(\.styleID), ["normal", "normal", "normal"])
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().outline.count, 2)
        var duplicate = style; duplicate.id = UUID().uuidString; duplicate.name = "REPORT SECTION"
        let before = document.snapshot()
        XCTAssertThrowsError(try controller.saveStyleDefinition(duplicate, applying: true))
        XCTAssertEqual(document.snapshot(), before)
    }
}
#endif
