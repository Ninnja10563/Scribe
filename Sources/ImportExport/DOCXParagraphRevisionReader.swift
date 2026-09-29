import Foundation
import DocumentCore

/// Previous properties are a complete snapshot, not a patch over current pPr.
final class DOCXParagraphRevisionReader {
    private(set) var depth = 0
    private var identity: RevisionIdentity?
    private var properties: [(String, [String: String])] = []
    private var sawProperties = false
    private var unsupportedCurrent = false
    func reset() { depth = 0; identity = nil; properties = []; sawProperties = false; unsupportedCurrent = false }
    func markUnsupportedCurrent() { unsupportedCurrent = true }
    func observeCurrent(_ name: String, namespace: String?, attributes: [String: String]) {
        guard namespace == DOCX.wordNS, ["pStyle", "pageBreakBefore", "spacing", "ind", "jc", "rPr", "pPrChange"].contains(name) else { unsupportedCurrent = true; return }
        if !["rPr", "pPrChange"].contains(name), !supportedAttributes(name, attributes) { unsupportedCurrent = true }
    }
    private func supportedAttributes(_ name: String, _ attributes: [String: String]) -> Bool {
        let allowed: Set<String>
        switch name {
        case "spacing": allowed = ["before", "after", "line", "lineRule"]
        case "ind": allowed = ["left", "right", "start", "end", "firstLine", "hanging"]
        default: allowed = ["val"]
        }
        guard attributes.keys.allSatisfy({ allowed.contains($0.hasPrefix("w:") ? String($0.dropFirst(2)) : $0) }) else { return false }
        if name == "jc", let value = wordAttribute(attributes), !["left", "center", "right", "both"].contains(value) { return false }
        if name == "pageBreakBefore", let value = wordAttribute(attributes), !["0", "1", "false", "true", "on", "off"].contains(value) { return false }
        if name == "spacing" || name == "ind" {
            for key in allowed where key != "lineRule" {
                if let raw = wordAttribute(attributes, key), Double(raw)?.isFinite != true { return false }
            }
        }
        return true
    }
    func begin(_ identity: RevisionIdentity) throws {
        guard self.identity == nil else { throw DocumentError.invalid("Duplicate paragraph formatting revision.") }
        self.identity = identity; depth = 1
    }
    func start(_ name: String, namespace: String?, attributes: [String: String]) throws {
        guard namespace == DOCX.wordNS else { throw DocumentError.invalid("Unsupported paragraph formatting history namespace.") }
        if depth == 1 {
            guard name == "pPr", !sawProperties else { throw DocumentError.invalid("Invalid previous paragraph properties.") }
            sawProperties = true
        } else {
            guard depth == 2, ["pStyle", "pageBreakBefore", "spacing", "ind", "jc"].contains(name), !properties.contains(where: { $0.0 == name }) else {
                throw DocumentError.invalid("Unsupported previous paragraph property.")
            }
            guard supportedAttributes(name, attributes) else { throw DocumentError.invalid("Unsupported previous paragraph property attribute.") }
            properties.append((name, attributes))
        }
        depth += 1
    }
    func end() throws {
        depth -= 1
        if depth == 0, !sawProperties { throw DocumentError.invalid("Missing previous paragraph properties.") }
    }
    func apply(to paragraph: inout Paragraph, document: ScribeDocument, defaultStyleID: String, styleLists: [String: StyleList]) throws {
        guard let identity else { return }
        guard !unsupportedCurrent else { throw DocumentError.invalid("Unsupported current paragraph properties in revision history.") }
        let styleID = properties.first(where: { $0.0 == "pStyle" }).flatMap { wordAttribute($0.1) } ?? defaultStyleID
        guard paragraph.list == nil, styleLists[styleID]?.id == nil else { throw DocumentError.invalid("Preserving list paragraph formatting history is not yet supported.") }
        var previous = paragraph
        previous.styleID = styleID; previous.formatting = nil; previous.pageBreakBefore = false
        let inheritedBefore = document.style(for: previous).paragraph
        for (name, attributes) in properties {
            if name == "pageBreakBefore" { previous.pageBreakBefore = !["0", "false", "off"].contains(wordAttribute(attributes) ?? "1") }
            if ["spacing", "ind", "jc"].contains(name) {
                var format = previous.formatting ?? inheritedBefore
                try applyParagraph(name, attributes, &format); previous.formatting = format
            }
        }
        guard ParagraphRevisionState(previous) != ParagraphRevisionState(paragraph) else {
            throw DocumentError.invalid("An empty paragraph formatting revision cannot be preserved.")
        }
        try paragraph.recordFormattingChange(from: previous, identity: identity, inheritedBefore: inheritedBefore, inheritedAfter: document.style(for: paragraph).paragraph)
    }
}
