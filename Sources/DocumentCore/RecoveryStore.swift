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
        try NativeFormat.validate(snapshot.document)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: directory.appendingPathComponent(snapshot.document.id.uuidString).appendingPathExtension("json"), options: .atomic)
    }
    public func snapshots() throws -> [RecoverySnapshot] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.compactMap { url in
                guard let data = try? Data(contentsOf: url), data.count <= NativeFormat.maximumBytes,
                      let snapshot = try? JSONDecoder().decode(RecoverySnapshot.self, from: data),
                      (try? NativeFormat.validate(snapshot.document)) != nil else { return nil }
                return snapshot
            }.sorted { $0.savedAt > $1.savedAt }
    }
    public func remove(id: UUID) throws {
        let url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
