import XCTest
@testable import DocumentCore

final class RecoveryMigrationTests: XCTestCase {
    func testRecoveryReplacementIsDurableAndFailureKeepsOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecoveryStore(directory: directory)
        var original = ScribeDocument(); original.sections[0].paragraphs[0] = Paragraph("Unsaved work")
        let snapshot = RecoverySnapshot(document: original, originalURL: URL(fileURLWithPath: "/tmp/original.scribe"))
        try await store.save(snapshot)
        var replacement = original; replacement.id = UUID(); replacement.sections = []
        do { try await store.replaceSnapshot(id: original.id, with: RecoverySnapshot(document: replacement, originalURL: snapshot.originalURL)); XCTFail("Invalid replacement accepted") } catch { }
        var recovered = try await store.snapshots()
        XCTAssertEqual(recovered.map { $0.document.id }, [original.id])
        replacement.sections = original.sections
        try await store.replaceSnapshot(id: original.id, with: RecoverySnapshot(document: replacement, originalURL: snapshot.originalURL))
        recovered = try await store.snapshots()
        XCTAssertEqual(recovered.map { $0.document.id }, [replacement.id])
        XCTAssertEqual(recovered.first?.document.plainText, original.plainText)
        XCTAssertEqual(recovered.first?.originalURL, snapshot.originalURL)
    }
    func testCancelledRecoveryWriteDoesNotRecreateClosedWork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecoveryStore(directory: directory), snapshot = RecoverySnapshot(document: ScribeDocument(), originalURL: nil)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.save(snapshot)
        }
        do { try await task.value; XCTFail("Cancelled write completed") } catch is CancellationError { }
        let snapshots = try await store.snapshots()
        XCTAssertTrue(snapshots.isEmpty)
    }
    func testOldSnapshotMigratesWithoutRewritingItsBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = ScribeDocument(), snapshot = RecoverySnapshot(document: ScribeDocument(), originalURL: nil)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        var document = try JSONSerialization.jsonObject(with: NativeFormat.encode(model)) as! [String: Any]
        document["formatVersion"] = 5; document.removeValue(forKey: "tablesOfContents")
        object["document"] = document
        let data = try JSONSerialization.data(withJSONObject: object), url = directory.appendingPathComponent("legacy.json")
        try data.write(to: url)
        let snapshots = try await RecoveryStore(directory: directory).snapshots()
        XCTAssertEqual(snapshots.first?.document.formatVersion, ScribeDocument.currentVersion)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
}
