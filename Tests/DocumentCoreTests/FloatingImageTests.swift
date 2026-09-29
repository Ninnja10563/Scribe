import Foundation
import XCTest
@testable import DocumentCore

final class FloatingImageTests: XCTestCase {
    private func document() -> ScribeDocument {
        var document = ScribeDocument(), run = TextRun("\u{fffc}")
        run.image = InlineImage(data: Data([1, 2, 3]), fileExtension: "png", width: 100, height: 80, altText: "Original image")
        document.sections[0].paragraphs[0].runs = [run]
        return document
    }
    func testVersion15ImagesRemainInlineWithoutMutatingTheSourceBytes() throws {
        let original = document()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: NativeFormat.encode(original)) as? [String: Any])
        json["formatVersion"] = 15
        let bytes = try JSONSerialization.data(withJSONObject: json), savedBytes = bytes
        let migrated = try NativeFormat.decode(bytes)
        XCTAssertEqual(migrated.formatVersion, ScribeDocument.currentVersion)
        XCTAssertNil(migrated.paragraphs[0].runs[0].image?.placement)
        XCTAssertEqual(migrated.paragraphs[0].runs[0].image, original.paragraphs[0].runs[0].image)
        XCTAssertEqual(bytes, savedBytes)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["formatVersion"] as? Int, 15)
    }
    func testPlacementRoundTripsWithoutChangingOriginalAsset() throws {
        for wrapping in FloatingImagePlacement.Wrapping.allCases {
            var value = document()
            let original = value.paragraphs[0].runs[0].image
            let placement = FloatingImagePlacement(x: 120.25, y: 44.5, wrapping: wrapping, textDistance: 12, zOrder: 2)
            value.sections[0].paragraphs[0].runs[0].image?.placement = placement
            let decoded = try NativeFormat.decode(NativeFormat.encode(value))
            XCTAssertTrue(decoded.hasFloatingImages)
            XCTAssertEqual(decoded.paragraphs[0].runs[0].image?.placement, placement)
            XCTAssertEqual(decoded.paragraphs[0].runs[0].image?.data, original?.data)
            XCTAssertEqual(decoded.paragraphs[0].runs[0].image?.altText, original?.altText)
        }
    }
    func testInvalidGeometryAndDuplicateAnchorsAreRejected() throws {
        for position in [FloatingImagePlacement(x: -.infinity, y: 0), .init(x: -1, y: 0), .init(x: 0, y: 4001), .init(x: 0, y: 0, textDistance: .nan), .init(x: 0, y: 0, zOrder: -1)] {
            var value = document(); value.sections[0].paragraphs[0].runs[0].image?.placement = position
            XCTAssertThrowsError(try NativeFormat.encode(value))
        }
        var value = document(); value.sections[0].paragraphs[0].runs[0].image?.placement = .init(x: 0, y: 0)
        value.sections[0].paragraphs[0].runs.append(value.paragraphs[0].runs[0])
        XCTAssertThrowsError(try NativeFormat.encode(value))
    }
}
