#if canImport(AppKit)
import AppKit
import XCTest
@testable import Scribe

@MainActor final class FootnoteLayoutTests: XCTestCase {
    func testMeasuredLinePlanKeepsReferencesWithTheirReservedNotesAfterReflow() throws {
        _ = NSApplication.shared
        let first = UUID(), second = UUID()
        let key = NSAttributedString.Key("org.scribe.test.noteReference")
        let paragraphs = (1...24).map { index in index == 2 ? "ReferenceOne" : index == 5 ? "ReferenceTwo" : "Measured paragraph \(index)." }
        let style = NSMutableParagraphStyle(); style.lineSpacing = 3
        let storage = NSTextStorage(string: paragraphs.joined(separator: "\n"), attributes: [.font: NSFont.systemFont(ofSize: 14), .paragraphStyle: style])
        storage.addAttribute(key, value: first.uuidString, range: (storage.string as NSString).range(of: "ReferenceOne"))
        storage.addAttribute(key, value: second.uuidString, range: (storage.string as NSString).range(of: "ReferenceTwo"))
        let layout = NSLayoutManager(); storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: 280, height: 300)); container.lineFragmentPadding = 0
        let successor = NSTextContainer(containerSize: NSSize(width: 280, height: 300)); successor.lineFragmentPadding = 0
        layout.addTextContainer(container); layout.addTextContainer(successor)
        func referenceIDs(_ glyphs: NSRange) -> [UUID] {
            var ids: [UUID] = []
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            storage.enumerateAttribute(key, in: characters) { value, _, _ in
                if let value = value as? String, let id = UUID(uuidString: value) { ids.append(id) }
            }
            return ids
        }
        for phase in 0..<2 {
            if phase == 1 { storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: String(repeating: "Earlier body text. ", count: 12) + "\n") }
            container.containerSize.height = 300; layout.textContainerChangedGeometry(container); layout.ensureLayout(for: container)
            var lines: [FootnotePagePlan.Line] = []
            layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { rect, _, _, glyphs, _ in
                lines.append(.init(bottom: rect.maxY, noteIDs: referenceIDs(glyphs)))
            }
            let plan = try FootnotePagePlan.choose(lines: lines, pageHeight: 300, noteHeights: [first: 130, second: 120])
            XCTAssertFalse(plan.needsContinuation); XCTAssertGreaterThan(plan.lineCount, 0)
            container.containerSize.height = plan.bodyHeight
            layout.textContainerChangedGeometry(container); layout.ensureLayout(for: container)
            XCTAssertEqual(referenceIDs(layout.glyphRange(for: container)), plan.noteIDs, "Reserving notes must not bring the excluded reference back onto this page")
            XCTAssertLessThanOrEqual(layout.usedRect(for: container).maxY + plan.noteHeight, 300.5)
            if phase == 0 { XCTAssertEqual(plan.noteIDs, [first]) }
        }
    }
}
#endif
