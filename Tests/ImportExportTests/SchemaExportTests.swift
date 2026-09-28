import XCTest
import DocumentCore
@testable import ImportExport

final class SchemaExportTests: XCTestCase {
    func testCombinedFormattingExportsWithoutLoss() throws {
        var document = ScribeDocument()
        var format = TextFormatting()
        format.fontFamily = "Helvetica Neue"; format.fontSize = 15
        format.bold = true; format.italic = true; format.underline = true
        format.strikethrough = true; format.foreground = "#123456"
        format.highlight = "#FFEEDD"; format.baseline = 1
        document.styles[0].text = format
        var paragraph = Paragraph("Formatting schema regression\u{c}After the page break")
        paragraph.runs[0].format = format
        paragraph.formatting = ParagraphFormatting()
        paragraph.list = ListDescriptor(kind: .decimal)
        paragraph.pageBreakBefore = true
        document.sections[0].paragraphs = [paragraph]
        document.insertTable(rows: 2, columns: 2, after: paragraph.id)
        let bytes = try DOCX.encode(document)
        let loaded = try DOCX.decode(bytes).document
        XCTAssertEqual(loaded.paragraphs[0].runs[0].format, format)
        XCTAssertEqual(loaded.paragraphs[0].list?.kind, .decimal)
        XCTAssertTrue(loaded.paragraphs[0].pageBreakBefore)
        XCTAssertEqual(loaded.tables.count, 1)
        // CI feeds this real exporter output to the independent Open XML SDK.
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try bytes.write(to: url.appendingPathComponent("Formatting.docx"), options: .atomic)
        }
    }
}
