import XCTest
import DocumentCore
@testable import ImportExport

final class RunningContentInterchangeTests: XCTestCase {
    func testIndependentFirstEvenAndCustomStartFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "RunningContent", withExtension: "docx", subdirectory: "Fixtures"))
        let section = try DOCX.decode(Data(contentsOf: url)).document.sections[0]
        XCTAssertEqual(section.header, "Independent default header")
        XCTAssertEqual(section.runningContent?.firstFooter, "Cover footer — résumé")
        XCTAssertEqual(section.runningContent?.differentFirstPage, true)
        XCTAssertEqual(section.runningContent?.differentOddEvenPages, true)
        XCTAssertEqual(section.runningContent?.startingPageNumber, 2)
        XCTAssertEqual(section.runningText(isHeader: true, pageIndex: 0), "")
        XCTAssertEqual(section.runningText(isHeader: true, pageIndex: 1), "Independent default header")
        XCTAssertEqual(section.runningText(isHeader: true, pageIndex: 2), "Independent even header")
    }
    func testActualVariantPartsRoundTripWithoutReplacingDefaultText() throws {
        var document = ScribeDocument()
        document.sections[0].header = "Default header"; document.sections[0].footer = "Default footer"
        var variants = RunningContentVariants()
        variants.differentFirstPage = true; variants.differentOddEvenPages = true
        variants.firstFooter = "Cover footer"; variants.evenHeader = "Even header"; variants.evenFooter = "Even footer"
        variants.startingPageNumber = 2
        document.sections[0].runningContent = variants
        document.sections[0].paragraphs = (0..<3).map { index in
            var p = Paragraph("Running content page \(index + 1)"); p.pageBreakBefore = index > 0; return p
        }
        let data = try DOCX.encode(document), parts = try ZipArchive.decode(data)
        let body = try XCTUnwrap(String(data: parts["word/document.xml"]!, encoding: .utf8))
        XCTAssertEqual(body.components(separatedBy: "headerReference").count - 1, 3)
        XCTAssertEqual(body.components(separatedBy: "footerReference").count - 1, 3)
        XCTAssertTrue(body.contains("<w:titlePg/>"))
        XCTAssertTrue(String(data: parts["word/settings.xml"]!, encoding: .utf8)!.contains("<w:evenAndOddHeaders/>"))
        XCTAssertTrue(String(data: parts["word/header1-first.xml"]!, encoding: .utf8)!.contains("<w:p/>"))
        let imported = try DOCX.decode(data)
        XCTAssertTrue(imported.warnings.contains { $0.contains("physical page order") })
        let reopened = imported.document.sections[0]
        XCTAssertEqual(reopened.header, "Default header"); XCTAssertEqual(reopened.footer, "Default footer")
        XCTAssertEqual(reopened.runningContent, variants)
        if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try data.write(to: url.appendingPathComponent("RunningContent.docx"))
            document.sections[0].runningContent?.startingPageNumber = 1
            try DOCX.encode(document).write(to: url.appendingPathComponent("RunningContentStandard.docx"))
        }
    }
    func testDisabledVariantTextIsNotActivatedOrLostInDOCX() throws {
        var document = ScribeDocument()
        document.sections[0].header = "Active header"
        var variants = RunningContentVariants(); variants.firstHeader = "Dormant first"; variants.evenFooter = "Dormant even"
        document.sections[0].runningContent = variants
        let data = try DOCX.encode(document), reopened = try DOCX.decode(data).document.sections[0]
        XCTAssertEqual(reopened.runningContent, variants)
        XCTAssertEqual(reopened.runningText(isHeader: true, pageIndex: 0), "Active header")
        XCTAssertEqual(reopened.runningText(isHeader: false, pageIndex: 1), "")
    }
    func testWordGlobalEvenSettingDoesNotBlankSectionsUsingOneHeader() throws {
        var document = ScribeDocument(); document.sections.append(Section())
        var variants = RunningContentVariants(); variants.differentOddEvenPages = true; variants.evenHeader = "First section even"
        document.sections[0].runningContent = variants
        document.sections[1].header = "Second section all pages"
        let parts = try ZipArchive.decode(DOCX.encode(document))
        XCTAssertTrue(String(data: parts["word/header2-even.xml"]!, encoding: .utf8)!.contains("Second section all pages"))
        XCTAssertNotNil(parts["word/footer2.xml"])
    }
}
