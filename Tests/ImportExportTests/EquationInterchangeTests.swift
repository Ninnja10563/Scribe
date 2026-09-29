import XCTest
import DocumentCore
@testable import ImportExport

final class EquationInterchangeTests: XCTestCase {
    func testIndependentEquationFixtureAndSafeTextExports() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "IndependentEquations", withExtension: "docx", subdirectory: "Fixtures"))
        let imported = try DOCX.decode(Data(contentsOf: url))
        XCTAssertTrue(imported.warnings.isEmpty)
        let equation = try XCTUnwrap(imported.document.paragraphs[0].runs.compactMap(\.equation).first)
        XCTAssertEqual(equation.expression, try MathParser.parse(#"\frac{12}{x_i^2}"#))
        XCTAssertTrue(imported.document.plainText.contains("remains editable."))
        XCTAssertTrue(TextFormats.exportMarkdown(imported.document).contains(equation.source))
        XCTAssertFalse(TextFormats.exportMarkdown(imported.document).contains("\u{FFFC}"))
    }
    func testActualOfficeMathObjectsRoundTripAndExportPackage() throws {
        let sources = [#"x^2+5x+6=0"#, #"x=\frac{-b+\sqrt{b^2-4ac}}{2a}"#, #"\sum_{i=1}^{n}i=\frac{n(n+1)}{2}"#, #"\int_0^1 x^2=\frac{1}{3}"#, #"\sqrt[3]{\frac{x+1}{y-2}}"#, #"\left(\frac{\alpha}{\beta}\right)^2"#, #"\text{Area}=\pi r^2"#, #"\sum_{i=1}^{n}"#, #"\int_0^1"#]
        var document = ScribeDocument()
        document.sections[0].paragraphs = try sources.map { source in
            var paragraph = Paragraph(); var run = TextRun("\u{FFFC}")
            run.equation = try Equation(source: source, pointSize: 24); paragraph.runs = [run]; return paragraph
        }
        let bytes = try DOCX.encode(document), parts = try ZipArchive.decode(bytes)
        let xml = try XCTUnwrap(String(data: parts["word/document.xml"]!, encoding: .utf8))
        for name in ["oMath", "f", "rad", "nary", "sSup", "d"] { XCTAssertTrue(xml.contains("<m:\(name)")) }
        XCTAssertFalse(xml.contains("<w:drawing"))
        XCTAssertFalse(xml.contains("<m:e/></m:nary>"), "Office Math operators must not export empty operands that render as placeholder boxes")
        let imported = try DOCX.decode(bytes)
        XCTAssertTrue(imported.warnings.isEmpty, imported.warnings.joined(separator: "; "))
        let equations = imported.document.paragraphs.flatMap(\.runs).compactMap(\.equation)
        XCTAssertEqual(equations.count, sources.count)
        for (original, reopened) in zip(document.paragraphs.flatMap(\.runs).compactMap(\.equation), equations) {
            XCTAssertEqual(original.expression, reopened.expression)
            XCTAssertEqual(reopened.pointSize, 24)
        }
        if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let directory = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bytes.write(to: directory.appendingPathComponent("Equations.docx"))
        }
    }
    func testEquationImportDisclosesUnsupportedStylingAndRejectsExcessiveNesting() throws {
        var parts = try ZipArchive.decode(DOCX.encode(ScribeDocument()))
        func package(_ math: String) throws -> Data {
            parts["word/document.xml"] = Data("<w:document xmlns:w=\"\(DOCX.wordNS)\" xmlns:m=\"\(DOCXEquations.namespace)\"><w:body><w:p>\(math)</w:p></w:body></w:document>".utf8)
            return try ZipArchive.encode(parts)
        }
        let styled = "<m:oMath><m:r><m:rPr><m:sty m:val=\"bi\"/></m:rPr><m:t>x</m:t></m:r></m:oMath>"
        let result = try DOCX.decode(package(styled))
        XCTAssertNotNil(result.document.paragraphs[0].runs[0].equation)
        XCTAssertTrue(result.warnings.contains { $0.contains("bold styling") })
        let nested = "<m:oMath>" + String(repeating: "<m:box><m:e>", count: 40) + "<m:r><m:t>x</m:t></m:r>" + String(repeating: "</m:e></m:box>", count: 40) + "</m:oMath>"
        XCTAssertThrowsError(try DOCX.decode(package(nested)))
    }
    func testUnknownMathRetainsTextAndAlternateNamespacePrefixImports() throws {
        var parts = try ZipArchive.decode(DOCX.encode(ScribeDocument()))
        let body = "<q:oMath><q:acc><q:e><q:r><q:t>x</q:t></q:r></q:e></q:acc></q:oMath>"
        parts["word/document.xml"] = Data("<w:document xmlns:w=\"\(DOCX.wordNS)\" xmlns:q=\"\(DOCXEquations.namespace)\"><w:body><w:p><w:r><w:t>Before </w:t></w:r>\(body)<w:r><w:t> after</w:t></w:r></w:p></w:body></w:document>".utf8)
        let fallback = try DOCX.decode(ZipArchive.encode(parts))
        XCTAssertEqual(fallback.document.plainText, "Before [Equation: x] after")
        XCTAssertTrue(fallback.warnings.contains { $0.contains("unsupported equation") })
        let math = DOCXEquations.xml(try Equation(source: #"\frac{1}{2}"#)).replacingOccurrences(of: "m:", with: "q:").replacingOccurrences(of: "xmlns:m", with: "xmlns:q")
        parts["word/document.xml"] = Data("<w:document xmlns:w=\"\(DOCX.wordNS)\"><w:body><w:p>\(math)</w:p></w:body></w:document>".utf8)
        let imported = try DOCX.decode(ZipArchive.encode(parts))
        XCTAssertEqual(imported.document.paragraphs[0].runs.first?.equation?.expression, try MathParser.parse(#"\frac{1}{2}"#))
    }
}
