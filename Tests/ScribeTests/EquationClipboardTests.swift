#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class EquationClipboardTests: XCTestCase {
    func testNativeCopyPasteRetainsEditableEquationAndExternalCopyHasImage() throws {
        _ = NSApplication.shared
        let source = ScribeFileDocument(); source.makeWindowControllers(); defer { source.close() }
        let equation = try Equation(source: #"\frac{\alpha+1}{\sqrt{x}}"#)
        try source.editorController!.applyEquation(equation, replacing: NSRange(location: 0, length: 0), action: "Insert Equation")
        source.editorController!.editor.select(NSRange(location: 0, length: 1))
        let board = NSPasteboard.general; board.clearContents()
        source.editorController!.editor.activeTextView.copy(nil)
        XCTAssertEqual(board.string(forType: .string), "[Equation: \(equation.source)]")
        let privateData = try XCTUnwrap(board.data(forType: InlineObjectClipboard.type))
        let rtfd = try XCTUnwrap(board.data(forType: .rtfd))
        let external = try NSAttributedString(data: rtfd, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        let attachment = try XCTUnwrap(external.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertTrue(attachment.fileWrapper?.preferredFilename?.hasSuffix(".png") == true)
        XCTAssertNotNil(NSImage(data: try XCTUnwrap(attachment.fileWrapper?.regularFileContents)))
        let restored = try InlineObjectClipboard.restore(privateData, in: external)
        XCTAssertEqual(AttributedDocument.capture(restored, preserving: ScribeDocument()).paragraphs[0].runs[0].equation, equation)
        let destination = ScribeFileDocument(); destination.makeWindowControllers(); defer { destination.close() }
        destination.editorController!.editor.activeTextView.paste(nil)
        XCTAssertEqual(destination.snapshot().paragraphs[0].runs[0].equation, equation)
        try NativeFormat.validate(destination.snapshot())
        destination.undoManager?.undo(); XCTAssertTrue(destination.snapshot().paragraphs[0].runs.compactMap(\.equation).isEmpty)
        destination.undoManager?.redo(); XCTAssertEqual(destination.snapshot().paragraphs[0].runs[0].equation, equation)
        let plain = try ExternalTextProjection.render(source.editorController!.editor.storage, includeImages: false)
        XCTAssertEqual(plain.string, "[Equation: \(equation.source)]")
        XCTAssertNil(plain.attribute(.attachment, at: 0, effectiveRange: nil))
    }
    func testClipboardRejectsMismatchedOrInvalidObjectLocationsAndPreservesAdjacentCopies() throws {
        _ = NSApplication.shared
        var model = ScribeDocument(); var run = TextRun("\u{FFFC}"); run.equation = try Equation(source: "x^2")
        model.sections[0].paragraphs[0].runs = [run]
        let projection = AttributedDocument.render(model)
        let bytes = try InlineObjectClipboard.encode(projection)
        XCTAssertThrowsError(try InlineObjectClipboard.restore(bytes, in: NSAttributedString(string: "different")))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var objects = try XCTUnwrap(json["objects"] as? [[String: Any]])
        objects[0]["location"] = -1; json["objects"] = objects
        XCTAssertThrowsError(try InlineObjectClipboard.restore(JSONSerialization.data(withJSONObject: json), in: projection))
        let adjacent = NSMutableAttributedString(attributedString: projection); adjacent.append(projection)
        let captured = AttributedDocument.capture(adjacent, preserving: model)
        XCTAssertEqual(captured.paragraphs[0].runs.compactMap(\.equation).count, 2)
        try NativeFormat.validate(captured)
    }
}
#endif
