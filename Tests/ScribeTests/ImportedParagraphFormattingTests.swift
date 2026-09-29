#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import ImportExport
@testable import Scribe

@MainActor final class ImportedParagraphFormattingTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func importedDocument() throws -> ScribeDocument {
        var source = ScribeDocument(), format = ParagraphFormatting()
        source.styles[0].text.fontFamily = "Helvetica"; source.styles[0].text.fontSize = 12
        format.lineHeight = .init(rule: .multiple, value: 1.5); format.lineSpacing = 0
        format.headIndent = 18; format.firstLineIndent = 18
        source.sections[0].paragraphs = [Paragraph("Unchanged introduction"), Paragraph("First line\u{2028}Second line\u{2028}Third line")]
        source.sections[0].paragraphs[1].formatting = format
        let before = source
        format.lineHeight = .init(rule: .exact, value: 28)
        format.headIndent = 36; format.firstLineIndent = 36; format.alignment = .right
        source.sections[0].paragraphs[1].formatting = format
        source.sections[0].paragraphs[1].pageBreakBefore = true
        try source.recordParagraphFormattingChanges(from: before, identity: .init(author: .init(name: "Paragraph reviewer")))
        return try DOCX.decodePreservingRevisions(DOCXWriter(source, revisions: .runChanges).encode()).document
    }
    func testImportedParagraphDecisionPreservesHistoryThroughUndo() throws {
        let document = ScribeFileDocument(); document.model = try importedDocument()
        document.makeWindowControllers(); defer { document.close() }
        document.undoManager?.removeAllActions()
        let before = document.snapshot(), controller = try XCTUnwrap(document.editorController)
        let id = try XCTUnwrap(before.paragraphs[1].formattingReview?.pendingIDs.first)
        XCTAssertTrue(controller.reviewNavigation.select(id))
        try controller.reviewNavigation.resolveCurrent(accepting: false)
        XCTAssertFalse(document.snapshot().paragraphs[1].pageBreakBefore)
        XCTAssertEqual(document.snapshot().paragraphs[1].formatting?.lineHeight, .init(rule: .multiple, value: 1.5))
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
        document.undoManager?.redo()
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
    }
    func testImportedParagraphDecisionsRenderPageFlowAndSpacing() throws {
        let source = try importedDocument(), original = try NativeFormat.encode(source)
        for mode in [ReviewOutputMode.accepted, .rejected] {
            let session = try ReviewOutputSession(source: source, mode: mode); defer { session.close() }
            XCTAssertNil(session.editor.layoutWarning)
            if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = mode == .accepted ? "Accepted" : "Rejected"
                try session.renderer.exportPDF(to: folder.appendingPathComponent("ImportedParagraphFormatting" + name + ".pdf"), title: name, author: "Paragraph reviewer")
            }
            XCTAssertEqual(try NativeFormat.encode(source), original)
        }
    }
}
#endif
