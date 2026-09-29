import XCTest
@testable import DocumentCore

final class ImageAdjustmentTests: XCTestCase {
    func testCropRotateAndResetKeepSourceBytesAndScale() throws {
        let source = InlineImage(data: Data([1, 2, 3]), fileExtension: "png", width: 200, height: 100, altText: "Source description")
        let adjusted = try source.adjusted(crop: ImageCrop(left: 0.25), rotation: 90, opacity: 0.5, sourceWidth: source.width, maximumWidth: 500, maximumHeight: 700)
        XCTAssertEqual(adjusted.width, 100, accuracy: 0.000001)
        XCTAssertEqual(adjusted.height, 150, accuracy: 0.000001)
        XCTAssertEqual(adjusted.sourceDisplayWidth, 200, accuracy: 0.000001)
        XCTAssertEqual(adjusted.data, source.data); XCTAssertEqual(adjusted.id, source.id); XCTAssertEqual(adjusted.altText, source.altText)
        let reset = try adjusted.adjusted(crop: ImageCrop(), rotation: 0, opacity: 1, sourceWidth: adjusted.sourceDisplayWidth, maximumWidth: 500, maximumHeight: 700)
        XCTAssertNil(reset.adjustments)
        XCTAssertEqual(reset.width, source.width, accuracy: 0.000001); XCTAssertEqual(reset.height, source.height, accuracy: 0.000001)
        XCTAssertEqual(reset.data, source.data)
    }
    func testArbitraryRotationFitsPageAndInvalidCropIsRejected() throws {
        let source = InlineImage(data: Data([1]), fileExtension: "png", width: 300, height: 100)
        let adjusted = try source.adjusted(crop: ImageCrop(), rotation: -45, opacity: 1, sourceWidth: 300, maximumWidth: 150, maximumHeight: 180)
        XCTAssertEqual(adjusted.width, 150, accuracy: 0.000001)
        XCTAssertEqual(adjusted.height, 150, accuracy: 0.000001)
        XCTAssertEqual(adjusted.adjustments?.rotation, 315)
        XCTAssertThrowsError(try source.adjusted(crop: ImageCrop(left: 0.8, right: 0.3), rotation: 0, opacity: 1, sourceWidth: 300, maximumWidth: 500, maximumHeight: 700))
        XCTAssertThrowsError(try source.adjusted(crop: ImageCrop(), rotation: .infinity, opacity: 1, sourceWidth: 300, maximumWidth: 500, maximumHeight: 700))
    }
    func testNativeRoundTripAndV8Migration() throws {
        var document = ScribeDocument()
        var run = TextRun("\u{FFFC}")
        let image = InlineImage(data: Data([1]), fileExtension: "png", width: 200, height: 100)
        run.image = try image.adjusted(crop: ImageCrop(top: 0.1), rotation: 30, opacity: 0.7, sourceWidth: 200, maximumWidth: 500, maximumHeight: 700)
        document.sections[0].paragraphs[0].runs = [run]
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        document.sections[0].paragraphs[0].runs[0].image = image
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: NativeFormat.encode(document)) as? [String: Any]); json["formatVersion"] = 8
        let migrated = try NativeFormat.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.formatVersion, ScribeDocument.currentVersion)
        XCTAssertNil(migrated.paragraphs[0].runs[0].image?.adjustments)
        document.sections[0].paragraphs[0].runs[0].image?.adjustments = ImageAdjustments(rotation: 90, sourceAspectRatio: 2)
        XCTAssertThrowsError(try NativeFormat.validate(document), "Frame proportions must agree with adjustments")
    }
}
