import XCTest
@testable import DocumentCore

final class BookmarkTests: XCTestCase {
    func testNamesStableLinksDeletionRestorationAndNativeRoundTrip() throws {
        var document = ScribeDocument()
        let paragraph = Paragraph("Research notes")
        document.sections[0].paragraphs.append(paragraph)
        let id = try XCTUnwrap(document.addParagraphBookmark(name: "Research", paragraphID: paragraph.id))
        let link = DocumentLink.bookmark(id)
        XCTAssertEqual(document.destinationParagraphID(for: link), paragraph.id)
        XCTAssertFalse(document.canNameBookmark("research"))
        XCTAssertFalse(document.canNameBookmark("Invalid name"))
        XCTAssertFalse(document.canNameBookmark("Scribe_reserved"))
        XCTAssertNil(DocumentLink.bookmarkID(link + "?query=1"))
        XCTAssertTrue(document.renameBookmark(id: id, name: "Sources"))
        XCTAssertEqual(document.destinationParagraphID(for: link), paragraph.id)
        document.sections[0].paragraphs.removeLast()
        XCTAssertNil(document.destinationParagraphID(for: link))
        XCTAssertEqual(document.bookmarks.count, 1)
        document = try NativeFormat.decode(NativeFormat.encode(document))
        document.sections[0].paragraphs.append(paragraph)
        XCTAssertEqual(document.destinationParagraphID(for: link), paragraph.id)
        document.bookmarks.append(document.bookmarks[0])
        XCTAssertThrowsError(try NativeFormat.validate(document))
    }
}
