import Foundation

public struct ScribeDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 11
    public var formatVersion = currentVersion
    public var id = UUID()
    public var title = "Untitled"
    public var author = ""
    public var language = "en-AU"
    public var sections = [Section()]
    public var styles = ParagraphStyle.defaults
    public var comments: [Comment] = []
    public var bookmarks: [Bookmark] = []
    public var tables: [DocumentTable] = []
    public var tablesOfContents: [DocumentTOC] = []
    public init() {}
    public var paragraphs: [Paragraph] { sections.flatMap(\.paragraphs) }
    public var plainText: String {
        var result = "", previous: TableCellReference?
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 {
                let sameRow = paragraph.tableCell != nil && previous?.tableID == paragraph.tableCell?.tableID && previous?.row == paragraph.tableCell?.row && previous?.column != paragraph.tableCell?.column
                result += sameRow ? "\t" : "\n"
            }
            result += paragraph.runs.map { $0.image.map { $0.altText.isEmpty ? "[Image]" : "[Image: \($0.altText)]" } ?? $0.text }.joined()
            previous = paragraph.tableCell
        }
        return result
    }
    public var outline: [OutlineEntry] {
        var numbering = ListNumbering()
        return paragraphs.compactMap { p in
            let marker = numbering.marker(for: p.list)
            guard p.toc == nil, let level = styles.first(where: { $0.id == p.styleID })?.headingLevel else { return nil }
            let title = p.runs.map { $0.image?.altText ?? $0.text }.joined()
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\u{2028}", with: " ")
                .replacingOccurrences(of: "\u{c}", with: " ")
            return OutlineEntry(id: p.id, title: (marker.map { $0 + " " } ?? "") + title, level: level)
        }
    }
    public func style(for paragraph: Paragraph) -> ParagraphStyle {
        styles.first { $0.id == paragraph.styleID } ?? .normal
    }
}

public struct Section: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var page = PageSettings()
    public var paragraphs = [Paragraph()]
    public var header = ""
    public var footer = ""
    public var pageNumbering: PageNumbering?
    public var runningContent: RunningContentVariants?
    public init() {}
}

public struct Paragraph: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var styleID = "normal"
    public var runs: [TextRun]
    public var formatting: ParagraphFormatting?
    public var list: ListDescriptor?
    public var pageBreakBefore = false
    public var tableCell: TableCellReference?
    public var toc: TOCParagraph?
    public init(_ text: String = "", style: String = "normal") {
        runs = [TextRun(text)]; styleID = style
    }
    public var text: String { runs.map(\.text).joined() }
}

public struct TextRun: Codable, Equatable, Sendable {
    /// Text flow uses U+2028 for a soft line break and U+000C for an inline page break.
    public var text: String
    public var format: TextFormatting
    public var link: String?
    public var image: InlineImage?
    public init(_ text: String, format: TextFormatting = TextFormatting(), link: String? = nil) {
        self.text = text; self.format = format; self.link = link
    }
}

/// Nil properties inherit from the paragraph's named style.
public struct TextFormatting: Codable, Equatable, Sendable {
    public var fontFamily: String?
    /// Optional PostScript face preserves weights/widths beyond bold and italic.
    public var fontFace: String?
    public var fontSize: Double?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    public var baseline: Int?
    public var foreground: String?
    public var highlight: String?
    /// Explicitly remove a highlight inherited from the paragraph style.
    public var clearHighlight: Bool?
    public init() {}
}

public enum Alignment: String, Codable, Sendable, CaseIterable { case left, center, right, justified }
public struct ParagraphFormatting: Codable, Equatable, Sendable {
    public var alignment = Alignment.left
    public var lineSpacing = 3.0
    public var spaceBefore = 0.0
    public var spaceAfter = 8.0
    public var firstLineIndent = 0.0
    public var headIndent = 0.0
    public var tailIndent = 0.0
    public init() {}
}
public struct ListDescriptor: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case bullet, decimal, lowerAlpha, lowerRoman, upperAlpha, upperRoman }
    public var kind: Kind
    public var level: Int
    public var start: Int
    /// A series continues across intervening body text. Nil preserves legacy contiguous lists.
    public var seriesID: UUID?
    /// Explicit restart at this paragraph; nil/false continues the current series.
    public var restart: Bool?
    public init(kind: Kind = .bullet, level: Int = 0, start: Int = 1, seriesID: UUID? = nil, restart: Bool? = nil) {
        self.kind = kind; self.level = level; self.start = start
        self.seriesID = seriesID; self.restart = restart
    }
}
public struct OutlineEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let level: Int
}
public struct TextAnchor: Codable, Equatable, Sendable {
    public var paragraphID: UUID
    public var offset: Int
    public var length: Int
    /// Multi-paragraph ranges use an explicit end; legacy single-paragraph anchors use length.
    public var endParagraphID: UUID?
    public var endOffset: Int?
    public init(paragraphID: UUID, offset: Int, length: Int) {
        self.paragraphID = paragraphID; self.offset = offset; self.length = length
    }
}
public struct Comment: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var anchor: TextAnchor
    public var text: String
    public var author: String
    public var resolved = false
    /// Keep the comment if its associated text is removed; native undo can reattach it.
    public var isDetached: Bool?
    public init(anchor: TextAnchor, text: String, author: String) {
        self.anchor = anchor; self.text = text; self.author = author
    }
}
public struct Bookmark: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var name: String
    public var anchor: TextAnchor
    public init(name: String, anchor: TextAnchor) { self.name = name; self.anchor = anchor }
}
