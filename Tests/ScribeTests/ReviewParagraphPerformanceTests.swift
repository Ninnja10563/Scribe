#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ReviewParagraphPerformanceTests: XCTestCase {
    func testTrackedReturnAtFrontMiddleAndEndOfLongDocument() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = (0..<1600).map {
            Paragraph("Paragraph \($0). " + String(repeating: "Document layout must preserve glyph coverage and page continuity. ", count: 6))
        }
        let original = document.model.paragraphs.map(\.text)
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        editor.reviewEditing.author = .init(name: "Writer")
        XCTAssertGreaterThan(editor.canvas.pageCount, 200)
        var measurements: [[String: Any]] = []
        for position in ["end", "middle", "front"] {
            let location = position == "end" ? editor.storage.length - 1 : (position == "middle" ? editor.storage.length / 2 : 0)
            editor.select(NSRange(location: location, length: 0))
            let began = ProcessInfo.processInfo.systemUptime
            editor.activeTextView.insertNewline(nil)
            let committed = ProcessInfo.processInfo.systemUptime
            editor.paginate()
            measurements.append(["position": position, "pages": editor.canvas.pageCount,
                "returnSeconds": committed - began, "replacedUTF16Length": document.lastStructureReplacementLength,
                "subsequentLayoutSeconds": ProcessInfo.processInfo.systemUptime - committed])
            XCTAssertLessThan(document.lastStructureReplacementLength, 2048)
            var end = 0
            for container in editor.layout.textContainers {
                let range = editor.layout.glyphRange(for: container)
                XCTAssertEqual(range.location, end); end = NSMaxRange(range)
            }
            XCTAssertEqual(end, editor.layout.numberOfGlyphs)
        }
        var model = document.snapshot(); try NativeFormat.validate(model)
        XCTAssertEqual(model.paragraphs.count, original.count + 3)
        XCTAssertEqual(model.pendingRevisionIDs.count, 3)
        try model.resolveAllRevisions(accepting: false)
        XCTAssertEqual(model.paragraphs.map(\.text), original)
        print("Tracked Return measurements: \(measurements)")
        if let path = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let suffix = ProcessInfo.processInfo.environment["ASAN_OPTIONS"] == nil ? "" : "-ASan"
            try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
                .write(to: folder.appendingPathComponent("ReviewParagraphMeasurements" + suffix + ".json"))
        }
    }
}
#endif
