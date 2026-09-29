#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NoteTextLayoutTests: XCTestCase {
    func testRichNoteMeasurementAndVectorOutputUseTheSameGlyphs() throws {
        _ = NSApplication.shared
        var note = DocumentNote(kind: .footnote, text: "A citation — résumé and Unicode text, followed by a longer explanation. ")
        note.paragraphs[0].runs[0].format.italic = true
        note.paragraphs.append(Paragraph("The second paragraph retains its content and wraps within the note writing width."))
        let numbered = try XCTUnwrap(NoteNumbering.resolve(referenceIDs: [note.id], notes: [note]).first)
        let wide = try NoteTextLayout(note: numbered, styles: ParagraphStyle.defaults, width: 400)
        let narrow = try NoteTextLayout(note: numbered, styles: ParagraphStyle.defaults, width: 180)
        XCTAssertGreaterThan(narrow.height, wide.height)
        let second = (narrow.storage.string as NSString).range(of: "The second")
        let secondStyle = try XCTUnwrap(narrow.storage.attribute(.paragraphStyle, at: second.location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(secondStyle.firstLineHeadIndent, 18)
        XCTAssertEqual(secondStyle.headIndent, 18)
        XCTAssertEqual(narrow.glyphRange.length, narrow.layout.numberOfGlyphs)
        let view = NoteDrawingView(note: narrow)
        let data = view.dataWithPDF(inside: view.bounds)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertTrue(pdf.string?.contains("second paragraph") == true)
        XCTAssertTrue(pdf.string?.contains("résumé") == true)
        let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent("NoteTextLayout.pdf"))
    }
}
@MainActor private final class NoteDrawingView: NSView {
    let note: NoteTextLayout
    override var isFlipped: Bool { true }
    init(note: NoteTextLayout) { self.note = note; super.init(frame: NSRect(x: 0, y: 0, width: 220, height: note.height + 40)) }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    override func draw(_ dirtyRect: NSRect) { NSColor.white.setFill(); bounds.fill(); note.draw(at: NSPoint(x: 20, y: 20)) }
}
#endif
