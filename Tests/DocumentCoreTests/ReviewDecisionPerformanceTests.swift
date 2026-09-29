import Foundation
import XCTest
@testable import DocumentCore

final class ReviewDecisionPerformanceTests: XCTestCase {
    func testBulkSeparatorRejectionPreservesLongTextAndAnnotations() throws {
        var measurements: [[String: Any]] = []
        let text = String(repeating: "Long document review preserves authored content. ", count: 8)
        for count in [250, 1000, 2000] {
            var document = ScribeDocument(), review = RunReview()
            review.insertion = .init(author: .init(name: "Writer"))
            document.sections[0].paragraphs = (0..<count).map { index in
                var paragraph = Paragraph(text); paragraph.breakReview = index + 1 < count ? review : nil; return paragraph
            }
            let first = document.paragraphs[0].id, last = document.paragraphs[count - 1].id
            document.comments = [.init(anchor: .init(paragraphID: last, offset: 3, length: 8), text: "Last paragraph", author: "Reader")]
            _ = document.addParagraphBookmark(name: "Last", paragraphID: last)
            let began = ProcessInfo.processInfo.systemUptime
            try document.resolveAllRevisions(accepting: false)
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            XCTAssertEqual(document.paragraphs.count, 1)
            XCTAssertEqual(document.paragraphs[0].runs.count, 1)
            XCTAssertEqual(document.paragraphs[0].text, String(repeating: text, count: count))
            XCTAssertEqual(document.comments[0].anchor, .init(paragraphID: first, offset: (count - 1) * text.utf16.count + 3, length: 8))
            XCTAssertEqual(document.bookmarks[0].anchor.paragraphID, first)
            XCTAssertFalse(document.hasPendingRevisions)
            measurements.append(["paragraphs": count, "utf16Length": count * text.utf16.count, "decisionSeconds": elapsed])
        }
        print("Bulk review decision measurements: \(measurements)")
        if let path = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let suffix = ProcessInfo.processInfo.environment["ASAN_OPTIONS"] == nil ? "" : "-ASan"
            try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
                .write(to: folder.appendingPathComponent("ReviewDecisionMeasurements" + suffix + ".json"))
        }
    }
}
