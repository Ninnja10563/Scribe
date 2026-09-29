import XCTest
@testable import DocumentCore

final class RunningContentTests: XCTestCase {
    func testFirstPagePrecedesNumberedParityAndDisabledVariantsAreRetained() {
        var section = Section(); section.header = "Default header"; section.footer = "Default footer"
        var variants = RunningContentVariants()
        variants.differentFirstPage = true; variants.differentOddEvenPages = true
        variants.firstHeader = "Cover"; variants.firstFooter = ""
        variants.evenHeader = "Even"; variants.evenFooter = "Even footer"
        section.runningContent = variants
        XCTAssertEqual(section.runningText(isHeader: true, pageIndex: 0), "Cover")
        XCTAssertEqual(section.runningText(isHeader: false, pageIndex: 0), "")
        XCTAssertEqual(section.runningText(isHeader: true, pageIndex: 1), "Even")
        XCTAssertEqual(section.runningText(isHeader: false, pageIndex: 2), "Default footer")
        section.pageNumbering = PageNumbering(start: 2)
        XCTAssertEqual(section.runningText(isHeader: true, pageIndex: 0), "Cover")
        XCTAssertEqual(section.runningText(isHeader: true, pageIndex: 1), "Default header")
        XCTAssertEqual(section.runningText(isHeader: true, pageIndex: 2), "Even")
        section.runningContent?.differentFirstPage = false
        section.runningContent?.differentOddEvenPages = false
        XCTAssertEqual(section.runningText(isHeader: true, pageIndex: 0), "Default header")
        XCTAssertEqual(section.runningContent?.firstHeader, "Cover")
    }
    func testVersionTenMigrationAndNativeRoundTripPreserveRunningContent() throws {
        var document = ScribeDocument()
        document.sections[0].header = "Older header"; document.sections[0].footer = "Older footer"
        var json = try JSONSerialization.jsonObject(with: NativeFormat.encode(document)) as! [String: Any]
        json["formatVersion"] = 10
        let oldBytes = try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
        let reopened = try NativeFormat.decode(oldBytes)
        XCTAssertEqual(reopened.formatVersion, 11)
        XCTAssertNil(reopened.sections[0].runningContent)
        XCTAssertEqual(reopened.sections[0].runningText(isHeader: true, pageIndex: 2), "Older header")
        XCTAssertEqual(reopened.sections[0].runningText(isHeader: false, pageIndex: 0), "Older footer")
        var variants = RunningContentVariants(); variants.firstHeader = "Résumé 👩🏽‍💻"; variants.differentFirstPage = true
        document.sections[0].runningContent = variants
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: oldBytes) as? NSDictionary, json as NSDictionary)
    }
}
