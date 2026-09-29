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
    func testSquareWrappingUsesRealLineFragmentsAndCanBeUndone() throws {
        let document = ScribeFileDocument(); document.model = source(.square)
        document.makeWindowControllers(); defer { document.close() }
        let editor = try XCTUnwrap(document.editorController?.editor)
        document.undoManager?.removeAllActions()
        let original = document.snapshot()
        XCTAssertNil(editor.layoutWarning)
        XCTAssertGreaterThan(editor.lastFloatingLayoutPasses, 0)
        XCTAssertLessThanOrEqual(editor.lastFloatingLayoutPasses, 12)
        func verifyExclusion() throws {
            let entry = try XCTUnwrap(editor.floatingImages.entries.first)
            let container = editor.layout.textContainers[entry.page]
            let expected = entry.frame.insetBy(dx: -8, dy: -8)
            XCTAssertEqual(container.exclusionPaths.map(\.bounds), [expected])
            let glyphs = editor.layout.glyphRange(for: container)
            editor.layout.enumerateLineFragments(forGlyphRange: glyphs) { _, used, current, _, _ in
                if current === container { XCTAssertFalse(used.intersects(expected.insetBy(dx: 0.25, dy: 0.25)), "Text intersects its image exclusion: \(used)") }
            }
        }
        try verifyExclusion()
        document.performEdit("Move Image") { $0.sections[0].paragraphs[0].runs[1].image?.placement?.x = 260 }
        XCTAssertNil(editor.layoutWarning); try verifyExclusion()
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs, original.paragraphs)
        try verifyExclusion()
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try PrintRenderer(editor: editor).exportPDF(to: folder.appendingPathComponent("FloatingImage-square.pdf"), title: "Square wrapping", author: "Scribe")
            NativeDialogCapture.save(editor.canvas, name: "FloatingImageSquareCanvas")
        }
        document.performEdit("Make Image Inline") { $0.sections[0].paragraphs[0].runs[1].image?.placement = nil }
        XCTAssertNil(editor.layoutWarning)
        XCTAssertTrue(editor.floatingImages.entries.isEmpty)
        XCTAssertTrue(editor.layout.textContainers.allSatisfy { $0.exclusionPaths.isEmpty })
    }
    func testTypingBeforeAnchorMovesItToLaterPagesAndDeletionUndoRestoresIt() throws {
        let document = ScribeFileDocument(); document.model = source(.square)
        document.makeWindowControllers(); defer { document.close() }
        let editor = try XCTUnwrap(document.editorController?.editor)
        let original = document.snapshot()
        document.undoManager?.removeAllActions()
        editor.select(NSRange(location: 0, length: 0))
        editor.activeTextView.insertText(String(repeating: "Preceding material flows onto later pages. ", count: 250) + "\n", replacementRange: NSRange(location: 0, length: 0))
        editor.paginate()
        XCTAssertNil(editor.layoutWarning)
        let moved = try XCTUnwrap(editor.floatingImages.entries.first)
        XCTAssertGreaterThan(moved.page, 0)
        XCTAssertTrue(editor.layout.textContainers[0].exclusionPaths.isEmpty)
        XCTAssertEqual(editor.layout.textContainers[moved.page].exclusionPaths.count, 1)
        document.undoManager?.undo(); editor.paginate()
        XCTAssertNil(editor.layoutWarning)
        XCTAssertEqual(document.snapshot().paragraphs, original.paragraphs)
        XCTAssertEqual(editor.floatingImages.entries.first?.page, 0)
        document.undoManager?.removeAllActions()
        editor.select(NSRange(location: 7, length: 1))
        editor.activeTextView.insertText("", replacementRange: NSRange(location: 7, length: 1))
        editor.paginate()
        XCTAssertNil(editor.layoutWarning)
        XCTAssertTrue(editor.floatingImages.entries.isEmpty)
        XCTAssertTrue(editor.layout.textContainers.allSatisfy { $0.exclusionPaths.isEmpty })
        document.undoManager?.undo(); editor.paginate()
        XCTAssertNil(editor.layoutWarning)
        XCTAssertEqual(document.snapshot().paragraphs, original.paragraphs)
        XCTAssertEqual(editor.floatingImages.entries.count, 1)
    }
    func testOverflowBlocksPDFWithoutReplacingAnExistingFile() throws {
        let document = ScribeFileDocument(); document.model = source(.square)
        document.model.sections[0].paragraphs[0].runs[1].image?.placement?.x = 440
        let editor = PaginatedEditor(document: document); defer { editor.prepareForClose() }
        XCTAssertNotNil(editor.layoutWarning)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let sentinel = Data("Existing PDF must survive".utf8)
        try sentinel.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try PrintRenderer(editor: editor).exportPDF(to: url, title: "Overflow", author: "Scribe"))
        XCTAssertEqual(try Data(contentsOf: url), sentinel)
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
