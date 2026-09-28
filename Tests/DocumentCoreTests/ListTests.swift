import XCTest
@testable import DocumentCore

final class ListTests: XCTestCase {
    func testIndependentSeriesResumeAndRestart() throws {
        let first = UUID(), second = UUID(); var counter = ListNumbering()
        XCTAssertEqual(counter.marker(for: .init(kind: .decimal, seriesID: first)), "1.")
        XCTAssertEqual(counter.marker(for: .init(kind: .decimal, start: 8, seriesID: second)), "8.")
        XCTAssertNil(counter.marker(for: nil))
        XCTAssertEqual(counter.marker(for: .init(kind: .decimal, seriesID: first)), "2.")
        XCTAssertEqual(counter.marker(for: .init(kind: .decimal, start: 4, seriesID: first, restart: true)), "4.")
        XCTAssertEqual(counter.marker(for: .init(kind: .decimal, seriesID: first)), "5.")
        XCTAssertEqual(ListNumbering.marker(number: 27, kind: .upperAlpha), "AA.")
        XCTAssertEqual(ListNumbering.marker(number: 9, kind: .upperRoman), "IX.")
        var doc = ScribeDocument(); doc.sections[0].paragraphs[0].list = .init(kind: .upperRoman, start: 4, seriesID: first, restart: true)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(doc)), doc)
    }
    func testListSplitPreservesUnicodeRunsAndExitsEmptyItems() throws {
        var document = ScribeDocument(); let id = document.paragraphs[0].id
        var bold = TextFormatting(); bold.bold = true
        document.sections[0].paragraphs[0].runs = [TextRun("Résumé ", format: bold), TextRun("👩🏽‍💻 text", link: "https://example.com")]
        document.sections[0].paragraphs[0].list = .init(kind: .decimal, start: 4, restart: true)
        let original = document
        XCTAssertNil(document.splitListItem(id: id, range: NSRange(location: 8, length: 0)))
        XCTAssertEqual(document, original)
        let next = try XCTUnwrap(document.splitListItem(id: id, range: NSRange(location: 7, length: 0)))
        XCTAssertEqual(document.paragraphs.map(\.text), ["Résumé ", "👩🏽‍💻 text"])
        XCTAssertEqual(document.paragraphs[0].runs[0].format.bold, true)
        XCTAssertEqual(document.paragraphs[1].runs[0].link, "https://example.com")
        XCTAssertNil(document.paragraphs[1].list?.restart)
        let empty = try XCTUnwrap(document.splitListItem(id: next, range: NSRange(location: (document.paragraphs[1].text as NSString).length, length: 0)))
        XCTAssertNotNil(document.paragraphs.last?.list)
        XCTAssertEqual(document.splitListItem(id: empty, range: NSRange(location: 0, length: 0)), empty)
        XCTAssertNil(document.paragraphs.last?.list)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
    }
    func testVersionTwoMigrationPreservesLegacyLists() throws {
        var doc = ScribeDocument(); doc.sections[0].paragraphs[0].list = .init(kind: .decimal, start: 5)
        var json = try JSONSerialization.jsonObject(with: NativeFormat.encode(doc)) as! [String: Any]
        json["formatVersion"] = 2
        let source = try JSONSerialization.data(withJSONObject: json)
        let result = try NativeFormat.decode(source)
        XCTAssertEqual(result.formatVersion, 3)
        XCTAssertNil(result.paragraphs[0].list?.seriesID)
        XCTAssertEqual(result.paragraphs[0].list?.start, 5)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: source) as! [String: Any])["formatVersion"] as? Int, 2)
        doc.sections[0].paragraphs[0].list?.start = Int.max
        XCTAssertThrowsError(try NativeFormat.encode(doc))
    }
}
