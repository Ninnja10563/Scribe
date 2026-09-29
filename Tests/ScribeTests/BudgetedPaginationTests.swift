#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class BudgetedPaginationTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func document(paragraphs count: Int) -> ScribeFileDocument {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = (0..<count).map {
            Paragraph("Paragraph \($0). " + String(repeating: "Page layout preserves authored text and complete glyph coverage. ", count: 6))
        }
        document.makeWindowControllers(); document.editorController!.editor.reviewEditing.author = .init(name: "Writer")
        return document
    }
    private func ranges(_ editor: PaginatedEditor) -> [NSRange] {
        editor.layout.textContainers.map { editor.layout.glyphRange(for: $0) }
    }
    private func outputFolder() throws -> URL {
        let path = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"]
        let folder = path.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory.appendingPathComponent("Scribe-Budgeted-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    func testLongReflowYieldsAcceptsAnotherEditAndMatchesColdLayout() async throws {
        let document = document(paragraphs: 1600); defer { document.close() }
        let original = document.model.paragraphs.map(\.text), editor = document.editorController!.editor
        document.editorController?.window?.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertGreaterThan(editor.canvas.pageCount, 200)
        editor.select(NSRange(location: 0, length: 0)); editor.activeTextView.insertNewline(nil)
        var completions = 0
        let previous = editor.onLayout
        editor.onLayout = { completions += 1; XCTAssertFalse(editor.hasPendingPagination); previous?() }
        editor.paginateForEditing()
        XCTAssertTrue(editor.lastPaginationYielded); XCTAssertTrue(editor.hasPendingPagination)
        XCTAssertLessThanOrEqual(editor.lastPaginationVisitedPages, 8); XCTAssertEqual(completions, 0)
        editor.activeTextView.insertText("Added", replacementRange: editor.activeTextView.selectedRange())
        let began = ProcessInfo.processInfo.systemUptime
        var previousTick = began, maximumGap = 0.0, ticks = 0, batches: [[String: Any]] = [], pass = editor.paginationPassCount
        while editor.hasPendingPagination && ProcessInfo.processInfo.systemUptime - began < 15 {
            try await Task.sleep(nanoseconds: 2_000_000)
            let now = ProcessInfo.processInfo.systemUptime
            maximumGap = max(maximumGap, now - previousTick); previousTick = now; ticks += 1
            if editor.paginationPassCount != pass {
                pass = editor.paginationPassCount
                batches.append(["seconds": editor.lastPaginationSeconds, "visitedPages": editor.lastPaginationVisitedPages])
                XCTAssertLessThanOrEqual(editor.lastPaginationVisitedPages, 8)
            }
        }
        XCTAssertFalse(editor.hasPendingPagination); XCTAssertGreaterThan(ticks, 1); XCTAssertEqual(completions, 1)
        let model = document.snapshot(); try NativeFormat.validate(model)
        let reference = ScribeFileDocument(); reference.model = model; reference.model.id = UUID()
        reference.makeWindowControllers(); defer { reference.close() }
        let cold = reference.editorController!.editor
        XCTAssertEqual(ranges(editor), ranges(cold)); XCTAssertEqual(editor.canvas.pageCount, cold.canvas.pageCount)
        var end = 0
        for range in ranges(editor) { XCTAssertEqual(range.location, end); end = NSMaxRange(range) }
        XCTAssertEqual(end, editor.layout.numberOfGlyphs)
        var rejected = model; try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.paragraphs.map(\.text), original)
        let folder = try outputFolder(), selected = [0, editor.canvas.pageCount / 2, editor.canvas.pageCount - 1]
        let partialPDF = folder.appendingPathComponent("BudgetedLayout.pdf"), coldPDF = folder.appendingPathComponent("SynchronousLayout.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: partialPDF, title: "Layout comparison", author: "Scribe tests", pages: selected)
        try PrintRenderer(editor: cold).exportPDF(to: coldPDF, title: "Layout comparison", author: "Scribe tests", pages: selected)
        let a = try XCTUnwrap(PDFDocument(url: partialPDF)), b = try XCTUnwrap(PDFDocument(url: coldPDF))
        XCTAssertEqual(a.pageCount, 3); XCTAssertEqual(a.pageCount, b.pageCount)
        for index in 0..<a.pageCount { XCTAssertEqual(a.page(at: index)?.string, b.page(at: index)?.string) }
        let measurements: [String: Any] = ["pages": editor.canvas.pageCount, "heartbeatCount": ticks,
            "maximumHeartbeatGapSeconds": maximumGap, "observedBatches": batches]
        try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("BudgetedPaginationMeasurements.json"))
    }
    func testExistingPDFRendererDrainsPendingPaginationBeforeExport() throws {
        let document = document(paragraphs: 160); defer { document.close() }
        let editor = document.editorController!.editor, renderer = PrintRenderer(editor: document.editorController!.editor)
        editor.select(NSRange(location: 0, length: 0)); editor.activeTextView.insertNewline(nil)
        editor.paginateForEditing(); XCTAssertTrue(editor.hasPendingPagination)
        let url = try outputFolder().appendingPathComponent("PendingLayoutExport.pdf")
        try renderer.exportPDF(to: url, title: "Pending layout", author: "Scribe tests")
        XCTAssertFalse(editor.hasPendingPagination)
        XCTAssertEqual(try XCTUnwrap(PDFDocument(url: url)).pageCount, editor.canvas.pageCount)
        XCTAssertEqual(NSMaxRange(try XCTUnwrap(ranges(editor).last)), editor.layout.numberOfGlyphs)
    }
    func testClosingCancelsQueuedPaginationContinuation() async throws {
        let document = document(paragraphs: 160), editor = document.editorController!.editor
        editor.select(NSRange(location: 0, length: 0)); editor.activeTextView.insertNewline(nil)
        var completed = false; editor.onLayout = { completed = true }
        editor.paginateForEditing(); XCTAssertTrue(editor.hasPendingPagination)
        document.close()
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertNil(editor.owner); XCTAssertFalse(completed)
    }
}
#endif
