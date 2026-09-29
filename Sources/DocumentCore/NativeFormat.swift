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
            if version < 6 { json["tablesOfContents"] = [] }
            // v6 → v7: absent cellStyles and minimumRowHeights inherit table defaults.
            // v7 → v8: absent mergedCells retains the original rectangular grid.
            // v8 → v9: absent image adjustments preserve original image presentation.
            // v9 → v10: absent clearHighlight retains inherited highlight semantics.
            // v10 → v11: absent runningContent uses the legacy header/footer on every page.
            // v11 → v12: absent equation retains legacy text and image runs.
            if version < 13 { json["notes"] = [] } // v12 → v13: earlier documents have no note registry.
            // v13 → v14: absent run review metadata means accepted content.
            // v14 → v15: absent lineHeight retains the original additional-spacing layout.
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
        try validateReviews(document)
        guard !document.sections.isEmpty else { throw DocumentError.invalid("missing section") }
        guard document.sections.allSatisfy({ $0.page.isValid && !$0.paragraphs.isEmpty }) else {
            throw DocumentError.invalid("invalid page geometry or empty section")
        }
        guard Set(document.styles.map(\.id)).count == document.styles.count,
              document.styles.contains(where: { $0.id == "normal" }) else {
            throw DocumentError.invalid("invalid style catalog")
        }
        guard Set(document.tablesOfContents.map(\.id)).count == document.tablesOfContents.count,
              document.tablesOfContents.allSatisfy({ (1...9).contains($0.maximumLevel) }) else { throw DocumentError.invalid("invalid table of contents") }
        let tocIDs = Set(document.tablesOfContents.map(\.id))
        for section in document.sections {
            if let start = section.runningContent?.startingPageNumber, !(1...1_000_000).contains(start) { throw DocumentError.invalid("invalid running-content starting page number") }
            if let numbering = section.pageNumbering, !(1...1_000_000).contains(numbering.start) { throw DocumentError.invalid("invalid starting page number") }
        }
        guard Set(document.tables.map(\.id)).count == document.tables.count else { throw DocumentError.invalid("duplicate table identifiers") }
        for table in document.tables {
            guard (1...100).contains(table.rows), (1...20).contains(table.columnWidths.count),
                  table.columnWidths.allSatisfy({ $0.isFinite && (12...4000).contains($0) }),
                  table.padding.isFinite, (0...50).contains(table.padding),
                  table.borderWidth.isFinite, (0...10).contains(table.borderWidth) else { throw DocumentError.invalid("invalid table geometry") }
            var occupied = Set<Int>()
            for merge in table.mergedCells ?? [] {
                guard merge.row >= 0, merge.column >= 0, merge.rowSpan > 0, merge.columnSpan > 0,
                      merge.rowSpan <= table.rows, merge.columnSpan <= table.columnWidths.count,
                      merge.row <= table.rows - merge.rowSpan, merge.column <= table.columnWidths.count - merge.columnSpan,
                      merge.rowSpan > 1 || merge.columnSpan > 1 else { throw DocumentError.invalid("invalid merged cell") }
                for row in merge.row..<(merge.row + merge.rowSpan) { for column in merge.column..<(merge.column + merge.columnSpan) {
                    guard occupied.insert(row * table.columnWidths.count + column).inserted else { throw DocumentError.invalid("overlapping merged cells") }
                } }
            }
            if let heights = table.minimumRowHeights {
                guard heights.count == table.rows, heights.compactMap({ $0 }).allSatisfy({ $0.isFinite && (1...4000).contains($0) }) else { throw DocumentError.invalid("invalid table row heights") }
            }
            if let cells = table.cellStyles {
                guard cells.count <= 2000, cells.allSatisfy({ (0..<table.rows).contains($0.row) && table.columnWidths.indices.contains($0.column) }),
                      Set(cells.map { "\($0.row):\($0.column)" }).count == cells.count else { throw DocumentError.invalid("invalid table cell styles") }
                for cell in cells {
                    var colors = TextFormatting(); colors.foreground = cell.borderColor; colors.highlight = cell.background
                    try validateText(colors)
                    if let padding = cell.padding, !padding.isFinite || !(0...50).contains(padding) { throw DocumentError.invalid("invalid cell padding") }
                    if let border = cell.borderWidth, !border.isFinite || !(0...10).contains(border) { throw DocumentError.invalid("invalid cell border") }
                }
            }
            var colors = TextFormatting(); colors.foreground = table.borderColor; colors.highlight = table.headerBackground
            try validateText(colors)

        }
        for style in document.styles {
            try validateText(style.text)
            try validateParagraph(style.paragraph)
            if let level = style.headingLevel, !(1...9).contains(level) { throw DocumentError.invalid("invalid heading level") }
        }
        try NoteValidation.validate(document)
        let paragraphs = document.paragraphs
        guard Set(paragraphs.compactMap { $0.toc?.tableID }) == tocIDs else { throw DocumentError.invalid("orphaned table of contents definition") }
        guard Set(paragraphs.map(\.id)).count == paragraphs.count else { throw DocumentError.invalid("duplicate paragraph identifiers") }
        guard Set(document.comments.map(\.id)).count == document.comments.count else { throw DocumentError.invalid("duplicate comment identifiers") }
        guard Set(document.bookmarks.map(\.id)).count == document.bookmarks.count else { throw DocumentError.invalid("duplicate bookmark identifiers") }
        let textIndex = DocumentTextIndex(paragraphs: paragraphs)
        for comment in document.comments where comment.isDetached != true {
            guard textIndex.range(for: comment.anchor) != nil else { throw DocumentError.invalid("invalid comment anchor") }
        }
        for p in paragraphs {
            if let toc = p.toc {
                guard tocIDs.contains(toc.tableID), p.tableCell == nil else { throw DocumentError.invalid("missing table of contents definition") }
                if toc.kind == .entry {
                    guard toc.headingID != nil, let level = toc.level, (1...9).contains(level) else { throw DocumentError.invalid("invalid contents entry") }
                } else if toc.headingID != nil || toc.level != nil { throw DocumentError.invalid("invalid contents paragraph") }
            }
            guard document.styles.contains(where: { $0.id == p.styleID }) else { throw DocumentError.invalid("missing paragraph style") }
            guard !p.text.contains("\n"), !p.text.contains("\r") else { throw DocumentError.invalid("paragraph contains a line separator") }
            if let list = p.list, !(0...8).contains(list.level) || !(1...1_000_000).contains(list.start) { throw DocumentError.invalid("invalid list") }
            if let formatting = p.formatting { try validateParagraph(formatting) }
            if let cell = p.tableCell {
                guard let table = document.tables.first(where: { $0.id == cell.tableID }),
                      (0..<table.rows).contains(cell.row), table.columnWidths.indices.contains(cell.column),
                      table.anchor(row: cell.row, column: cell.column) == cell else { throw DocumentError.invalid("invalid table cell reference") }
            }
            for run in p.runs {
                try validateText(run.format)
                if run.noteID != nil {
                    guard run.text == "\u{FFFC}", run.image == nil, run.equation == nil else { throw DocumentError.invalid("invalid note reference") }
                }
                if run.equation != nil {
                    guard run.text == "\u{FFFC}", run.image == nil else { throw DocumentError.invalid("invalid inline equation") }
                }
                if let image = run.image {
                    if let adjustments = image.adjustments {
                        guard adjustments.isValid,
                              abs(image.width / image.height - adjustments.frameAspectRatio) <= max(0.000001, adjustments.frameAspectRatio * 0.000001) else { throw DocumentError.invalid("invalid image adjustments or frame proportions") }
                    }
                    guard run.text == "\u{FFFC}", image.data.count <= 32 * 1024 * 1024,
                          !image.data.isEmpty, ["png", "jpg", "jpeg", "tiff", "heic"].contains(image.fileExtension),
                          image.width.isFinite, image.height.isFinite, (1...4000).contains(image.width), (1...4000).contains(image.height) else { throw DocumentError.invalid("invalid inline image") }
                }
            }
        }
    }
    static func validateText(_ format: TextFormatting) throws {
        if format.clearHighlight == true, format.highlight != nil { throw DocumentError.invalid("conflicting highlight overrides") }
        if let face = format.fontFace, face.isEmpty || face.utf8.count > 512 || face.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            throw DocumentError.invalid("invalid font face")
        }
        if let size = format.fontSize, !size.isFinite || !(1...1000).contains(size) { throw DocumentError.invalid("invalid font size") }
        if let baseline = format.baseline, !(-1...1).contains(baseline) { throw DocumentError.invalid("invalid baseline") }
        for color in [format.foreground, format.highlight].compactMap({ $0 }) {
            guard color.count == 7, color.first == "#", UInt32(color.dropFirst(), radix: 16) != nil else { throw DocumentError.invalid("invalid colour") }
        }
    }
    static func validateParagraph(_ format: ParagraphFormatting) throws {
        try format.lineHeight?.validate()
        guard [format.lineSpacing, format.spaceBefore, format.spaceAfter, format.headIndent, format.tailIndent, format.firstLineIndent]
            .allSatisfy({ $0.isFinite && abs($0) <= 4000 }) else { throw DocumentError.invalid("invalid paragraph geometry") }
    }

}
