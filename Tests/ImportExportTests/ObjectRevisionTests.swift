import Foundation
import XCTest
import DocumentCore
@testable import ImportExport

final class ObjectRevisionTests: XCTestCase {
    private let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAKElEQVR4nGP4z8BAEiJNNRlo1IJRCwbAAlJ1/P/PQBIatWDUgiFgAQAk0H2fCntH2wAAAABJRU5ErkJggg==")!
    func testReviewedObjectsRetainPayloadsAndDecisions() throws {
        var document = ScribeDocument()
        let author = RevisionAuthor(name: "Object reviewer")
        var inserted = RunReview(), deleted = RunReview()
        inserted.insertion = .init(author: author); deleted.deletion = .init(author: author)
        var picture = TextRun("\u{fffc}"); picture.image = InlineImage(data: image, fileExtension: "png", width: 64, height: 32, altText: "Reviewed image"); picture.review = inserted
        var equation = TextRun("\u{fffc}"); equation.equation = try Equation(source: #"\frac{1}{2}"#); equation.review = deleted
        let note = DocumentNote(kind: .footnote, text: "Retained note payload")
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id; reference.review = deleted
        document.notes = [note]
        document.sections[0].paragraphs[0].runs = [TextRun("Objects "), picture, equation, reference]
        let bytes = try DOCXWriter(document, revisions: .runChanges).encode()
        let imported = try DOCX.decodePreservingRevisions(bytes).document
        let runs = imported.paragraphs[0].runs
        XCTAssertEqual(runs.compactMap(\.image).first?.data, image)
        XCTAssertEqual(runs.compactMap(\.image).first?.width, 64)
        XCTAssertEqual(runs.compactMap(\.equation).first?.expression, equation.equation?.expression)
        XCTAssertEqual(imported.notes[0].plainText, note.plainText)
        XCTAssertEqual(runs.filter { $0.image != nil }.first?.review?.insertion?.author.name, author.name)
        XCTAssertEqual(runs.filter { $0.equation != nil }.first?.review?.deletion?.author.name, author.name)
        XCTAssertEqual(runs.filter { $0.noteID != nil }.first?.review?.deletion?.author.name, author.name)
        for accepting in [true, false] {
            var copy = imported; try copy.resolveAllRevisions(accepting: accepting)
            XCTAssertEqual(copy.paragraphs[0].runs.compactMap(\.image).count, accepting ? 1 : 0)
            XCTAssertEqual(copy.paragraphs[0].runs.compactMap(\.equation).count, accepting ? 0 : 1)
            XCTAssertEqual(copy.notes.count, accepting ? 0 : 1)
        }
        if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            try bytes.write(to: URL(fileURLWithPath: folder).appendingPathComponent("ObjectRevisions.docx"), options: .atomic)
        }
    }
    func testTextSurroundingDrawingInOneRunKeepsItsProperties() throws {
        var document = ScribeDocument(), picture = TextRun("\u{fffc}")
        picture.image = InlineImage(data: image, fileExtension: "png", width: 64, height: 32)
        document.sections[0].paragraphs[0].runs = [picture]
        var parts = try ZipArchive.decode(DOCX.encode(document))
        let xml = String(decoding: try XCTUnwrap(parts["word/document.xml"]), as: UTF8.self)
        let start = try XCTUnwrap(xml.range(of: "<w:drawing>")), end = try XCTUnwrap(xml.range(of: "</w:drawing>"))
        let drawing = xml[start.lowerBound..<end.upperBound]
        let prefix = xml[..<(try XCTUnwrap(xml.range(of: "<w:body>"))).lowerBound]
        let body = "<w:p><w:r><w:rPr><w:b/><w:i/></w:rPr><w:t>Before</w:t>\(drawing)<w:t>After</w:t></w:r></w:p>"
        parts["word/document.xml"] = Data("\(prefix)<w:body>\(body)</w:body></w:document>".utf8)
        let imported = try DOCX.decode(ZipArchive.encode(parts)).document
        let text = imported.paragraphs[0].runs.filter { $0.image == nil }
        XCTAssertEqual(text.map(\.text), ["Before", "After"])
        XCTAssertTrue(text.allSatisfy { $0.format.bold == true && $0.format.italic == true })
    }

    func testMissingReviewedImageCannotDisappearSilently() throws {
        var document = ScribeDocument(), run = TextRun("\u{fffc}"), review = RunReview()
        review.insertion = .init(author: .init(name: "Editor")); run.review = review
        run.image = InlineImage(data: image, fileExtension: "png", width: 64, height: 32)
        document.sections[0].paragraphs[0].runs = [run]
        var parts = try ZipArchive.decode(DOCXWriter(document, revisions: .runChanges).encode())
        for name in parts.keys where name.hasPrefix("word/media/") { parts.removeValue(forKey: name) }
        XCTAssertThrowsError(try DOCX.decodePreservingRevisions(ZipArchive.encode(parts)))
    }
}
