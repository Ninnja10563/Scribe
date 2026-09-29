#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class RecoveryTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testShortRecoveredDocumentKeepsAllContentAndReviewData() throws {
        var model = ScribeDocument(); model.title = "Research"
        model.sections[0].paragraphs = [Paragraph("Only one paragraph, café 東京")]
        let id = model.paragraphs[0].id
        model.comments = [Comment(anchor: TextAnchor(paragraphID: id, offset: 0, length: 4), text: "Keep this review", author: "Writer")]
        _ = model.addParagraphBookmark(name: "Opening", paragraphID: id)
        let originalURL = URL(fileURLWithPath: "/tmp/original-must-not-be-overwritten.scribe")
        let document = try ScribeFileDocument.recovering(RecoverySnapshot(document: model, originalURL: originalURL))
        defer { document.close() }
        XCTAssertNil(document.fileURL); XCTAssertTrue(document.isDocumentEdited)
        XCTAssertNotEqual(document.model.id, model.id)
        XCTAssertEqual(document.model.title, "Research — Recovered")
        XCTAssertEqual(document.model.sections, model.sections)
        XCTAssertEqual(document.model.comments, model.comments)
        XCTAssertEqual(document.model.bookmarks, model.bookmarks)
        document.makeWindowControllers()
        let saved = try NativeFormat.decode(document.data(ofType: ScribeFileDocument.typeName))
        XCTAssertEqual(saved.plainText, model.plainText)
        XCTAssertEqual(saved.comments, model.comments)
        XCTAssertEqual(saved.bookmarks, model.bookmarks)
    }
    func testEmptyAndUnsupportedSectionRecoveryAreNonDestructive() throws {
        let model = ScribeDocument()
        let empty = try ScribeFileDocument.recovering(RecoverySnapshot(document: model, originalURL: nil))
        XCTAssertEqual(empty.model.paragraphs.count, 1); XCTAssertEqual(empty.model.plainText, "")
        empty.close()
        var multiple = model; multiple.sections.append(Section())
        XCTAssertThrowsError(try ScribeFileDocument.recovering(RecoverySnapshot(document: multiple, originalURL: nil)))
        XCTAssertEqual(multiple.sections.count, 2)
    }
}
#endif
