import XCTest
import DocumentCore
@testable import ImportExport

final class StyleOverrideTests: XCTestCase {
    func testExplicitHighlightAndBaselineResetsSurviveNativeAndDOCX() throws {
        var document = ScribeDocument()
        document.title = "Style overrides"
        document.styles[0].text.highlight = "#FFFF00"
        document.styles[0].text.baseline = 1
        var plain = TextRun("NO HIGHLIGHT"); plain.format.clearHighlight = true; plain.format.baseline = 0
        var paragraph = Paragraph(); paragraph.runs = [plain]
        var direct = Paragraph("DIRECT"); direct.runs[0].format.highlight = "#FF0000"
        document.sections[0].paragraphs = [Paragraph("INHERITED"), paragraph, direct]
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        let bytes = try DOCX.encode(document)
        let parts = try ZipArchive.decode(bytes)
        let xml = String(decoding: parts["word/document.xml"]!, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:shd w:val=\"nil\" w:fill=\"auto\"/>"))
        XCTAssertTrue(xml.contains("<w:vertAlign w:val=\"baseline\"/>"))
        let imported = try DOCX.decode(bytes).document
        XCTAssertEqual(imported.paragraphs[1].runs[0].format.clearHighlight, true)
        XCTAssertEqual(imported.paragraphs[1].runs[0].format.baseline, 0)
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent("StyleOverrides.docx"))
        }
        document.sections[0].paragraphs[1].runs[0].format.highlight = "#FF0000"
        XCTAssertThrowsError(try NativeFormat.validate(document))
    }
    func testV9MigrationKeepsImplicitHighlightInheritance() throws {
        var document = ScribeDocument(); document.styles[0].text.highlight = "#FFFF00"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: NativeFormat.encode(document)) as? [String: Any]); json["formatVersion"] = 9
        let restored = try NativeFormat.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.formatVersion, ScribeDocument.currentVersion)
        XCTAssertNil(restored.paragraphs[0].runs[0].format.clearHighlight)
        XCTAssertEqual(restored.styles[0].text.highlight, "#FFFF00")
    }
}
