import Foundation

public enum DocumentError: LocalizedError {
    case unsupportedVersion(Int), invalid(String), tooLarge
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v): return "This document uses Scribe format \(v). Please use a newer version of Scribe."
        case .invalid(let message): return "The document is invalid: \(message)"
        case .tooLarge: return "The document exceeds the 128 MB safety limit."
        }
    }
}

/// Explicit JSON schema; no executable object deserialization. Saves use atomic replacement.
public enum NativeFormat {
    public static let maximumBytes = 128 * 1024 * 1024
    public static func encode(_ document: ScribeDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw DocumentError.tooLarge }
        return data
    }
    public static func decode(_ data: Data) throws -> ScribeDocument {
        guard data.count <= maximumBytes else { throw DocumentError.tooLarge }
        struct Version: Decodable { let formatVersion: Int }
        let version = try JSONDecoder().decode(Version.self, from: data).formatVersion
        guard version == ScribeDocument.currentVersion else { throw DocumentError.unsupportedVersion(version) }
        // Future migrations must be explicit and preserve the original file.
        let document = try JSONDecoder().decode(ScribeDocument.self, from: data)
        try validate(document)
        return document
    }
    public static func save(_ document: ScribeDocument, to url: URL) throws {
        try encode(document).write(to: url, options: .atomic)
    }
    public static func validate(_ document: ScribeDocument) throws {
        guard !document.sections.isEmpty else { throw DocumentError.invalid("missing section") }
        guard document.sections.allSatisfy({ $0.page.isValid && !$0.paragraphs.isEmpty }) else {
            throw DocumentError.invalid("invalid page geometry or empty section")
        }
        guard Set(document.styles.map(\.id)).count == document.styles.count,
              document.styles.contains(where: { $0.id == "normal" }) else {
            throw DocumentError.invalid("invalid style catalog")
        }
        let paragraphs = document.paragraphs
        guard Set(paragraphs.map(\.id)).count == paragraphs.count else { throw DocumentError.invalid("duplicate paragraph identifiers") }
        for p in paragraphs {
            guard document.styles.contains(where: { $0.id == p.styleID }) else { throw DocumentError.invalid("missing paragraph style") }
            guard !p.text.contains("\n"), !p.text.contains("\r") else { throw DocumentError.invalid("paragraph contains a line separator") }
            if let list = p.list, !(0...8).contains(list.level) || list.start < 1 { throw DocumentError.invalid("invalid list") }
            for run in p.runs {
                if let size = run.format.fontSize, !size.isFinite || !(1...1000).contains(size) {
                    throw DocumentError.invalid("invalid font size")
                }
            }
        }
    }
}
