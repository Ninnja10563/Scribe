#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ReviewProjectionTests: XCTestCase {
    func testProjectionPreservesRevisionMetadataAndFormattingHistory() throws {
        _ = NSApplication.shared
        let author = RevisionAuthor(name: "Reviewer")
        var text = RevisionText(runs: [TextRun("Original")])
        try text.replace(NSRange(location: 0, length: 8), with: [TextRun("Replacement")], insertion: .init(author: author), deletion: .init(author: author))
        try text.format(NSRange(location: 8, length: 11), identity: .init(author: author)) { var value = $0; value.bold = true; return value }
        var model = ScribeDocument(); model.sections[0].paragraphs[0].runs = text.runs
        let projected = AttributedDocument.render(model)
        let captured = AttributedDocument.capture(projected, preserving: model)
        try NativeFormat.validate(captured)
        XCTAssertEqual(captured.paragraphs[0].runs, model.paragraphs[0].runs)
        XCTAssertTrue(captured.hasPendingRevisions)
        let document = ScribeFileDocument()
        XCTAssertThrowsError(try document.read(from: NativeFormat.encode(model), ofType: ScribeFileDocument.typeName), "Until native review actions are integrated, opening must not silently flatten pending changes")
    }
}
#endif
