import Foundation
import DocumentCore
#if canImport(FoundationXML)
import FoundationXML
#endif

struct DOCXRunningContentPart {
    let kind: String
    let variant: String
    let path: String
    let xml: String
}

enum DOCXRunningContent {
    static func parts(section: Section, index: Int, documentUsesEvenPages: Bool) -> [DOCXRunningContentPart] {
        var parts: [DOCXRunningContentPart] = []
        let variants = section.runningContent ?? RunningContentVariants()
        for isHeader in [true, false] {
            let kind = isHeader ? "header" : "footer", root = isHeader ? "hdr" : "ftr"
            let standard = isHeader ? section.header : section.footer
            let numbering = section.pageNumbering.flatMap { ([.topLeft, .topCenter, .topRight].contains($0.position) == isHeader) ? $0 : nil }
            let values = [("default", standard, index > 0),
                          ("first", isHeader ? variants.firstHeader : variants.firstFooter, variants.differentFirstPage),
                          ("even", documentUsesEvenPages && !variants.differentOddEvenPages ? standard : (isHeader ? variants.evenHeader : variants.evenFooter), documentUsesEvenPages)]
            for (variant, text, required) in values {
                // Preserve dormant text even when the corresponding switch is off.
                let enabled = variant == "default" || (variant == "first" ? variants.differentFirstPage : documentUsesEvenPages)
                guard required || !text.isEmpty || (enabled && numbering != nil) else { continue }
                let suffix = variant == "default" ? "" : "-" + variant
                let path = "\(kind)\(index + 1)\(suffix).xml"
                var content = text.isEmpty ? "" : "<w:p><w:r><w:rPr><w:sz w:val=\"18\"/></w:rPr><w:t xml:space=\"preserve\">\(DOCX.xml(text))</w:t></w:r></w:p>"
                if let numbering { content += pageNumber(numbering) }
                if content.isEmpty { content = "<w:p/>" }
                parts.append(DOCXRunningContentPart(kind: kind, variant: variant, path: path, xml: "<w:\(root) xmlns:w=\"\(DOCX.wordNS)\">\(content)</w:\(root)>"))
            }
        }
        return parts
    }
    private static func pageNumber(_ numbering: PageNumbering) -> String {
        let alignment = [.topCenter, .bottomCenter].contains(numbering.position) ? "center" : [.topRight, .bottomRight].contains(numbering.position) ? "right" : "left"
        var field = "<w:fldSimple w:instr=\"PAGE\"><w:r><w:t>\(numbering.start)</w:t></w:r></w:fldSimple>"
        if numbering.format == .page || numbering.format == .pageOfTotal { field = "<w:r><w:t xml:space=\"preserve\">Page </w:t></w:r>" + field }
        if numbering.format == .pageOfTotal { field += "<w:r><w:t xml:space=\"preserve\"> of </w:t></w:r><w:fldSimple w:instr=\"NUMPAGES\"><w:r><w:t>1</w:t></w:r></w:fldSimple>" }
        return "<w:p><w:pPr><w:jc w:val=\"\(alignment)\"/></w:pPr>\(field)</w:p>"
    }
}

final class DOCXRunningContentSettingsReader: NSObject, XMLParserDelegate {
    var differentOddEvenPages = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if namespaceURI == DOCX.wordNS, name == "evenAndOddHeaders" { differentOddEvenPages = !["0", "false", "off"].contains(wordAttribute(a) ?? "1") }
    }
}
