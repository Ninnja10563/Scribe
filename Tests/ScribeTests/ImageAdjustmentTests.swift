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
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        editor.activeTextView.setSelectedRange(NSRange(location: location, length: 1))
        let types = editor.activeTextView.writablePasteboardTypes
        XCTAssertTrue(types.contains(.rtfd), "Native Copy must advertise rich text with image attachments")
        XCTAssertTrue(editor.activeTextView.writeSelection(to: pasteboard, types: types))
        let richData = try XCTUnwrap(pasteboard.data(forType: .rtfd))
        let rich = try NSAttributedString(data: richData, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        let copied = try XCTUnwrap(rich.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        let copiedData = try XCTUnwrap(copied.fileWrapper?.regularFileContents)
        XCTAssertNotEqual(copiedData, data, "External copy must contain the rendered crop, not the uncropped source")
        let copiedBitmap = try XCTUnwrap(NSBitmapImageRep(data: copiedData))
        XCTAssertEqual(copiedBitmap.pixelsWide, 200); XCTAssertEqual(copiedBitmap.pixelsHigh, 300)
        let color = try XCTUnwrap(copiedBitmap.colorAt(x: 50, y: 50)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.blueComponent, 0.9); XCTAssertLessThan(color.redComponent, 0.1)
        XCTAssertEqual(color.alphaComponent, 0.5, accuracy: 0.05)
        let pasted = AttributedDocument.capture(rich, preserving: ScribeDocument())
        let pastedImage = try XCTUnwrap(pasted.paragraphs.flatMap(\.runs).compactMap(\.image).first)
        XCTAssertEqual(pastedImage.width, changed.width, accuracy: 0.1)
        XCTAssertEqual(pastedImage.height, changed.height, accuracy: 0.1)
        XCTAssertNil(pastedImage.adjustments, "External RTFD images are already flattened")
        XCTAssertEqual(try current().data, data, "Copy must not alter native source bytes")
        editor.paginate(); XCTAssertNil(editor.layoutWarning)
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ImageAdjustments.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Adjusted image", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 1); XCTAssertTrue(pdf.string?.contains("After adjusted image.") == true)
        let rotated = try source.adjusted(crop: ImageCrop(left: 0.25), rotation: 30, opacity: 0.5, sourceWidth: 200, maximumWidth: 500, maximumHeight: 700)
        try controller.applyImageProperties(rotated, at: location)
        editor.paginate(); XCTAssertNil(editor.layoutWarning)
        try PrintRenderer(editor: editor).exportPDF(to: directory.appendingPathComponent("ImageRotation.pdf"), title: "Adjusted image", author: "")
    }
}
#endif
