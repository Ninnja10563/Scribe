import XCTest
@testable import DocumentCore

final class AnchorTests: XCTestCase {
    func testMultiParagraphUTF16RangesRoundTrip() throws {
        let paragraphs = [Paragraph("First 👩🏽‍💻"), Paragraph(""), Paragraph("Last café")]
        let index = DocumentTextIndex(paragraphs: paragraphs)
        let range = NSRange(location: 6, length: index.length - 6)
        let anchor = try XCTUnwrap(index.anchor(for: range))
        XCTAssertEqual(anchor.paragraphID, paragraphs[0].id)
        XCTAssertEqual(anchor.endParagraphID, paragraphs[2].id)
        XCTAssertEqual(index.range(for: anchor), range)
        XCTAssertNil(index.anchor(for: NSRange(location: Int.max, length: 1)))
        XCTAssertNil(index.range(for: TextAnchor(paragraphID: paragraphs[0].id, offset: 0, length: Int.max)))
        var document = ScribeDocument(); document.sections[0].paragraphs = paragraphs
        document.comments = [Comment(anchor: anchor, text: "Review across paragraphs", author: "Alex")]
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
    }
    func testListSplitMovesAndExtendsCommentAnchors() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs[0] = Paragraph("First second")
        let id = document.paragraphs[0].id
        document.sections[0].paragraphs[0].list = .init(kind: .decimal)
        document.comments = [
            Comment(anchor: .init(paragraphID: id, offset: 6, length: 6), text: "Second", author: "Alex"),
            Comment(anchor: .init(paragraphID: id, offset: 0, length: 12), text: "Both", author: "Alex")
        ]
        let next = try XCTUnwrap(document.splitListItem(id: id, range: NSRange(location: 6, length: 0)))
        XCTAssertEqual(document.comments[0].anchor.paragraphID, next)
        XCTAssertEqual(document.comments[0].anchor.offset, 0)
        XCTAssertEqual(document.comments[1].anchor.endParagraphID, next)
        XCTAssertEqual(document.comments[1].anchor.length, 13)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
    }
    func testDeletedTextRetainsDetachedCommentAndMigrationRepairsLegacyAnchors() throws {
        var document = ScribeDocument(); let id = document.paragraphs[0].id
        document.comments = [Comment(anchor: .init(paragraphID: id, offset: 10, length: 2), text: "Keep the review", author: "Alex")]
        XCTAssertThrowsError(try NativeFormat.encode(document))
        // Earlier editor versions did not maintain the schema-only anchors as text changed.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
        json["formatVersion"] = 3
        let loaded = try NativeFormat.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(loaded.comments[0].text, "Keep the review")
        XCTAssertEqual(loaded.comments[0].isDetached, true)
        XCTAssertEqual(loaded.formatVersion, 4)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(loaded)), loaded)
    }
}
