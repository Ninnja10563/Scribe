import Foundation

public struct ParagraphStyle: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var headingLevel: Int?
    public var text: TextFormatting
    public var paragraph: ParagraphFormatting
    public var isBuiltIn: Bool
    public init(id: String, name: String, size: Double = 12, bold: Bool = false,
                headingLevel: Int? = nil, isBuiltIn: Bool = false) {
        self.id = id; self.name = name; self.headingLevel = headingLevel
        self.isBuiltIn = isBuiltIn
        text = TextFormatting(); text.fontFamily = "Helvetica Neue"; text.fontSize = size
        text.bold = bold; paragraph = ParagraphFormatting()
    }
    public static let normal = ParagraphStyle(id: "normal", name: "Normal", isBuiltIn: true)
    public static var defaults: [ParagraphStyle] {
        var styles = [normal,
            ParagraphStyle(id: "title", name: "Title", size: 32, bold: true, isBuiltIn: true),
            ParagraphStyle(id: "subtitle", name: "Subtitle", size: 16, isBuiltIn: true),
            ParagraphStyle(id: "heading1", name: "Heading 1", size: 22, bold: true, headingLevel: 1, isBuiltIn: true),
            ParagraphStyle(id: "heading2", name: "Heading 2", size: 17, bold: true, headingLevel: 2, isBuiltIn: true),
            ParagraphStyle(id: "heading3", name: "Heading 3", size: 14, bold: true, headingLevel: 3, isBuiltIn: true),
            ParagraphStyle(id: "quote", name: "Quote", isBuiltIn: true),
            ParagraphStyle(id: "caption", name: "Caption", size: 10, isBuiltIn: true)]
        for index in 3...5 { styles[index].paragraph.spaceBefore = 16; styles[index].paragraph.spaceAfter = 6 }
        styles[6].text.italic = true; styles[6].paragraph.headIndent = 24
        styles[6].paragraph.tailIndent = 24
        return styles
    }
}

public extension ScribeDocument {
    mutating func updateStyle(_ style: ParagraphStyle) {
        if let index = styles.firstIndex(where: { $0.id == style.id }) { styles[index] = style }
        else { styles.append(style) }
    }
    mutating func deleteStyle(id: String) {
        guard let style = styles.first(where: { $0.id == id }), !style.isBuiltIn else { return }
        styles.removeAll { $0.id == id }
        for note in notes.indices {
            for paragraph in notes[note].paragraphs.indices where notes[note].paragraphs[paragraph].styleID == id {
                notes[note].paragraphs[paragraph].styleID = "normal"
            }
        }
        for s in sections.indices {
            for p in sections[s].paragraphs.indices where sections[s].paragraphs[p].styleID == id {
                sections[s].paragraphs[p].styleID = "normal"
            }
        }
    }
}
