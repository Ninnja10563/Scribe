import XCTest
import DocumentCore
@testable import ImportExport

final class ImageAdjustmentTests: XCTestCase {
    func testIndependentDrawingMLImageFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ImageAdjustments", withExtension: "docx", subdirectory: "Fixtures"))
        let imported = try DOCX.decode(Data(contentsOf: url))
        let image = try XCTUnwrap(imported.document.paragraphs.flatMap(\.runs).compactMap(\.image).first)
        XCTAssertEqual(image.adjustments?.crop.left, 0.25)
        XCTAssertEqual(image.adjustments?.rotation, 90)
        XCTAssertEqual(image.adjustments?.opacity, 0.5)
        XCTAssertEqual(image.width, 100, accuracy: 0.001)
        XCTAssertEqual(image.height, 150, accuracy: 0.001)
        XCTAssertEqual(image.sourceDisplayWidth, 200, accuracy: 0.001)
    }
    func testDrawingMLAdjustmentsPreserveSourceAndGeometry() throws {
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAKElEQVR4nGP4z8BAEiJNNRlo1IJRCwbAAlJ1/P/PQBIatWDUgiFgAQAk0H2fCntH2wAAAABJRU5ErkJggg==")!
        let source = InlineImage(data: data, fileExtension: "png", width: 200, height: 100, altText: "Four colored quadrants")
        let image = try source.adjusted(crop: ImageCrop(left: 0.25), rotation: 90, opacity: 0.5, sourceWidth: 200, maximumWidth: 500, maximumHeight: 700)
        var document = ScribeDocument()
        document.title = "Adjusted image"
        var run = TextRun("\u{FFFC}"); run.image = image
        var picture = Paragraph(); picture.runs = [run]
        document.sections[0].paragraphs = [Paragraph("Adjusted image"), picture, Paragraph("After adjusted image.")]
        let bytes = try DOCX.encode(document)
        let parts = try ZipArchive.decode(bytes)
        XCTAssertEqual(parts.filter { $0.key.hasPrefix("word/media/") }.values.first, data)
        let xml = String(decoding: parts["word/document.xml"]!, as: UTF8.self)
        XCTAssertTrue(xml.contains("rot=\"5400000\""))
        XCTAssertTrue(xml.contains("<a:srcRect l=\"25000\""))
        XCTAssertTrue(xml.contains("<a:alphaModFix amt=\"50000\"/>"))
        let imported = try DOCX.decode(bytes)
        let result = try XCTUnwrap(imported.document.paragraphs.flatMap(\.runs).compactMap(\.image).first)
        XCTAssertEqual(result.data, data)
        XCTAssertEqual(result.width, 100, accuracy: 0.001)
        XCTAssertEqual(result.height, 150, accuracy: 0.001)
        XCTAssertEqual(result.adjustments, image.adjustments)
        XCTAssertTrue(imported.warnings.isEmpty, imported.warnings.joined(separator: "\n"))
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent("ImageAdjustments.docx"))
        }
    }
    func testDuplicateImageIdentifiersDoNotOverwriteDistinctSourceData() throws {
        let first = InlineImage(data: Data([1, 2]), fileExtension: "png", width: 20, height: 10)
        var second = first; second.data = Data([3, 4])
        var a = TextRun("\u{FFFC}"); a.image = first
        var b = TextRun("\u{FFFC}"); b.image = second
        var document = ScribeDocument(); document.sections[0].paragraphs[0].runs = [a, b]
        let imported = try DOCX.decode(DOCX.encode(document))
        XCTAssertEqual(imported.document.paragraphs.flatMap(\.runs).compactMap(\.image).map(\.data), [first.data, second.data])
    }
}
