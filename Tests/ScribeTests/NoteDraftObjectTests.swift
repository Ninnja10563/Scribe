#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NoteDraftObjectTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAKElEQVR4nGP4z8BAEiJNNRlo1IJRCwbAAlJ1/P/PQBIatWDUgiFgAQAk0H2fCntH2wAAAABJRU5ErkJggg==")!
    func testWideTallImageFitsDraftWithoutResizingOriginal() throws {
        _ = NSApplication.shared
        var note = DocumentNote(kind: .footnote)
        var run = TextRun("\u{fffc}")
        run.image = InlineImage(data: png, fileExtension: "png", width: 420, height: 620, altText: "Original illustration")
        note.paragraphs[0].runs = [run]
        _ = try NoteTextLayout(note: NoteNumbering.resolve(referenceIDs: [note.id], notes: [note])[0], styles: ParagraphStyle.defaults, width: PageSettings().contentWidth)
        let options = NoteOptions(note: note, styles: ParagraphStyle.defaults)
        defer { options.close() }
        let editor = try XCTUnwrap(options.text.editor)
        XCTAssertTrue(editor.scrollView.hasHorizontalScroller)
        XCTAssertGreaterThan(editor.canvas.pageSettings.contentWidth, 420)
        XCTAssertGreaterThan(editor.canvas.pageSettings.contentHeight, 620)
        XCTAssertNil(editor.outputWarning)
        XCTAssertEqual(try options.note(), note)
        try export(editor, name: "NoteDraftImage")
    }
    func testWideEquationAndListIndentFitWithoutChangingMathematicalSource() throws {
        _ = NSApplication.shared
        var terms = 1
        var equation = try Equation(source: "x", pointSize: 40)
        while EquationLayout(equation: equation).width < 390 {
            terms += 1; equation = try Equation(source: Array(repeating: "x", count: terms).joined(separator: "+"), pointSize: 40)
        }
        var note = DocumentNote(kind: .endnote), run = TextRun("\u{fffc}")
        run.equation = equation; note.paragraphs[0].runs = [run]
        note.paragraphs[0].list = ListDescriptor(kind: .decimal, level: 2)
        _ = try NoteTextLayout(note: NoteNumbering.resolve(referenceIDs: [note.id], notes: [note])[0], styles: ParagraphStyle.defaults, width: 660)
        let options = NoteOptions(note: note, styles: ParagraphStyle.defaults)
        defer { options.close() }
        let editor = try XCTUnwrap(options.text.editor)
        XCTAssertTrue(editor.scrollView.hasHorizontalScroller)
        XCTAssertNil(editor.outputWarning)
        XCTAssertEqual(try options.note(), note)
        try export(editor, name: "NoteDraftEquation")
    }
    private func export(_ editor: PaginatedEditor, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PrintRenderer(editor: editor).exportPDF(to: folder.appendingPathComponent(name + ".pdf"), title: name, author: "Scribe tests")
    }
}
#endif
