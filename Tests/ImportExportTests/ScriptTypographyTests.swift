import XCTest
import DocumentCore
@testable import ImportExport

final class ScriptTypographyTests: XCTestCase {
    func testScriptRunsKeepLogicalSizeInOfficeXML() throws {
        var document = ScribeDocument(); document.title = "Script typography"
        document.styles[0].text.fontSize = 20
        var up = TextRun("SUP"); up.format.baseline = 1
        var down = TextRun("SUB"); down.format.baseline = -1
        document.sections[0].paragraphs[0].runs = [TextRun("Base "), up, TextRun(" Base "), down, TextRun(" Base")]
        let data = try DOCX.encode(document)
        let restored = try DOCX.decode(data).document
        XCTAssertEqual(restored.paragraphs[0].runs.map(\.format.baseline), [nil, 1, nil, -1, nil])
        XCTAssertTrue(restored.paragraphs[0].runs.allSatisfy { $0.format.fontSize == nil })
        XCTAssertEqual(restored.style(for: restored.paragraphs[0]).text.fontSize, 20)
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent("ScriptTypography.docx"))
        }
    }
}
