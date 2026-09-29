import Foundation
import XCTest
@testable import Scribe

final class FootnotePagePlanTests: XCTestCase {
    func testNewReferenceCannotOscillateBackIntoThePreviousPage() throws {
        let first = UUID(), second = UUID()
        let lines: [FootnotePagePlan.Line] = [
            .init(bottom: 40, noteIDs: [first]), .init(bottom: 80, noteIDs: []),
            .init(bottom: 120, noteIDs: []), .init(bottom: 160, noteIDs: []),
            .init(bottom: 180, noteIDs: [second]), .init(bottom: 220, noteIDs: [])
        ]
        let plan = try FootnotePagePlan.choose(lines: lines, pageHeight: 300, noteHeights: [first: 80, second: 100])
        XCTAssertEqual(plan.lineCount, 4); XCTAssertEqual(plan.noteIDs, [first])
        XCTAssertEqual(plan.noteHeight, 92)
        XCTAssertGreaterThanOrEqual(plan.bodyHeight, 160); XCTAssertLessThan(plan.bodyHeight, 180)
        XCTAssertFalse(plan.needsContinuation)
    }
    func testMeasuredNotesReserveSpaceWithoutChangingPagesWithoutReferences() throws {
        let id = UUID()
        let plain = try FootnotePagePlan.choose(lines: [.init(bottom: 290, noteIDs: [])], pageHeight: 300, noteHeights: [:])
        XCTAssertEqual(plain.bodyHeight, 300); XCTAssertEqual(plain.noteHeight, 0)
        let notes = try FootnotePagePlan.choose(lines: [.init(bottom: 40, noteIDs: [id]), .init(bottom: 200, noteIDs: []), .init(bottom: 240, noteIDs: [])], pageHeight: 300, noteHeights: [id: 80])
        XCTAssertEqual(notes.lineCount, 2); XCTAssertEqual(notes.bodyHeight, 208)
    }
    func testOversizedNotesRequireContinuationInsteadOfProducingAnEmptyPageLoop() throws {
        let id = UUID()
        let plan = try FootnotePagePlan.choose(lines: [.init(bottom: 20, noteIDs: [id])], pageHeight: 300, noteHeights: [id: 400])
        XCTAssertEqual(plan.lineCount, 0); XCTAssertTrue(plan.needsContinuation)
        XCTAssertThrowsError(try FootnotePagePlan.choose(lines: [.init(bottom: 20, noteIDs: [id])], pageHeight: 300, noteHeights: [:]))
        XCTAssertThrowsError(try FootnotePagePlan.choose(lines: [.init(bottom: .nan, noteIDs: [])], pageHeight: 300, noteHeights: [:]))
    }
}
