import XCTest
@testable import DocumentCore

final class DocumentCoreTests: XCTestCase {
    func testNativeRoundTripPreservesStructure() throws {
        var doc = ScribeDocument()
        var heading = Paragraph("Résumé 👩🏽‍💻 & research", style: "heading1")
        heading.runs[0].format.bold = true
        doc.sections[0].paragraphs = [heading, Paragraph("Second paragraph")]
        doc.comments = [Comment(anchor: TextAnchor(paragraphID: heading.id, offset: 0, length: 6), text: "Review", author: "Alex")]
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(doc)), doc)
        XCTAssertEqual(doc.outline.count, 1)
        XCTAssertEqual(doc.outline[0].title, heading.text)
    }
    func testUnknownVersionIsRejectedWithoutMutation() throws {
        let data = Data("{\"formatVersion\":99}".utf8)
        XCTAssertThrowsError(try NativeFormat.decode(data)) { error in
            guard case DocumentError.unsupportedVersion(99) = error else { return XCTFail("Wrong error: \(error)") }
        }
    }
    func testInvalidGeometryAndDuplicateIDsAreRejected() throws {
        var doc = ScribeDocument(); doc.sections[0].page.left = 10000
        XCTAssertThrowsError(try NativeFormat.encode(doc))
        doc.sections[0].page = PageSettings()
        doc.sections[0].paragraphs.append(doc.sections[0].paragraphs[0])
        XCTAssertThrowsError(try NativeFormat.encode(doc))
    }
    func testStyleModificationRemainsSemantic() {
        var doc = ScribeDocument(); doc.sections[0].paragraphs = [Paragraph("Heading", style: "heading1")]
        var style = doc.styles.first { $0.id == "heading1" }!; style.text.fontSize = 40
        doc.updateStyle(style)
        XCTAssertNil(doc.paragraphs[0].runs[0].format.fontSize)
        XCTAssertEqual(doc.style(for: doc.paragraphs[0]).text.fontSize, 40)
        doc.deleteStyle(id: "heading1"); XCTAssertEqual(doc.paragraphs[0].styleID, "heading1")
        doc.updateStyle(ParagraphStyle(id: "custom", name: "Custom")); doc.sections[0].paragraphs[0].styleID = "custom"
        doc.deleteStyle(id: "custom"); XCTAssertEqual(doc.paragraphs[0].styleID, "normal")
    }
    func testSearchUsesUTF16AndLiteralQueries() {
        let text = "👩🏽‍💻 Cat cat scatter [cat]"
        let matches = DocumentSearch.matches(in: text, query: "cat", options: SearchOptions(wholeWord: true))
        XCTAssertEqual(matches.count, 3)
        for range in matches { XCTAssertEqual((text as NSString).substring(with: range).lowercased(), "cat") }
        XCTAssertEqual(DocumentSearch.matches(in: text, query: "cat", options: SearchOptions(matchCase: true)).count, 3)
        XCTAssertEqual(DocumentSearch.matches(in: text, query: "[cat]").count, 1)
        XCTAssertTrue(DocumentSearch.matches(in: text, query: "").isEmpty)
    }
    func testNestedNumberingResumesAndResets() {
        var numbering = ListNumbering()
        XCTAssertEqual(numbering.marker(for: ListDescriptor(kind: .decimal)), "1.")
        XCTAssertEqual(numbering.marker(for: ListDescriptor(kind: .lowerAlpha, level: 1)), "a.")
        XCTAssertEqual(numbering.marker(for: ListDescriptor(kind: .lowerAlpha, level: 1)), "b.")
        XCTAssertEqual(numbering.marker(for: ListDescriptor(kind: .decimal)), "2.")
        XCTAssertNil(numbering.marker(for: nil))
        XCTAssertEqual(numbering.marker(for: ListDescriptor(kind: .lowerRoman, start: 4)), "iv.")
    }
    func testPageNumberFormatsAndInvalidStart() throws {
        XCTAssertEqual(PageNumbering(format: .pageOfTotal, start: 5).label(pageIndex: 1, pageCount: 10), "Page 6 of 14")
        XCTAssertEqual(PageNumbering(format: .roman).label(pageIndex: 8, pageCount: 10), "ix")
        var doc = ScribeDocument(); doc.sections[0].pageNumbering = PageNumbering(start: -1)
        XCTAssertThrowsError(try NativeFormat.encode(doc))
        doc.sections[0].pageNumbering = PageNumbering()
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(doc)), doc)
    }
    func testVersionOneMigrationDoesNotChangeSourceData() throws {
        let document = ScribeDocument()
        var json = try JSONSerialization.jsonObject(with: NativeFormat.encode(document)) as! [String: Any]
        json["formatVersion"] = 1; json.removeValue(forKey: "tables")
        let source = try JSONSerialization.data(withJSONObject: json)
        let loaded = try NativeFormat.decode(source)
        XCTAssertEqual(loaded.formatVersion, 2); XCTAssertTrue(loaded.tables.isEmpty)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: source) as! [String: Any])["formatVersion"] as? Int, 1)
    }
    func testTableMutationsPreserveCellContentAndReferences() throws {
        var document = ScribeDocument()
        document.insertTable(rows: 2, columns: 2, after: document.paragraphs[0].id)
        let id = document.tables[0].id
        document.sections[0].paragraphs[1].runs = [TextRun("Keep me")]
        document.addTableRow(tableID: id, after: 0)
        document.addTableColumn(tableID: id, after: 0)
        XCTAssertEqual(document.tables[0].rows, 3); XCTAssertEqual(document.tables[0].columnWidths.count, 3)
        XCTAssertEqual(document.paragraphs.filter { $0.tableCell != nil }.count, 9)
        document.deleteTableRow(tableID: id, row: 1); document.deleteTableColumn(tableID: id, column: 1)
        XCTAssertEqual(document.paragraphs.filter { $0.tableCell != nil }.count, 4)
        XCTAssertTrue(document.plainText.contains("Keep me"))
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        document.deleteTable(id: id)
        XCTAssertTrue(document.tables.isEmpty); XCTAssertTrue(document.paragraphs.allSatisfy { $0.tableCell == nil })
    }
    func testCombiningMarksStayInsideWords() {
        let text = "cafe\u{301} nai\u{308}ve"
        XCTAssertEqual(DocumentStatistics(text: text).words, 2)
        XCTAssertTrue(DocumentSearch.matches(in: text, query: "cafe", options: SearchOptions(wholeWord: true)).isEmpty)
    }
    func testStatistics() {
        let stats = DocumentStatistics(text: "Don't stop.\nCafé 東京 👩🏽‍💻")
        XCTAssertEqual(stats.words, 4); XCTAssertEqual(stats.paragraphs, 2)
        XCTAssertEqual(DocumentStatistics(text: "").words, 0)
    }
    func testRecoveryNeverWritesOriginalAndSurvivesCorruptSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecoveryStore(directory: directory)
        let document = ScribeDocument(); let original = directory.appendingPathComponent("original.scribe")
        try await store.save(RecoverySnapshot(document: document, originalURL: original))
        try Data("broken".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let snapshots = try await store.snapshots()
        XCTAssertEqual(snapshots.count, 1); XCTAssertEqual(snapshots[0].document, document)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        try await store.remove(id: document.id)
        let remaining = try await store.snapshots(); XCTAssertTrue(remaining.isEmpty)
    }
    func testLargeDocumentSerializationAndSearch() throws {
        var doc = ScribeDocument()
        doc.sections[0].paragraphs = (0..<6000).map { Paragraph("Paragraph \($0). " + String(repeating: "A well structured document remains searchable. ", count: 8)) }
        let start = Date()
        let bytes = try NativeFormat.encode(doc); let loaded = try NativeFormat.decode(bytes)
        XCTAssertEqual(loaded.paragraphs.count, 6000)
        XCTAssertEqual(DocumentSearch.matches(in: loaded.plainText, query: "searchable").count, 48000)
        print("6000-paragraph save/load/search: \(Date().timeIntervalSince(start)) seconds; \(bytes.count) bytes")
    }
}
