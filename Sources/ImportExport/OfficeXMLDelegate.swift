import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// XML prefixes are aliases, not format identifiers. Normalize known attribute namespaces
/// before forwarding to the focused Office readers; element namespace URIs remain unchanged.
final class OfficeXMLDelegate: NSObject, XMLParserDelegate {
    private let receiver: XMLParserDelegate
    private var bindings: [String: [String]] = [:]
    private let aliases = [
        DOCX.wordNS: "w", DOCX.relationNS: "r",
        "http://schemas.microsoft.com/office/word/2010/wordml": "w14",
        "http://schemas.microsoft.com/office/word/2012/wordml": "w15"
    ]
    init(receiver: XMLParserDelegate) { self.receiver = receiver }
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) { bindings[prefix, default: []].append(namespaceURI) }
    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) { _ = bindings[prefix]?.popLast() }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes attributes: [String: String]) {
        var normalized: [String: String] = [:]
        for (key, value) in attributes {
            let parts = key.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let prefix = String(parts[0]), local = String(parts[1])
                if let uri = bindings[prefix]?.last, let alias = aliases[uri] { normalized[alias + ":" + local] = value }
                else if !aliases.values.contains(prefix) { normalized[key] = value }
                // A familiar prefix bound to a different URI must not masquerade as Office XML.
            } else { normalized[key] = value }
        }
        #if canImport(ObjectiveC)
        receiver.parser?(parser, didStartElement: name, namespaceURI: namespaceURI, qualifiedName: qualifiedName, attributes: normalized)
        #else
        receiver.parser(parser, didStartElement: name, namespaceURI: namespaceURI, qualifiedName: qualifiedName, attributes: normalized)
        #endif
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        #if canImport(ObjectiveC)
        receiver.parser?(parser, didEndElement: name, namespaceURI: namespaceURI, qualifiedName: qualifiedName)
        #else
        receiver.parser(parser, didEndElement: name, namespaceURI: namespaceURI, qualifiedName: qualifiedName)
        #endif
    }
    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { parser.abortParsing(); return }
        self.parser(parser, foundCharacters: text)
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) {
        #if canImport(ObjectiveC)
        receiver.parser?(parser, foundCharacters: text)
        #else
        receiver.parser(parser, foundCharacters: text)
        #endif
    }
}
