import XCTest
import DocumentCore
@testable import ImportExport

final class PageGeometryTests: XCTestCase {
    func testCustomPaperUsesRealOfficeGeometry() throws {
        var document = ScribeDocument(), page = PageSettings()
        page.width = 480.75; page.height = 600.25; page.top = 60.125; page.left = 48.5
        try document.applyPageLayout(page, sectionID: document.sections[0].id)
        let data = try DOCX.encode(document)
        let result = try DOCX.decode(data).document.sections[0].page
        XCTAssertEqual(result.width, page.width, accuracy: 0.05)
        XCTAssertEqual(result.height, page.height, accuracy: 0.05)
        XCTAssertEqual(result.top, page.top, accuracy: 0.05)
        XCTAssertEqual(result.left, page.left, accuracy: 0.05)
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent("CustomPaper.docx"))
        }
    }
}
