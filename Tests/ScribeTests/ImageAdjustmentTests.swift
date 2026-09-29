#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ImageAdjustmentTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testImagePropertiesUndoSourceRetentionAndRenderedPDF() throws {
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAKElEQVR4nGP4z8BAEiJNNRlo1IJRCwbAAlJ1/P/PQBIatWDUgiFgAQAk0H2fCntH2wAAAABJRU5ErkJggg==")!
        let source = InlineImage(data: data, fileExtension: "png", width: 200, height: 100, altText: "Four colored quadrants")
        let document = ScribeFileDocument()
        document.model.title = "Adjusted image"
        var run = TextRun("\u{FFFC}"); run.image = source
        var picture = Paragraph(); picture.runs = [run]
        document.model.sections[0].paragraphs = [Paragraph("Adjusted image"), picture, Paragraph("After adjusted image.")]
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        let location = (editor.storage.string as NSString).range(of: "\u{FFFC}").location
        editor.activeTextView.setSelectedRange(NSRange(location: location, length: 1))
        document.undoManager?.removeAllActions()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            guard let content = NSApp.modalWindow?.contentView else { XCTFail("Missing image dialog"); NSApp.abortModal(); return }
            let views = descendants(content)
            let values = ["Clockwise rotation (°)": "90", "Opacity (%)": "50", "Crop left (%)": "25"]
            for field in views.compactMap({ $0 as? NSTextField }) {
                if let id = field.identifier?.rawValue, let value = values[id] { field.stringValue = value }
            }
            NativeDialogCapture.save(content, name: "ImagePropertiesDialog")
            guard let button = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Apply" }) else { XCTFail("Missing Apply"); NSApp.abortModal(); return }
            button.performClick(nil)
        }
        controller.imageProperties()
        func current() throws -> InlineImage { try XCTUnwrap(document.snapshot().paragraphs.flatMap(\.runs).compactMap(\.image).first) }
        let changed = try current()
        XCTAssertEqual(changed.data, data); XCTAssertEqual(changed.width, 100, accuracy: 0.001); XCTAssertEqual(changed.height, 150, accuracy: 0.001)
        document.undoManager?.undo(); XCTAssertNil(try current().adjustments)
        document.undoManager?.redo(); XCTAssertEqual(try current(), changed)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document.snapshot())).paragraphs.flatMap(\.runs).compactMap(\.image).first, changed)
        editor.paginate(); XCTAssertNil(editor.layoutWarning)
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ImageAdjustments.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Adjusted image", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 1); XCTAssertTrue(pdf.string?.contains("After adjusted image.") == true)
    }
}
#endif
