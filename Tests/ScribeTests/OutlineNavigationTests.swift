#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class OutlineNavigationTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func model() -> ScribeDocument {
        var model = ScribeDocument()
        model.sections[0].paragraphs = [Paragraph("Introduction", style: "heading1"), Paragraph("Body text"), Paragraph("Skipped level", style: "heading3"), Paragraph("Methods", style: "heading2"), Paragraph("Detail", style: "heading3"), Paragraph("Conclusion", style: "heading1")]
        return model
    }
    func testHierarchyUsesNearestPrecedingLowerHeadingAndRetainsCollapsedIdentity() {
        var model = model()
        let outline = DocumentOutlineView(frame: NSRect(x: 0, y: 0, width: 250, height: 400))
        outline.refresh(model.outline)
        XCTAssertEqual(outline.numberOfRows, 5)
        XCTAssertEqual(outline.roots.map(\.entry.title), ["Introduction", "Conclusion"])
        let introduction = outline.roots[0]
        XCTAssertEqual(introduction.children.map(\.entry.title), ["Skipped level", "Methods"])
        XCTAssertEqual(introduction.children[1].children.map(\.entry.title), ["Detail"])
        outline.collapseItem(introduction)
        XCTAssertEqual(outline.numberOfRows, 2)
        model.sections[0].paragraphs[0].runs = [TextRun("Renamed introduction")]
        outline.refresh(model.outline)
        XCTAssertTrue(outline.roots[0] === introduction)
        XCTAssertEqual(outline.numberOfRows, 2)
        XCTAssertEqual(outline.roots[0].entry.title, "Renamed introduction")
        outline.expandAllHeadings(); XCTAssertEqual(outline.numberOfRows, 5)
        outline.collapseAllHeadings(); XCTAssertEqual(outline.numberOfRows, 2)
        outline.refresh(model.outline); XCTAssertEqual(outline.numberOfRows, 2)
        outline.expandAllHeadings(); XCTAssertEqual(outline.numberOfRows, 5)
    }
    func testRefreshKeepsSelectionWithoutNavigatingAndHandlesRemovedHeadings() {
        var model = model()
        let outline = DocumentOutlineView(frame: .zero)
        outline.refresh(model.outline)
        var navigations = 0
        outline.navigate = { _, _ in navigations += 1 }
        outline.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
        XCTAssertEqual(navigations, 1)
        let selected = (outline.item(atRow: 3) as! DocumentOutlineView.Node).entry.id
        model.sections[0].paragraphs.insert(Paragraph("New child", style: "heading2"), at: 1)
        outline.refresh(model.outline)
        XCTAssertEqual(navigations, 1)
        XCTAssertEqual((outline.item(atRow: outline.selectedRow) as? DocumentOutlineView.Node)?.entry.id, selected)
        model.sections[0].paragraphs.removeAll { $0.id == selected }
        outline.refresh(model.outline)
        XCTAssertEqual(outline.selectedRow, -1)
        XCTAssertEqual(navigations, 1)
        model.sections[0].paragraphs = [Paragraph()]
        outline.refresh(model.outline); XCTAssertEqual(outline.numberOfRows, 0)
    }
    func testKeyboardNavigationKeepsFocusUntilReturnAndDoesNotEditDocument() throws {
        let document = ScribeFileDocument(); document.model = model()
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, window = controller.window!, outline = controller.outline
        window.makeKeyAndOrderFront(nil)
        controller.focusOutline()
        XCTAssertTrue(window.firstResponder === outline)
        func key(_ code: UInt16, _ characters: String) throws {
            outline.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)))
        }
        try key(123, "\u{f702}"); XCTAssertEqual(outline.numberOfRows, 2)
        try key(124, "\u{f703}"); XCTAssertEqual(outline.numberOfRows, 5)
        try key(125, "\u{f701}"); XCTAssertEqual(outline.selectedRow, 1)
        let before = document.snapshot()
        outline.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        XCTAssertTrue(window.firstResponder === outline)
        let expected = (controller.editor.storage.string as NSString).range(of: "Methods").location
        XCTAssertEqual(controller.editor.activeTextView.selectedRange().location, expected)
        controller.editor.select(NSRange(location: 0, length: 0), focus: false)
        outline.previewHeading()
        XCTAssertEqual(controller.editor.activeTextView.selectedRange().location, expected)
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        outline.keyDown(with: enter)
        XCTAssertTrue(window.firstResponder is ScribeTextView)
        controller.focusOutline(); outline.cancelOperation(nil)
        XCTAssertTrue(window.firstResponder is ScribeTextView)
        XCTAssertEqual(document.snapshot(), before)
        XCTAssertFalse(document.isDocumentEdited)
        controller.focusOutline()
        NativeDialogCapture.save(window.contentView!, name: "HierarchicalOutline")
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let title = try XCTUnwrap(descendants(controller.sidebar).compactMap { $0 as? NSTextField }.first { $0.stringValue == "OUTLINE" })
        XCTAssertGreaterThan(title.frame.height, 8)
        XCTAssertGreaterThan(title.frame.width, 20)
    }
}
#endif
