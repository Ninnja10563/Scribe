import Foundation
import XCTest
import DocumentCore
@testable import ImportExport

final class LineHeightInterchangeTests: XCTestCase {
    func testExplicitLineHeightUsesOfficeUnitsAndRoundTrips() throws {
        for (rule, value, units, officeRule) in [(ParagraphLineHeight.Rule.multiple, 1.5, 360, "auto"), (.minimum, 24.0, 480, "atLeast"), (.exact, 24.0, 480, "exact")] {
            var document = ScribeDocument(), format = ParagraphFormatting()
            format.lineHeight = .init(rule: rule, value: value); format.lineSpacing = 0
            document.styles[0].paragraph = format
            document.sections[0].paragraphs[0] = Paragraph("First line\u{2028}Second line\u{2028}Third line")
            document.sections[0].paragraphs[0].formatting = format
            let bytes = try DOCX.encode(document), parts = try ZipArchive.decode(bytes)
            let xml = String(decoding: try XCTUnwrap(parts["word/document.xml"]), as: UTF8.self)
            XCTAssertTrue(xml.contains("w:line=\"\(units)\" w:lineRule=\"\(officeRule)\""))
            let imported = try DOCX.decode(bytes).document
            XCTAssertEqual(imported.paragraphs[0].formatting ?? imported.style(for: imported.paragraphs[0]).paragraph, format)
            if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let url = URL(fileURLWithPath: folder, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try bytes.write(to: url.appendingPathComponent("LineHeight-" + rule.rawValue + ".docx"), options: .atomic)
            }
        }
    }
    func testStyleDefaultsInheritanceAndPartialOverrides() throws {
        var parts = try ZipArchive.decode(DOCX.encode(ScribeDocument()))
        parts["word/styles.xml"] = Data("""
        <w:styles xmlns:w="\(DOCX.wordNS)"><w:docDefaults><w:pPrDefault><w:pPr><w:spacing w:line="360" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
        <w:style w:type="paragraph" w:styleId="base"><w:pPr><w:spacing w:line="480" w:lineRule="exact"/></w:pPr></w:style>
        <w:style w:type="paragraph" w:styleId="child"><w:basedOn w:val="base"/><w:pPr><w:spacing w:line="600"/></w:pPr></w:style>
        <w:style w:type="paragraph" w:styleId="defaultBased"/></w:styles>
        """.utf8)
        parts["word/document.xml"] = Data("""
        <w:document xmlns:w="\(DOCX.wordNS)"><w:body><w:p><w:pPr><w:pStyle w:val="child"/><w:spacing w:line="400"/></w:pPr><w:r><w:t>Text</w:t></w:r></w:p></w:body></w:document>
        """.utf8)
        let imported = try DOCX.decode(ZipArchive.encode(parts)).document
        XCTAssertEqual(imported.styles.first { $0.id == "child" }?.paragraph.lineHeight, .init(rule: .exact, value: 30))
        XCTAssertEqual(imported.styles.first { $0.id == "defaultBased" }?.paragraph.lineHeight, .init(rule: .multiple, value: 1.5))
        XCTAssertEqual(imported.paragraphs[0].formatting?.lineHeight, .init(rule: .exact, value: 20))
    }
}
