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
        guard (1...ScribeDocument.currentVersion).contains(version) else { throw DocumentError.unsupportedVersion(version) }
        var migrated = data
        if version < ScribeDocument.currentVersion {
            // Migrations occur in memory; opening never rewrites the original bytes.
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DocumentError.invalid("missing document object") }
            if version == 1 { json["tables"] = [] }
            // v2 → v3: absent seriesID/restart retain legacy contiguous-list semantics.
            // v3 → v4: legacy comment anchors remain single-paragraph ranges.
            // v4 → v5: absent fontFace retains family/trait-based font selection.
            json["formatVersion"] = ScribeDocument.currentVersion
            migrated = try JSONSerialization.data(withJSONObject: json)
        }
        var document = try JSONDecoder().decode(ScribeDocument.self, from: migrated)
        if version < 4 { document.reconcileCommentAnchors() }
        try validate(document)
        return document
    }
    public static func save(_ document: ScribeDocument, to url: URL) throws {
        try encode(document).write(to: url, options: .atomic)
    }
    public static func validate(_ document: ScribeDocument) throws {
        guard document.formatVersion == ScribeDocument.currentVersion else { throw DocumentError.unsupportedVersion(document.formatVersion) }
        guard !document.sections.isEmpty else { throw DocumentError.invalid("missing section") }
        guard document.sections.allSatisfy({ $0.page.isValid && !$0.paragraphs.isEmpty }) else {
            throw DocumentError.invalid("invalid page geometry or empty section")
        }
        guard Set(document.styles.map(\.id)).count == document.styles.count,
              document.styles.contains(where: { $0.id == "normal" }) else {
            throw DocumentError.invalid("invalid style catalog")
        }
        for section in document.sections {
            if let numbering = section.pageNumbering, !(1...1_000_000).contains(numbering.start) { throw DocumentError.invalid("invalid starting page number") }
        }
        guard Set(document.tables.map(\.id)).count == document.tables.count else { throw DocumentError.invalid("duplicate table identifiers") }
        for table in document.tables {
            var colors = TextFormatting(); colors.foreground = table.borderColor; colors.highlight = table.headerBackground
            try validateText(colors)
            guard (1...100).contains(table.rows), (1...20).contains(table.columnWidths.count),
                  table.columnWidths.allSatisfy({ $0.isFinite && (12...4000).contains($0) }),
                  table.padding.isFinite, (0...50).contains(table.padding),
                  table.borderWidth.isFinite, (0...10).contains(table.borderWidth) else { throw DocumentError.invalid("invalid table geometry") }
        }
        for style in document.styles {
            try validateText(style.text)
            try validateParagraph(style.paragraph)
            if let level = style.headingLevel, !(1...9).contains(level) { throw DocumentError.invalid("invalid heading level") }
        }
        let paragraphs = document.paragraphs
        guard Set(paragraphs.map(\.id)).count == paragraphs.count else { throw DocumentError.invalid("duplicate paragraph identifiers") }
        guard Set(document.comments.map(\.id)).count == document.comments.count else { throw DocumentError.invalid("duplicate comment identifiers") }
        let textIndex = DocumentTextIndex(paragraphs: paragraphs)
        for comment in document.comments where comment.isDetached != true {
            guard textIndex.range(for: comment.anchor) != nil else { throw DocumentError.invalid("invalid comment anchor") }
        }
        for p in paragraphs {
            guard document.styles.contains(where: { $0.id == p.styleID }) else { throw DocumentError.invalid("missing paragraph style") }
            guard !p.text.contains("\n"), !p.text.contains("\r") else { throw DocumentError.invalid("paragraph contains a line separator") }
            if let list = p.list, !(0...8).contains(list.level) || !(1...1_000_000).contains(list.start) { throw DocumentError.invalid("invalid list") }
            if let formatting = p.formatting { try validateParagraph(formatting) }
            if let cell = p.tableCell {
                guard let table = document.tables.first(where: { $0.id == cell.tableID }),
                      (0..<table.rows).contains(cell.row), table.columnWidths.indices.contains(cell.column) else { throw DocumentError.invalid("invalid table cell reference") }
            }
            for run in p.runs {
                try validateText(run.format)
                if let image = run.image {
                    guard run.text == "\u{FFFC}", image.data.count <= 32 * 1024 * 1024,
                          !image.data.isEmpty, ["png", "jpg", "jpeg", "tiff", "heic"].contains(image.fileExtension),
                          image.width.isFinite, image.height.isFinite, (1...4000).contains(image.width), (1...4000).contains(image.height) else { throw DocumentError.invalid("invalid inline image") }
                }
            }
        }
    }
    private static func validateText(_ format: TextFormatting) throws {
        if let face = format.fontFace, face.isEmpty || face.utf8.count > 512 || face.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            throw DocumentError.invalid("invalid font face")
        }
        if let size = format.fontSize, !size.isFinite || !(1...1000).contains(size) { throw DocumentError.invalid("invalid font size") }
        if let baseline = format.baseline, !(-1...1).contains(baseline) { throw DocumentError.invalid("invalid baseline") }
        for color in [format.foreground, format.highlight].compactMap({ $0 }) {
            guard color.count == 7, color.first == "#", UInt32(color.dropFirst(), radix: 16) != nil else { throw DocumentError.invalid("invalid colour") }
        }
    }
    private static func validateParagraph(_ format: ParagraphFormatting) throws {
        guard [format.lineSpacing, format.spaceBefore, format.spaceAfter, format.headIndent, format.tailIndent, format.firstLineIndent]
            .allSatisfy({ $0.isFinite && abs($0) <= 4000 }) else { throw DocumentError.invalid("invalid paragraph geometry") }
    }

}
