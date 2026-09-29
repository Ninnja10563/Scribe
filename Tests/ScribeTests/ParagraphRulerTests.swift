#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
import ImportExport
@testable import Scribe

@MainActor final class ParagraphRulerTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func event(_ type: NSEvent.EventType, point: NSPoint, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    func testDragCommitsOneUndoAndPreservesOtherParagraphGeometry() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = [Paragraph("A paragraph with an independent first line.")]
        var format = ParagraphFormatting(); format.firstLineIndent = 18; format.spaceBefore = 12; format.alignment = .justified
        document.model.sections[0].paragraphs[0].formatting = format
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor, window = controller.window!
        controller.showWindow(nil); window.contentView?.layoutSubtreeIfNeeded(); editor.resizeCanvas()
        let ruler = try XCTUnwrap(editor.paragraphRuler), handle = try XCTUnwrap(ruler.handles.first { $0.indent == .left })
        ruler.refresh(); document.undoManager?.removeAllActions()
        let start = handle.convert(NSPoint(x: 8, y: 7), to: nil)
        try handle.mouseDown(with: event(.leftMouseDown, point: start, window: window))
        let target = NSPoint(x: start.x + 36 * editor.zoom, y: start.y)
        try handle.mouseDragged(with: event(.leftMouseDragged, point: target, window: window))
        XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.headIndent, 0)
        XCTAssertFalse(document.undoManager!.canUndo)
        try handle.mouseUp(with: event(.leftMouseUp, point: target, window: window))
        let result = document.snapshot().paragraphs[0].formatting
        XCTAssertEqual(result?.headIndent, 36); XCTAssertEqual(result?.firstLineIndent, 18)
        XCTAssertEqual(result?.spaceBefore, 12); XCTAssertEqual(result?.alignment, .justified)
        XCTAssertTrue(document.isDocumentEdited)
        XCTAssertEqual(try NativeFormat.decode(document.data(ofType: ScribeFileDocument.typeName)).paragraphs[0].formatting, result)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.headIndent, 0)
        XCTAssertFalse(document.undoManager!.canUndo)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.headIndent, 36)
        NativeDialogCapture.save(window.contentView!, name: "ParagraphRuler")
    }
    func testRulerCoordinatesFollowZoomAndHorizontalScroll() throws {
        let document = ScribeFileDocument(); document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        controller.showWindow(nil); controller.window?.contentView?.layoutSubtreeIfNeeded()
        let ruler = try XCTUnwrap(editor.paragraphRuler)
        for zoom in [0.5, 1.0, 2.0] {
            editor.zoom = zoom; editor.resizeCanvas()
            editor.scrollView.contentView.scroll(to: NSPoint(x: zoom == 2 ? 100 : 0, y: 0))
            ruler.updateGeometry()
            let page = editor.canvas.pageRect(0), settings = editor.canvas.pageSettings
            let point = ruler.convert(NSPoint(x: page.minX + settings.left + 42, y: 0), from: editor.canvas)
            XCTAssertEqual(ruler.value(at: point, for: .left), 42, accuracy: 0.01)
            XCTAssertEqual(ruler.value(at: point, for: .right), settings.contentWidth - 42, accuracy: 0.01)
            let left = try XCTUnwrap(ruler.handles.first { $0.indent == .left })
            let zero = ruler.convert(NSPoint(x: page.minX + settings.left, y: 0), from: editor.canvas)
            XCTAssertEqual(left.frame.midX, zero.x, accuracy: 0.01)
        }
        controller.toggleFocus(); XCTAssertFalse(editor.scrollView.rulersVisible)
        controller.toggleFocus(); XCTAssertTrue(editor.scrollView.rulersVisible)
        controller.toggleRuler(); controller.toggleFocus(); controller.toggleFocus()
        XCTAssertFalse(editor.scrollView.rulersVisible)
    }
    func testAccessibilityAdjustmentAndEmptyParagraphPersistence() throws {
        let document = ScribeFileDocument(); document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor, ruler = try XCTUnwrap(editor.paragraphRuler)
        ruler.refresh()
        let handle = try XCTUnwrap(ruler.handles.first { $0.indent == .firstLine })
        XCTAssertEqual(handle.accessibilityRole(), .slider)
        XCTAssertTrue(handle.accessibilityPerformIncrement())
        XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.firstLineIndent, 1)
        handle.setAccessibilityValue(NSNumber(value: 24))
        XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.firstLineIndent, 24)
        XCTAssertEqual((handle.accessibilityValue() as? NSNumber)?.doubleValue, 24)
        XCTAssertEqual(try NativeFormat.decode(document.data(ofType: ScribeFileDocument.typeName)).paragraphs[0].formatting?.firstLineIndent, 24)
        XCTAssertTrue(handle.accessibilityPerformDecrement())
        XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.firstLineIndent, 23)
        editor.activeTextView.insertText("Indented", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.firstLineIndent, 23)
    }
    func testCancelAndStaleDragDoNotModifyDocument() throws {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = [Paragraph("One"), Paragraph("Two")]
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor, window = controller.window!
        controller.showWindow(nil); window.contentView?.layoutSubtreeIfNeeded()
        let ruler = try XCTUnwrap(editor.paragraphRuler), handle = ruler.handles[0]
        ruler.refresh(); document.undoManager?.removeAllActions()
        let start = handle.convert(NSPoint(x: 8, y: 7), to: nil), target = NSPoint(x: start.x + 48, y: start.y)
        try handle.mouseDown(with: event(.leftMouseDown, point: start, window: window))
        try handle.mouseDragged(with: event(.leftMouseDragged, point: target, window: window))
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        handle.keyDown(with: escape)
        try handle.mouseUp(with: event(.leftMouseUp, point: target, window: window))
        XCTAssertFalse(document.undoManager!.canUndo); XCTAssertNil(document.snapshot().paragraphs[0].formatting)
        try handle.mouseDown(with: event(.leftMouseDown, point: start, window: window))
        try handle.mouseDragged(with: event(.leftMouseDragged, point: target, window: window))
        editor.select(NSRange(location: 4, length: 0))
        try handle.mouseUp(with: event(.leftMouseUp, point: target, window: window))
        XCTAssertNil(document.snapshot().paragraphs[0].formatting); XCTAssertNil(document.snapshot().paragraphs[1].formatting)
    }
    func testMixedSelectionPreservesIndependentSpacingAndDisablesForLists() throws {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = [Paragraph("One"), Paragraph("Two")]
        var format = ParagraphFormatting(); format.firstLineIndent = 24; format.spaceBefore = 18
        document.model.sections[0].paragraphs[1].formatting = format
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor, ruler = try XCTUnwrap(editor.paragraphRuler)
        editor.select(NSRange(location: 0, length: editor.storage.length)); ruler.refresh()
        let handle = ruler.handles[0]; XCTAssertTrue(handle.isMixed)
        ruler.commit(handle, value: 36)
        XCTAssertEqual(document.snapshot().paragraphs.map { $0.formatting?.firstLineIndent }, [36, 36])
        XCTAssertEqual(document.snapshot().paragraphs[1].formatting?.spaceBefore, 18)
        editor.applyList(ListDescriptor()); ruler.refresh()
        XCTAssertTrue(ruler.handles.allSatisfy { !$0.isEnabled })
        XCTAssertFalse(handle.accessibilityPerformIncrement())
    }
}
#endif
