import Foundation

public struct ScribeDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var formatVersion = currentVersion
    public var id = UUID()
    public var title = "Untitled"
    public var author = ""
    public var language = "en-AU"
    public var sections = [Section()]
    public var styles = ParagraphStyle.defaults
    public var comments: [Comment] = []
    public var bookmarks: [Bookmark] = []
    public init() {}
    public var paragraphs: [Paragraph] { sections.flatMap(\.paragraphs) }
    public var plainText: String { paragraphs.map(\.text).joined(separator: "\n") }
    public var outline: [OutlineEntry] {
        paragraphs.compactMap { p in
            guard let level = styles.first(where: { $0.id == p.styleID })?.headingLevel else { return nil }
            return OutlineEntry(id: p.id, title: p.text, level: level)
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
    public init() {}
}

public struct Paragraph: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var styleID = "normal"
    public var runs: [TextRun]
    public var formatting: ParagraphFormatting?
    public var list: ListDescriptor?
    public var pageBreakBefore = false
    public init(_ text: String = "", style: String = "normal") {
        runs = [TextRun(text)]; styleID = style
    }
    public var text: String { runs.map(\.text).joined() }
}

public struct TextRun: Codable, Equatable, Sendable {
    public var text: String
    public var format: TextFormatting
    public var link: String?
    public init(_ text: String, format: TextFormatting = TextFormatting(), link: String? = nil) {
        self.text = text; self.format = format; self.link = link
    }
}

/// Nil properties inherit from the paragraph's named style.
public struct TextFormatting: Codable, Equatable, Sendable {
    public var fontFamily: String?
    public var fontSize: Double?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    public var baseline: Int?
    public var foreground: String?
    public var highlight: String?
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
    public enum Kind: String, Codable, Sendable { case bullet, decimal, lowerAlpha, lowerRoman }
    public var kind: Kind
    public var level: Int
    public var start: Int
    public init(kind: Kind = .bullet, level: Int = 0, start: Int = 1) {
        self.kind = kind; self.level = level; self.start = start
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
