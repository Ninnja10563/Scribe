#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ImageResizeTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func document() -> ScribeFileDocument {
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAKElEQVR4nGP4z8BAEiJNNRlo1IJRCwbAAlJ1/P/PQBIatWDUgiFgAQAk0H2fCntH2wAAAABJRU5ErkJggg==")!
        let document = ScribeFileDocument()
        var run = TextRun("\u{FFFC}"); run.image = InlineImage(data: data, fileExtension: "png", width: 200, height: 100, altText: "Resize test")
        var paragraph = Paragraph(); paragraph.runs = [run]
        document.model.sections[0].paragraphs = [paragraph, Paragraph("After image")]
        document.makeWindowControllers(); document.editorController?.showWindow(nil)
        document.editorController?.editor.select(NSRange(location: 0, length: 1))
        document.editorController?.window?.contentView?.layoutSubtreeIfNeeded()
        return document
    }
    private func mouse(_ type: NSEvent.EventType, point: NSPoint, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    func testVerticalGestureCommitsOneUndoAndKeepsOriginalBytes() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, view = editor.activeTextView, window = document.editorController!.window!
        let original = try XCTUnwrap(document.snapshot().paragraphs[0].runs[0].image)
        let frame = try XCTUnwrap(view.selectedImageFrame)
        let start = view.convert(NSPoint(x: frame.maxX, y: frame.maxY), to: nil)
        let end = view.convert(NSPoint(x: frame.maxX, y: frame.maxY + 50), to: nil)
        document.undoManager?.removeAllActions()
        NSApp.postEvent(try mouse(.leftMouseDragged, point: end, window: window), atStart: false)
        NSApp.postEvent(try mouse(.leftMouseUp, point: end, window: window), atStart: false)
        XCTAssertTrue(try view.resizeImageIfNeeded(with: mouse(.leftMouseDown, point: start, window: window)))
        let changed = try XCTUnwrap(document.snapshot().paragraphs[0].runs[0].image)
        XCTAssertEqual(changed.width, 300, accuracy: 0.01); XCTAssertEqual(changed.height, 150, accuracy: 0.01)
        XCTAssertEqual(changed.data, original.data)
        XCTAssertEqual(try NativeFormat.decode(document.data(ofType: ScribeFileDocument.typeName)).paragraphs[0].runs[0].image, changed)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].image, original)
        XCTAssertFalse(document.undoManager!.canUndo)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].image, changed)
    }
    func testEscapeRestoresPreviewWithoutUndoOrSourceChanges() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, view = editor.activeTextView, window = document.editorController!.window!
        let original = document.snapshot(), frame = try XCTUnwrap(view.selectedImageFrame)
        let start = view.convert(NSPoint(x: frame.maxX, y: frame.maxY), to: nil)
        let end = view.convert(NSPoint(x: frame.maxX + 80, y: frame.maxY), to: nil)
        document.undoManager?.removeAllActions()
        NSApp.postEvent(try mouse(.leftMouseDragged, point: end, window: window), atStart: false)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.postEvent(escape, atStart: false)
        XCTAssertTrue(try view.resizeImageIfNeeded(with: mouse(.leftMouseDown, point: start, window: window)))
        XCTAssertEqual(document.snapshot(), original); XCTAssertFalse(document.undoManager!.canUndo)
        XCTAssertEqual(try XCTUnwrap(view.selectedImageFrame).width, frame.width, accuracy: 0.01)
    }
    func testSelectionHandlesAppearOnlyOnImagePageAndGeometryRespectsBounds() throws {
        let document = document(); defer { document.close() }
        document.performEdit("Page break") { $0.sections[0].paragraphs.insert(Paragraph("First page"), at: 0); $0.sections[0].paragraphs[1].pageBreakBefore = true }
        let editor = document.editorController!.editor
        let range = (editor.storage.string as NSString).range(of: "\u{FFFC}")
        editor.select(range); editor.paginate()
        XCTAssertEqual(editor.textViews.count, 2)
        XCTAssertNil(editor.textViews[0].selectedImageFrame)
        XCTAssertNotNil(editor.textViews[1].selectedImageFrame)
        XCTAssertEqual(ImageResizeGeometry.scale(width: 200, height: 100, horizontalChange: 1000, verticalChange: 0, maximumWidth: 400, maximumHeight: 150), 1.5)
        XCTAssertEqual(ImageResizeGeometry.scale(width: 200, height: 100, horizontalChange: 0, verticalChange: -50, maximumWidth: 400, maximumHeight: 500), 0.5)
    }
}
#endif
