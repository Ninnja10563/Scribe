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
        document.comments[0].resolved = true
        var detached = Comment(anchor: .init(paragraphID: UUID(), offset: 0, length: 0), text: "Retain detached review", author: "Alex")
        detached.isDetached = true; document.comments.append(detached)
        let exported = try DOCX.encode(document), files = try ZipArchive.decode(exported)
        XCTAssertNotNil(files["word/comments.xml"]); XCTAssertNotNil(files["word/commentsExtended.xml"])
        let xml = String(decoding: files["word/document.xml"]!, as: UTF8.self)
        XCTAssertTrue(xml.contains("commentRangeStart")); XCTAssertTrue(xml.contains("commentRangeEnd")); XCTAssertTrue(xml.contains("commentReference"))
        XCTAssertTrue(String(decoding: files["word/_rels/document.xml.rels"]!, as: UTF8.self).contains("/comments"))
        let result = try DOCX.decode(exported)
        XCTAssertTrue(result.warnings.isEmpty, result.warnings.joined())
        XCTAssertEqual(result.document.plainText, document.plainText)
        XCTAssertEqual(result.document.comments.map(\.text), document.comments.map(\.text))
        XCTAssertEqual(result.document.comments.map(\.author), document.comments.map(\.author))
        XCTAssertEqual(result.document.comments.last?.isDetached, true)
        XCTAssertEqual(result.document.comments.map(\.resolved), [true, false, false])
        let loadedIndex = DocumentTextIndex(paragraphs: result.document.paragraphs)
        XCTAssertEqual(loadedIndex.range(for: result.document.comments[0].anchor), NSRange(location: 0, length: 5))
        XCTAssertEqual(loadedIndex.range(for: result.document.comments[1].anchor), NSRange(location: 6, length: index.length - 6))
        XCTAssertTrue(result.document.paragraphs[0].runs.allSatisfy { $0.format.bold == true })
    }
    func testAlternateNamespacePrefixesAndCustomCommentPartNames() throws {
        var document = ScribeDocument(); let p = Paragraph("A reviewed heading", style: "heading1")
        document.sections[0].paragraphs = [p]
        var comment = Comment(anchor: .init(paragraphID: p.id, offset: 2, length: 8), text: "Resolved comment", author: "Alex")
        comment.resolved = true; document.comments = [comment]
        var files = try ZipArchive.decode(DOCX.encode(document))
        files["word/review.xml"] = files.removeValue(forKey: "word/comments.xml")
        files["word/reviewState.xml"] = files.removeValue(forKey: "word/commentsExtended.xml")
        for path in Array(files.keys) where path.hasSuffix("xml") || path.hasSuffix("rels") {
            var xml = String(decoding: files[path]!, as: UTF8.self)
            xml = xml.replacingOccurrences(of: "commentsExtended.xml", with: "reviewState.xml").replacingOccurrences(of: "comments.xml", with: "review.xml")
            xml = xml.replacingOccurrences(of: "xmlns:w=", with: "xmlns:body=").replacingOccurrences(of: "w:", with: "body:")
            xml = xml.replacingOccurrences(of: "xmlns:w14=", with: "xmlns:ids=").replacingOccurrences(of: "w14:", with: "ids:").replacingOccurrences(of: "Ignorable=\"w14\"", with: "Ignorable=\"ids\"")
            xml = xml.replacingOccurrences(of: "xmlns:w15=", with: "xmlns:review=").replacingOccurrences(of: "w15:", with: "review:")
            files[path] = Data(xml.utf8)
        }
        let result = try DOCX.decode(ZipArchive.encode(files))
        XCTAssertEqual(result.document.paragraphs[0].styleID, "heading1")
        XCTAssertEqual(result.document.comments[0].resolved, true)
        XCTAssertEqual(result.document.comments[0].anchor.offset, 2)
        XCTAssertEqual(result.document.comments[0].anchor.length, 8)
        XCTAssertEqual(result.document.comments[0].author, "Alex")
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
