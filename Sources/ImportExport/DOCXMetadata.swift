import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import DocumentCore

enum DOCXMetadata {
    static let relationship = "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"
    static let contentType = "application/vnd.openxmlformats-package.core-properties+xml"
    static func xml(_ document: ScribeDocument) throws -> String {
        try DocumentMetadata.validateText(document.title); try DocumentMetadata.validateText(document.author)
        let language = try DocumentMetadata.languageIdentifier(document.language)
        return "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>\(DOCX.xml(document.title))</dc:title><dc:creator>\(DOCX.xml(document.author))</dc:creator><dc:language>\(DOCX.xml(language))</dc:language></cp:coreProperties>"
    }
}

final class DOCXMetadataReader: NSObject, XMLParserDelegate {
    var title: String?, author: String?, language: String?
    private var field: String?, text = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if namespaceURI == "http://purl.org/dc/elements/1.1/", ["title", "creator", "language"].contains(name) { field = name; text = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if field != nil { text += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if field != nil { text += String(decoding: CDATABlock, as: UTF8.self) } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard field == name, namespaceURI == "http://purl.org/dc/elements/1.1/" else { return }
        switch name { case "title": title = text; case "creator": author = text; case "language": language = text; default: break }
        field = nil
    }
}
