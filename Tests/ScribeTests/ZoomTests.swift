#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ZoomTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testFitPageHonorsBothDimensionsAndViewportChanges() {
        let document = ScribeFileDocument()
        document.model.sections[0].page = PageSettings(paper: .legal, landscape: true)
        let editor = PaginatedEditor(document: document)
        editor.scrollView.frame = NSRect(x: 0, y: 0, width: 450, height: 800)
        editor.selectZoom(.fitPage)
        let initial = editor.zoom
        XCTAssertLessThan(initial, 0.5)
        XCTAssertLessThanOrEqual((editor.canvas.pageSettings.width + 48) * initial, editor.scrollView.contentView.frame.width + 0.1)
        XCTAssertLessThanOrEqual((editor.canvas.pageSettings.height + 48) * initial, editor.scrollView.contentView.frame.height + 0.1)
        editor.scrollView.setFrameSize(NSSize(width: 900, height: 800)); editor.viewportChanged()
        XCTAssertGreaterThan(editor.zoom, initial)
        XCTAssertEqual(editor.zoomMode, .fitPage)
        editor.zoom = 1.25
        editor.scrollView.setFrameSize(NSSize(width: 500, height: 400)); editor.viewportChanged()
        XCTAssertEqual(editor.zoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(document.model.sections[0].page.width, 1008)
    }
    func testFitWidthRespondsToGeometryAndPinchBecomesFixedZoom() {
        let document = ScribeFileDocument()
        let owned = PaginatedEditor(document: document)
        owned.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 700)
        owned.selectZoom(.fitWidth)
        let before = owned.zoom
        owned.setPageSettings(PageSettings(paper: .legal, landscape: true))
        XCTAssertLessThan(owned.zoom, before)
        owned.scrollView.magnification = 1.1
        NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: owned.scrollView)
        XCTAssertEqual(owned.zoomMode, .factor(1.1))
    }
}
#endif
