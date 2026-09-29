#if canImport(AppKit)
import AppKit
import XCTest
@testable import Scribe

@MainActor final class StartupWindowTests: XCTestCase {
    func testDocumentRegistersAndShowsItsEditorWindow() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        defer { document.close() }
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.editorController)
        XCTAssertEqual(document.windowControllers.count, 1)
        XCTAssertTrue(document.windowControllers.first === controller)
        XCTAssertTrue(controller.document === document)
        document.showWindows()
        XCTAssertTrue(controller.window?.isVisible == true)
        controller.editor.activeTextView.insertText("Visible editor accepts typing", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(document.snapshot().paragraphs[0].text.contains("Visible editor accepts typing"))
        document.updateChangeCount(.changeCleared)
    }
}
#endif
