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
        try compareWithFullLayout(editor, document: document, phase: "Baseline")
        editor.storage.replaceCharacters(in: NSRange(location: 1, length: 0), with: "x")
        editor.paginate()
        XCTAssertLessThan(editor.lastPaginationVisitedPages, count)
        try compareWithFullLayout(editor, document: document, phase: "Typed")
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
    func testWrappingAtPageBoundariesAndFallbackEditsMatchFullLayout() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = (0..<90).map { index in
            var paragraph = Paragraph("Paragraph \(index). " + String(repeating: "Wrapping must retain every line and page. ", count: 7), style: index % 9 == 0 ? "heading2" : "normal")
            paragraph.pageBreakBefore = index > 0 && index % 23 == 0
            return paragraph
        }
        let editor = PaginatedEditor(document: document); defer { editor.prepareForClose() }
        try compareWithFullLayout(editor, document: document, phase: "MixedBaseline")
        for iteration in 0..<12 {
            let page = min(editor.textViews.count - 1, iteration)
            let glyphs = editor.layout.glyphRange(for: editor.layout.textContainers[page])
            let range = editor.layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let position = max(0, NSMaxRange(range) - 1)
            let inserted = iteration % 2 == 0 ? "x" : String(repeating: " measured ", count: 12)
            editor.storage.replaceCharacters(in: NSRange(location: position, length: 0), with: inserted)
            editor.paginate(); try compareWithFullLayout(editor, document: document, phase: "Boundary-\(iteration)")
        }
        editor.storage.replaceCharacters(in: NSRange(location: 0, length: 3), with: "")
        editor.paginate(); try compareWithFullLayout(editor, document: document)
        editor.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "New ")
        document.model.sections[0].page.left += 24
        editor.setPageSettings(document.model.sections[0].page)
        try compareWithFullLayout(editor, document: document)
    }
    private func compareWithFullLayout(_ editor: PaginatedEditor, document: ScribeFileDocument, phase: String = "Edited") throws {
        let fresh = PaginatedEditor(document: document, projectedContent: editor.storage); defer { fresh.prepareForClose() }
        XCTAssertEqual(editor.textViews.count, fresh.textViews.count)
        for index in 0..<min(editor.textViews.count, fresh.textViews.count) {
            let a = editor.layout.textContainers[index], b = fresh.layout.textContainers[index]
            editor.layout.ensureLayout(for: a); fresh.layout.ensureLayout(for: b)
            XCTAssertEqual(editor.layout.glyphRange(for: a), fresh.layout.glyphRange(for: b), "Page \(index)")
            // Compare glyph baselines, not aggregate usedRect trailing paragraph space.
            var originalLines: [(Int, NSPoint)] = [], freshLines: [(Int, NSPoint)] = []
            editor.layout.enumerateLineFragments(forGlyphRange: editor.layout.glyphRange(for: a)) { rect, _, _, range, _ in
                let position = editor.layout.location(forGlyphAt: range.location)
                originalLines.append((range.location, NSPoint(x: rect.minX + position.x, y: rect.minY + position.y)))
            }
            fresh.layout.enumerateLineFragments(forGlyphRange: fresh.layout.glyphRange(for: b)) { rect, _, _, range, _ in
                let position = fresh.layout.location(forGlyphAt: range.location)
                freshLines.append((range.location, NSPoint(x: rect.minX + position.x, y: rect.minY + position.y)))
            }
            XCTAssertEqual(originalLines.map(\.0), freshLines.map(\.0), "\(phase), page \(index)")
            XCTAssertEqual(originalLines.map(\.1), freshLines.map(\.1), "\(phase), page \(index)")
            if phase == "Baseline", index == 0, editor.layout.usedRect(for: a) != fresh.layout.usedRect(for: b) {
                print("Used-rectangle difference \(phase), page \(index): \(editor.layout.usedRect(for: a)) versus \(fresh.layout.usedRect(for: b))")
            }
        }
        if phase != "Edited", let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try PrintRenderer(editor: editor).exportPDF(to: folder.appendingPathComponent("Incremental-" + phase + ".pdf"), title: phase, author: "")
            try PrintRenderer(editor: fresh).exportPDF(to: folder.appendingPathComponent("Full-" + phase + ".pdf"), title: phase, author: "")
        }
    }
}
#endif
