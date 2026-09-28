import XCTest
import DocumentCore
@testable import ImportExport

final class CommentInterchangeTests: XCTestCase {
    func testCommentPartsAndOverlappingRangesRoundTrip() throws {
        var document = ScribeDocument()
        var first = Paragraph("First 👩🏽‍💻 paragraph")
        first.runs[0].format.bold = true
        document.sections[0].paragraphs = [first, Paragraph("Second paragraph")]
        let index = DocumentTextIndex(paragraphs: document.paragraphs)
        document.comments = [
            Comment(anchor: .init(paragraphID: first.id, offset: 0, length: 5), text: "Review & <check>\nSecond line", author: "Alex & Sam"),
            Comment(anchor: index.anchor(for: NSRange(location: 6, length: index.length - 6))!, text: "Across paragraphs", author: "Editor")
        ]
        var detached = Comment(anchor: .init(paragraphID: UUID(), offset: 0, length: 0), text: "Retain detached review", author: "Alex")
        detached.isDetached = true; document.comments.append(detached)
        let exported = try DOCX.encode(document), files = try ZipArchive.decode(exported)
        XCTAssertNotNil(files["word/comments.xml"])
        let xml = String(decoding: files["word/document.xml"]!, as: UTF8.self)
        XCTAssertTrue(xml.contains("commentRangeStart")); XCTAssertTrue(xml.contains("commentRangeEnd")); XCTAssertTrue(xml.contains("commentReference"))
        XCTAssertTrue(String(decoding: files["word/_rels/document.xml.rels"]!, as: UTF8.self).contains("/comments"))
        let result = try DOCX.decode(exported)
        XCTAssertTrue(result.warnings.isEmpty, result.warnings.joined())
        XCTAssertEqual(result.document.plainText, document.plainText)
        XCTAssertEqual(result.document.comments.map(\.text), document.comments.map(\.text))
        XCTAssertEqual(result.document.comments.map(\.author), document.comments.map(\.author))
        XCTAssertEqual(result.document.comments.last?.isDetached, true)
        let loadedIndex = DocumentTextIndex(paragraphs: result.document.paragraphs)
        XCTAssertEqual(loadedIndex.range(for: result.document.comments[0].anchor), NSRange(location: 0, length: 5))
        XCTAssertEqual(loadedIndex.range(for: result.document.comments[1].anchor), NSRange(location: 6, length: index.length - 6))
        XCTAssertTrue(result.document.paragraphs[0].runs.allSatisfy { $0.format.bold == true })
    }
    func testCommentAnchorCannotSplitSurrogatePairs() {
        var document = ScribeDocument(); document.sections[0].paragraphs[0] = Paragraph("👩🏽‍💻")
        document.comments = [Comment(anchor: .init(paragraphID: document.paragraphs[0].id, offset: 1, length: 1), text: "Invalid", author: "Editor")]
        XCTAssertThrowsError(try DOCX.encode(document))
    }
    func testIndependentCommentFixture() throws {
        let url = Bundle.module.url(forResource: "Comments", withExtension: "docx", subdirectory: "Fixtures")!
        let result = try DOCX.decode(Data(contentsOf: url))
        XCTAssertEqual(result.document.comments.count, 2)
        XCTAssertEqual(result.document.comments[0].author, "Independent editor")
        XCTAssertEqual(result.document.comments[0].text, "Across both paragraphs\nKeep Unicode: café 東京")
        let index = DocumentTextIndex(paragraphs: result.document.paragraphs)
        XCTAssertEqual(index.range(for: result.document.comments[0].anchor), NSRange(location: 0, length: index.length))
        XCTAssertEqual(result.document.comments[1].text, "Overlapping first paragraph")
    }
}
