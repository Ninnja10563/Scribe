#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class PageLayoutTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testCustomGeometryNativeDialogUndoAndPDFMediaBox() throws {
        let document = ScribeFileDocument()
        var page = PageSettings(); page.width = 450.5; page.height = 600.25; page.top = 60.125
        document.model.sections[0].page = page
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            guard let content = NSApp.modalWindow?.contentView else { XCTFail("Missing layout dialog"); NSApp.abortModal(); return }
            let views = descendants(content)
            XCTAssertEqual(views.compactMap { $0 as? NSPopUpButton }.first?.titleOfSelectedItem, "Custom")
            guard let field = views.compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable && $0.stringValue == "450.5" }),
                  let button = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Apply" }) else { XCTFail("Missing page controls"); NSApp.abortModal(); return }
            field.stringValue = "480.75"
            NativeDialogCapture.save(content, name: "PageLayoutDialog")
            button.performClick(nil)
        }
        controller.pageSettings()
        XCTAssertEqual(document.model.sections[0].page.width, 480.75)
        XCTAssertEqual(document.model.sections[0].page.top, 60.125)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try PrintRenderer(editor: controller.editor).exportPDF(to: url, title: "Custom", author: "")
        let bounds = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0)?.bounds(for: .mediaBox))
        XCTAssertEqual(bounds.width, 480.75, accuracy: 0.01); XCTAssertEqual(bounds.height, 600.25, accuracy: 0.01)
        document.undoManager?.undo()
        XCTAssertEqual(document.model.sections[0].page, page)
    }
    func testPresetRotationAndCustomDimensionsStayConsistent() throws {
        let options = PageLayoutOptions(settings: PageSettings())
        options.paper.selectItem(at: 1); options.selectPaper()
        XCTAssertEqual(try options.settings().width, 612)
        options.landscape.state = .on; options.rotate()
        XCTAssertEqual(try options.settings().width, 792)
        XCTAssertEqual(try options.settings().height, 612)
        options.width.stringValue = "800.25"; options.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        XCTAssertEqual(options.paper.titleOfSelectedItem, "Custom")
        XCTAssertEqual(try options.settings().width, 800.25)
    }
}
#endif
