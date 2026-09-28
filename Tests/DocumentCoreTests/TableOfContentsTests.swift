import XCTest
@testable import DocumentCore

final class TableOfContentsTests: XCTestCase {
    func testTOCUpdatesTitlesLevelsAndPagesWithoutDeletingUserNotes() throws {
        var document = ScribeDocument()
        let introduction = Paragraph("Introduction", style: "heading1"), detail = Paragraph("Detail", style: "heading2")
        document.sections[0].paragraphs = [Paragraph("Cover"), introduction, detail]
        let id = try XCTUnwrap(document.insertTableOfContents(after: document.paragraphs[0].id, pages: [introduction.id: "2", detail.id: "3"]))
        let entries = document.paragraphs.filter { $0.toc?.kind == .entry }
        XCTAssertEqual(entries.map(\.text), ["Introduction\t2", "Detail\t3"])
        XCTAssertEqual(document.outline.count, 2)
        let note = Paragraph("Keep this ordinary note")
        document.sections[0].paragraphs.insert(note, at: 3)
        let headingIndex = try XCTUnwrap(document.sections[0].paragraphs.firstIndex(where: { $0.id == introduction.id }))
        document.sections[0].paragraphs[headingIndex].runs = [TextRun("Renamed introduction")]
        document.refreshTableOfContents(id: id, pages: [introduction.id: "4", detail.id: "5"])
        let updated = document.paragraphs.filter { $0.toc?.kind == .entry }
        XCTAssertEqual(updated.map(\.id), entries.map(\.id))
        XCTAssertEqual(updated.map(\.text), ["Renamed introduction\t4", "Detail\t5"])
        XCTAssertTrue(document.paragraphs.contains(note))
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        document.removeTableOfContents(id: id)
        XCTAssertTrue(document.tablesOfContents.isEmpty)
        XCTAssertTrue(document.paragraphs.contains(note)); XCTAssertEqual(document.outline.count, 2)
    }
    func testDeletedHeadingsAreRemovedAndReviewTextRemainsDetached() throws {
        var document = ScribeDocument(); let heading = Paragraph("A heading", style: "heading1")
        document.sections[0].paragraphs = [Paragraph("Cover"), heading]
        let id = try XCTUnwrap(document.insertTableOfContents(after: document.paragraphs[0].id))
        let entry = try XCTUnwrap(document.paragraphs.first(where: { $0.toc?.kind == .entry }))
        document.comments = [Comment(anchor: .init(paragraphID: entry.id, offset: 0, length: 1), text: "Review the entry", author: "Alex")]
        document.sections[0].paragraphs.removeAll { $0.id == heading.id }
        document.refreshTableOfContents(id: id, pages: [:])
        XCTAssertFalse(document.paragraphs.contains(where: { $0.toc?.kind == .entry }))
        XCTAssertTrue(document.paragraphs.contains(where: { $0.toc?.kind == .empty }))
        XCTAssertEqual(document.comments[0].text, "Review the entry"); XCTAssertEqual(document.comments[0].isDetached, true)
        XCTAssertNoThrow(try NativeFormat.validate(document))
    }
    func testSemanticListSplitDoesNotMarkNewUserTextAsGenerated() throws {
        var document = ScribeDocument(); let heading = Paragraph("Heading", style: "heading1")
        document.sections[0].paragraphs = [Paragraph("Cover"), heading]
        let tocID = try XCTUnwrap(document.insertTableOfContents(after: document.paragraphs[0].id))
        let index = try XCTUnwrap(document.sections[0].paragraphs.firstIndex(where: { $0.toc?.kind == .entry }))
        document.sections[0].paragraphs[index].list = ListDescriptor()
        let paragraph = document.sections[0].paragraphs[index]
        let newID = try XCTUnwrap(document.splitListItem(id: paragraph.id, range: NSRange(location: 0, length: 0)))
        XCTAssertNil(document.paragraphs.first(where: { $0.id == newID })?.toc)
        document.refreshTableOfContents(id: tocID, pages: [:])
        XCTAssertEqual(document.paragraphs.first(where: { $0.id == newID })?.text, paragraph.text)
    }
    func testNumberedHeadingsUseVisibleMarkersWithoutControlCharactersInEntries() throws {
        var document = ScribeDocument()
        let series = UUID()
        var first = Paragraph("Setup\tand scope", style: "heading1")
        first.list = ListDescriptor(kind: .upperRoman, start: 4, seriesID: series)
        var second = Paragraph("Results\u{2028}continued", style: "heading1")
        second.list = ListDescriptor(kind: .upperRoman, start: 4, seriesID: series)
        document.sections[0].paragraphs = [Paragraph("Cover"), first, Paragraph("Body"), second]
        _ = document.insertTableOfContents(after: document.paragraphs[0].id, pages: [first.id: "2", second.id: "3"])
        XCTAssertEqual(document.outline.map(\.title), ["IV. Setup and scope", "V. Results continued"])
        XCTAssertEqual(document.paragraphs.filter { $0.toc?.kind == .entry }.map(\.text), ["IV. Setup and scope\t2", "V. Results continued\t3"])
    }
    func testV5MigrationAndInvalidDefinitions() throws {
        let document = ScribeDocument()
        var json = try JSONSerialization.jsonObject(with: NativeFormat.encode(document)) as! [String: Any]
        json["formatVersion"] = 5; json.removeValue(forKey: "tablesOfContents")
        let migrated = try NativeFormat.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.formatVersion, ScribeDocument.currentVersion); XCTAssertTrue(migrated.tablesOfContents.isEmpty)
        var invalid = document; invalid.tablesOfContents = [DocumentTOC(maximumLevel: 10)]
        XCTAssertThrowsError(try NativeFormat.encode(invalid))
    }
}
