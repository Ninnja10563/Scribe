import Foundation
import XCTest
import DocumentCore
@testable import ImportExport

final class FloatingImageInterchangeTests: XCTestCase {
    private func source(_ mode: FloatingImagePlacement.Wrapping) -> ScribeDocument {
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAKElEQVR4nGP4z8BAEiJNNRlo1IJRCwbAAlJ1/P/PQBIatWDUgiFgAQAk0H2fCntH2wAAAABJRU5ErkJggg==")!
        var document = ScribeDocument(), image = InlineImage(data: bytes, fileExtension: "png", width: 120, height: 60, altText: "Floating test image")
        image.placement = .init(x: 20, y: 80, wrapping: mode)
        var run = TextRun("\u{fffc}"); run.image = image
        document.sections[0].paragraphs[0].runs = [TextRun("Before "), run, TextRun(" after anchor.")]
        document.sections[0].paragraphs.append(Paragraph(String(repeating: "Text continues through the page. ", count: 80)))
        return document
    }
    func testAnchoredPackagesKeepOriginalAssetsAndPublicImportDisclosesFlattening() throws {
        for mode in FloatingImagePlacement.Wrapping.allCases {
            let document = source(mode)
            XCTAssertThrowsError(try DOCX.encode(document))
            let bytes = try DOCXWriter(document, allowsFloatingImages: true).encode()
            let parts = try ZipArchive.decode(bytes)
            let assets = parts.filter { $0.key.hasPrefix("word/media/") }
            XCTAssertEqual(assets.count, 1)
            XCTAssertEqual(assets.first?.value, document.paragraphs[0].runs[1].image?.data)
            let imported = try DOCX.decode(bytes)
            XCTAssertFalse(imported.document.hasFloatingImages)
            XCTAssertTrue(imported.warnings.contains("Floating images are imported inline with the text."))
            XCTAssertEqual(imported.document.paragraphs[0].runs.compactMap(\.image).first?.data, assets.first?.value)
            if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let url = URL(fileURLWithPath: folder, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try bytes.write(to: url.appendingPathComponent("FloatingImage-" + mode.rawValue + ".docx"), options: .atomic)
            }
        }
    }
    func testUnvalidatedRotationAndPageOverflowAreRefused() throws {
        var document = source(.square)
        document.sections[0].paragraphs[0].runs[1].image?.placement?.x = 440
        XCTAssertThrowsError(try DOCXWriter(document, allowsFloatingImages: true).encode())
        document = source(.square)
        let original = try XCTUnwrap(document.paragraphs[0].runs[1].image)
        var rotated = try original.adjusted(crop: ImageCrop(), rotation: 90, opacity: 1, sourceWidth: 120, maximumWidth: 450, maximumHeight: 600)
        rotated.placement = original.placement
        document.sections[0].paragraphs[0].runs[1].image = rotated
        XCTAssertThrowsError(try DOCXWriter(document, allowsFloatingImages: true).encode())
    }
}
