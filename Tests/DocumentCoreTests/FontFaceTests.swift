import XCTest
@testable import DocumentCore

final class FontFaceTests: XCTestCase {
    func testV4MigrationRetainsFamilyAndDoesNotInventFace() throws {
        var document = ScribeDocument()
        document.sections[0].paragraphs[0].runs[0].format.fontFamily = "Helvetica Neue"
        var json = try JSONSerialization.jsonObject(with: NativeFormat.encode(document)) as! [String: Any]
        json["formatVersion"] = 4
        let original = try JSONSerialization.data(withJSONObject: json)
        let migrated = try NativeFormat.decode(original)
        XCTAssertEqual(migrated.formatVersion, 5)
        XCTAssertNil(migrated.paragraphs[0].runs[0].format.fontFace)
        XCTAssertEqual(migrated.paragraphs[0].runs[0].format.fontFamily, "Helvetica Neue")
        XCTAssertEqual((try JSONSerialization.jsonObject(with: original) as! [String: Any])["formatVersion"] as? Int, 4)
    }
    func testFontFaceRoundTripAndValidation() throws {
        var document = ScribeDocument()
        document.sections[0].paragraphs[0].runs[0].format.fontFace = "HelveticaNeue-Medium"
        document.styles[0].text.fontFace = "HelveticaNeue-Light"
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        for invalid in ["", "Bad\nFace", String(repeating: "a", count: 513)] {
            document.sections[0].paragraphs[0].runs[0].format.fontFace = invalid
            XCTAssertThrowsError(try NativeFormat.encode(document))
        }
    }
}
