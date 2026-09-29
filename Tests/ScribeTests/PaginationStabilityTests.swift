import Foundation
import XCTest
@testable import Scribe

final class PaginationStabilityTests: XCTestCase {
    func testOffsetsFollowMultipleInsertionsAndCannotStopBeforeLastEdit() {
        var state = PaginationStability()
        state.insert(at: 50, length: 2, previousEnds: [100, 200, 300], startingClean: true)
        state.insert(at: 170, length: 3, previousEnds: [], startingClean: false)
        XCTAssertEqual(state.expectedEnds, [102, 205, 305])
        XCTAssertFalse(state.canStop(after: 0, characterEnd: 102, documentLength: 305))
        XCTAssertTrue(state.canStop(after: 1, characterEnd: 205, documentLength: 305))
        XCTAssertEqual(state.remainingRanges(after: 1), [NSRange(location: 205, length: 100)])
        state.insert(at: 20, length: 4, previousEnds: [], startingClean: false)
        XCTAssertEqual(state.editedEnd, 177)
        XCTAssertEqual(state.expectedEnds, [106, 209, 309])
        XCTAssertFalse(state.canStop(after: 1, characterEnd: 205, documentLength: 309))
        state.invalidate()
        state.insert(at: 20, length: 1, previousEnds: [100, 200], startingClean: false)
        XCTAssertNil(state.expectedEnds)
    }
}
#if canImport(AppKit)
import AppKit
import DocumentCore
import PDFKit

@MainActor final class IncrementalPaginationTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testStableTypingMatchesFullLayoutIncludingLaterPagesAndPDF() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = (0..<160).map { Paragraph("Entry \($0): " + String(repeating: "A measured line of document text. ", count: 8)) }
        let editor = PaginatedEditor(document: document); defer { editor.prepareForClose() }
        let count = editor.textViews.count
        XCTAssertGreaterThan(count, 10)
        editor.storage.replaceCharacters(in: NSRange(location: 1, length: 0), with: "x")
        editor.paginate()
        XCTAssertLessThan(editor.lastPaginationVisitedPages, count)
        try compareWithFullLayout(editor, document: document)
        // Multiple edits can arrive before the debounced layout pass, including Unicode.
        editor.storage.replaceCharacters(in: NSRange(location: editor.storage.length / 2, length: 0), with: " café 👩🏽‍💻 ")
        editor.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Prefix ")
        editor.paginate(); try compareWithFullLayout(editor, document: document)
        // Flow controls and paragraph formatting must fall back to complete pagination.
        editor.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "\n\u{c}")
        editor.paginate(); try compareWithFullLayout(editor, document: document)
        let style = NSMutableParagraphStyle(); style.lineSpacing = 7
        editor.storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 2, length: editor.storage.length - 2))
        editor.paginate(); try compareWithFullLayout(editor, document: document)
        let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("IncrementalPagination.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Incremental pagination", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url)), text = pdf.string ?? ""
        XCTAssertEqual(pdf.pageCount, editor.textViews.count)
        for index in 1..<160 { XCTAssertEqual(text.components(separatedBy: "Entry \(index):").count - 1, 1) }
    }
    private func compareWithFullLayout(_ editor: PaginatedEditor, document: ScribeFileDocument) throws {
        let fresh = PaginatedEditor(document: document); defer { fresh.prepareForClose() }
        fresh.storage.setAttributedString(editor.storage); fresh.paginate()
        XCTAssertEqual(editor.textViews.count, fresh.textViews.count)
        for index in 0..<min(editor.textViews.count, fresh.textViews.count) {
            let a = editor.layout.textContainers[index], b = fresh.layout.textContainers[index]
            editor.layout.ensureLayout(for: a); fresh.layout.ensureLayout(for: b)
            XCTAssertEqual(editor.layout.glyphRange(for: a), fresh.layout.glyphRange(for: b), "Page \(index)")
            XCTAssertEqual(editor.layout.usedRect(for: a), fresh.layout.usedRect(for: b), "Page \(index)")
        }
    }
}
#endif
