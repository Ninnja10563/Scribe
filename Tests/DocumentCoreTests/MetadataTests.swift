import XCTest
@testable import DocumentCore

final class MetadataTests: XCTestCase {
    func testMetadataIsTransactionalAndPreservesUnicode() throws {
        var document = ScribeDocument()
        try document.setMetadata(title: "Résumé 東京 & research", author: "Zoë", language: "zh_hant_tw")
        XCTAssertEqual(document.language, "zh-Hant-TW")
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        let before = document
        XCTAssertThrowsError(try document.setMetadata(title: "Changed", author: "Other", language: "en--AU"))
        XCTAssertEqual(document, before)
        XCTAssertThrowsError(try document.setMetadata(title: "Invalid\u{0}", author: "", language: "fr"))
        XCTAssertEqual(document, before)
        try document.setMetadata(title: before.title, author: before.author, language: "und")
        XCTAssertEqual(document.language, "und")
    }
}
