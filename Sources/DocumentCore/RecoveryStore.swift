import Foundation

public struct RecoverySnapshot: Codable, Sendable {
    public var document: ScribeDocument
    public var originalURL: URL?
    public var savedAt: Date
    public init(document: ScribeDocument, originalURL: URL?, savedAt: Date = Date()) {
        self.document = document; self.originalURL = originalURL; self.savedAt = savedAt
    }
}
public actor RecoveryStore {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func save(_ snapshot: RecoverySnapshot) throws {
        try Task.checkCancellation()
        try NativeFormat.validate(snapshot.document)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= NativeFormat.maximumBytes else { throw DocumentError.tooLarge }
        try Task.checkCancellation()
        try data.write(to: directory.appendingPathComponent(snapshot.document.id.uuidString).appendingPathExtension("json"), options: .atomic)
    }
    public func snapshots() throws -> [RecoverySnapshot] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.compactMap { url in
                guard let data = try? Data(contentsOf: url), data.count <= NativeFormat.maximumBytes,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rawDocument = json["document"], let documentData = try? JSONSerialization.data(withJSONObject: rawDocument),
                      let document = try? NativeFormat.decode(documentData),
                      let metadata = try? JSONDecoder().decode(RecoveryMetadata.self, from: data) else { return nil }
                return RecoverySnapshot(document: document, originalURL: metadata.originalURL, savedAt: metadata.savedAt)
            }.sorted { $0.savedAt > $1.savedAt }
    }
    /// The new copy is durable before the previous snapshot is retired. Failure
    /// while validating/writing the replacement leaves the original recoverable.
    public func replaceSnapshot(id: UUID, with snapshot: RecoverySnapshot) throws {
        guard snapshot.document.id != id else { throw DocumentError.invalid("a recovered copy needs its own document identity") }
        try save(snapshot)
        try remove(id: id)
    }
    public func remove(id: UUID) throws {
        let url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

private struct RecoveryMetadata: Decodable { let originalURL: URL?; let savedAt: Date }
