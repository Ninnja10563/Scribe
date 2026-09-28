import XCTest
@testable import DocumentCore

final class DocumentLinkTests: XCTestCase {
    func testInternalTargetsRequireStableParagraphIDs() {
        let id = UUID()
        XCTAssertEqual(DocumentLink.paragraphID(DocumentLink.paragraph(id)), id)
        for invalid in ["https://paragraph/\(id)", "scribe://paragraph/not-an-id", "scribe://paragraph/\(id)?other=1", "scribe://other/\(id)", "scribe://paragraph/\(id)/extra"] {
            XCTAssertNil(DocumentLink.paragraphID(invalid))
        }
        XCTAssertLessThanOrEqual(DocumentLink.officeBookmark(id).count, 40)
        XCTAssertFalse(DocumentLink.officeBookmark(id).contains("-"))
    }
}
