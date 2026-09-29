#if canImport(AppKit)
import AppKit
import XCTest
@testable import Scribe

@MainActor final class WindowLifetimeTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testWindowCloseAlsoDetachesEditorCallbacks() {
        let document = ScribeFileDocument(); document.makeWindowControllers()
        defer { document.close() }
        let controller = document.editorController!
        controller.window?.close()
        XCTAssertTrue(controller.isClosing)
        XCTAssertNil(controller.editor.onSelection)
        XCTAssertNil(controller.editor.layout.delegate)
    }
    func testClosingCancelsPendingUIWorkBeforeDocumentDetaches() async throws {
        let document = ScribeFileDocument(); document.makeWindowControllers()
        let controller = document.editorController!, editor = controller.editor
        controller.scheduleStatistics()
        controller.searchBar.query.stringValue = "text"; controller.searchBar.search()
        editor.activeTextView.insertText("Some text", replacementRange: NSRange(location: 0, length: 0))
        document.close()
        XCTAssertTrue(controller.isClosing)
        XCTAssertNil(editor.owner); XCTAssertNil(editor.layout.delegate); XCTAssertNil(editor.storage.delegate)
        XCTAssertTrue(editor.textViews.allSatisfy { $0.delegate == nil && $0.editor == nil })
        controller.document = nil
        // Delayed callbacks must not reach the now-detached NSWindowController.
        try await Task.sleep(nanoseconds: 400_000_000)
        controller.updateStatus(); controller.refreshOutline(); controller.scheduleStatistics()
    }
}
#endif
