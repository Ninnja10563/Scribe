#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ReviewTypingPerformanceTests: XCTestCase {
    func testTrackedTypingAtFrontMiddleAndEndOfLongDocument() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = (0..<1600).map { Paragraph("Paragraph \($0). " + String(repeating: "Document layout must preserve glyph coverage and page continuity. ", count: 6)) }
        let original = document.model.paragraphs.map(\.text)
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        editor.reviewEditing.author = .init(name: "Reviewer")
        XCTAssertGreaterThan(editor.canvas.pageCount, 200)
        var measurements: [[String: Any]] = []
        for position in ["end", "middle", "front"] {
            let location = position == "end" ? editor.storage.length - 1 : (position == "middle" ? editor.storage.length / 2 : 0)
            editor.select(NSRange(location: location, length: 0))
            let began = Date()
            editor.activeTextView.insertText("x", replacementRange: NSRange(location: location, length: 0))
            let typed = Date(); editor.paginate()
            let result: [String: Any] = ["position": position, "pages": editor.canvas.pageCount,
                "typingSeconds": typed.timeIntervalSince(began), "layoutSeconds": Date().timeIntervalSince(typed),
                "visitedPages": editor.lastPaginationVisitedPages,
                "addressSanitizer": ProcessInfo.processInfo.environment["ASAN_OPTIONS"] != nil]
            measurements.append(result)
            var end = 0
            for container in editor.layout.textContainers {
                let range = editor.layout.glyphRange(for: container)
                XCTAssertEqual(range.location, end); end = NSMaxRange(range)
            }
            XCTAssertEqual(end, editor.layout.numberOfGlyphs)
        }
        var captured = document.snapshot(); try NativeFormat.validate(captured)
        XCTAssertEqual(captured.pendingRevisionIDs.count, 3)
        try captured.resolveAllRevisions(accepting: false)
        XCTAssertEqual(captured.paragraphs.map(\.text), original)
        print("Tracked typing measurements: \(measurements)")
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let suffix = ProcessInfo.processInfo.environment["ASAN_OPTIONS"] == nil ? "" : "-ASan"
            try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("ReviewTypingMeasurements" + suffix + ".json"))
        }
    }
}
#endif
