#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class FloatingImageNativeTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func source(_ mode: FloatingImagePlacement.Wrapping) -> ScribeDocument {
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAKElEQVR4nGP4z8BAEiJNNRlo1IJRCwbAAlJ1/P/PQBIatWDUgiFgAQAk0H2fCntH2wAAAABJRU5ErkJggg==")!
        var source = ScribeDocument(), image = InlineImage(data: bytes, fileExtension: "png", width: 120, height: 60, altText: "Floating test image")
        image.placement = .init(x: 20, y: 80, wrapping: mode)
        var run = TextRun("\u{fffc}"); run.image = image
        source.sections[0].paragraphs[0].runs = [TextRun("Before "), run, TextRun(" after anchor.")]
        source.sections[0].paragraphs.append(Paragraph(String(repeating: "Text continues through the page. ", count: 80)))
        return source
    }
    func testAnchorDoesNotReserveTheInlineImageBoxAndCapturesItsSource() throws {
        let source = source(.inFrontOfText), rendered = AttributedDocument.render(source)
        let attachment = try XCTUnwrap(rendered.attribute(.attachment, at: 7, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(attachment.attachmentCell?.cellSize(), .zero)
        XCTAssertEqual(AttributedDocument.capture(rendered, preserving: source).paragraphs, source.paragraphs)
    }
    func testPageAndPDFUseTheFloatingFrame() throws {
        for mode in [FloatingImagePlacement.Wrapping.behindText, .inFrontOfText] {
            let source = source(mode), document = ScribeFileDocument(); document.model = source
            let editor = PaginatedEditor(document: document); defer { editor.prepareForClose() }
            XCTAssertNil(editor.layoutWarning)
            let entry = try XCTUnwrap(editor.floatingImages.entries.first)
            XCTAssertEqual(entry.frame, NSRect(x: 20, y: 80, width: 120, height: 60))
            XCTAssertEqual(entry.page, 0)
            XCTAssertEqual(entry.range, NSRange(location: 7, length: 1))
            if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try PrintRenderer(editor: editor).exportPDF(to: folder.appendingPathComponent("FloatingImage-" + mode.rawValue + ".pdf"), title: mode.rawValue, author: "Scribe")
            }
            XCTAssertEqual(document.snapshot().paragraphs, source.paragraphs)
        }
    }
    func testSquareWrappingBlocksOutputUntilItsLayoutIsImplemented() throws {
        let document = ScribeFileDocument(); document.model = source(.square)
        let editor = PaginatedEditor(document: document); defer { editor.prepareForClose() }
        XCTAssertTrue(editor.layoutWarning?.contains("Square") == true)
    }
    func testClipboardKeepsPlacementAndExternalCopyContainsAVisibleImage() throws {
        let source = source(.inFrontOfText), rendered = AttributedDocument.render(source)
        let selected = rendered.attributedSubstring(from: NSRange(location: 7, length: 1))
        let payload = try InlineObjectClipboard.encode(selected)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 4)
        let external = try ExternalImageProjection.render(selected)
        let attachment = try XCTUnwrap(external.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(attachment.attachmentCell?.cellSize(), NSSize(width: 120, height: 60))
        let restored = try InlineObjectClipboard.restore(payload, in: external)
        let captured = AttributedDocument.capture(restored, preserving: ScribeDocument())
        XCTAssertEqual(captured.paragraphs[0].runs[0].image, source.paragraphs[0].runs[1].image)
    }
}
#endif
