import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import DocumentCore

/// Resolves concrete num IDs through abstract definitions and per-level overrides.
/// IDs have no inherent meaning: numId=1 is just as capable of being decimal as bullet.
final class DOCXNumberingReader: NSObject, XMLParserDelegate {
    struct Level {
        var kind: ListDescriptor.Kind = .decimal
        var start = 1
        var text: String?
    }
    struct Instance {
        var abstractID = ""
        var levels: [Int: Level] = [:]
        var starts: [Int: Int] = [:]
        var seriesID = UUID()
    }
    private var abstracts: [String: [Int: Level]] = [:]
    private var instances: [String: Instance] = [:]
    private var abstractID: String?, instanceID: String?, levelIndex: Int?, overrideIndex: Int?
    private var level: Level?
    var warnings: Set<String> = []

    func descriptor(id: String, level index: Int) -> ListDescriptor? {
        guard id != "0" else { return nil }
        guard let instance = instances[id], let definition = instance.levels[index] ?? abstracts[instance.abstractID]?[index] else {
            warnings.insert("A missing list definition was replaced with decimal numbering.")
            return ListDescriptor(kind: .decimal, level: index)
        }
        return ListDescriptor(kind: definition.kind, level: index, start: instance.starts[index] ?? definition.start, seriesID: instance.seriesID)
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        guard namespaceURI == DOCX.wordNS else { return }
        func value(_ key: String = "val") -> String? { a["w:\(key)"] ?? a[key] }
        switch name {
        case "abstractNum": abstractID = value("abstractNumId"); if let id = abstractID { abstracts[id] = [:] }
        case "num": instanceID = value("numId"); if let id = instanceID { instances[id] = Instance() }
        case "abstractNumId": if let id = instanceID { instances[id]?.abstractID = value() ?? "" }
        case "lvlOverride": overrideIndex = value("ilvl").flatMap(Int.init)
        case "startOverride": if let id = instanceID, let index = overrideIndex, let start = value().flatMap(Int.init) { instances[id]?.starts[index] = start }
        case "lvl": levelIndex = value("ilvl").flatMap(Int.init); level = Level()
        case "start": if let start = value().flatMap(Int.init) { level?.start = start }
        case "numFmt":
            let formats: [String: ListDescriptor.Kind] = ["bullet": .bullet, "decimal": .decimal, "lowerLetter": .lowerAlpha, "upperLetter": .upperAlpha, "lowerRoman": .lowerRoman, "upperRoman": .upperRoman]
            if let kind = formats[value() ?? ""] { level?.kind = kind }
            else { warnings.insert("An unsupported numbering format was replaced with decimal numbering.") }
        case "lvlText": level?.text = value()
        case "lvlRestart":
            if let index = levelIndex, value().flatMap(Int.init) != index {
                warnings.insert("Custom nested-list restart rules use Scribe's parent-level restart behavior.")
            }
        case "numStyleLink", "styleLink": warnings.insert("Linked numbering styles may require direct list formatting.")
        default: break
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard namespaceURI == DOCX.wordNS else { return }
        switch name {
        case "lvl":
            if let index = levelIndex, let level {
                if level.kind != .bullet, let text = level.text, text != "%\(index + 1)." {
                    warnings.insert("Custom list marker text uses standard number-and-period markers.")
                }
                if let id = instanceID { instances[id]?.levels[index] = level }
                else if let id = abstractID { abstracts[id]?[index] = level }
            }
            levelIndex = nil; level = nil
        case "lvlOverride": overrideIndex = nil
        case "num": instanceID = nil
        case "abstractNum": abstractID = nil
        default: break
        }
    }
}

/// Assigns a concrete numbering instance per series/restart. Starts are derived from the
/// same counter used by the editor, including restarts after legacy contiguous lists.
struct DOCXNumberingWriter {
    private struct Definition {
        var levels: [Int: ListDescriptor] = [:]
    }
    private var definitions: [Definition] = []
    private(set) var paragraphIDs: [UUID: Int] = [:]
    init(paragraphs: [Paragraph]) {
        var counter = ListNumbering(), active: [UUID: Int] = [:], anonymous: Int?
        var exportedCounters: [ListNumbering] = []
        for paragraph in paragraphs {
            let number = counter.number(for: paragraph.list)
            guard var list = paragraph.list, let number else { anonymous = nil; continue }
            if list.seriesID != nil { anonymous = nil }
            var index = list.seriesID.flatMap { active[$0] } ?? (list.seriesID == nil ? anonymous : nil)
            if list.restart == true { index = nil }
            if let existing = index, let level = definitions[existing].levels[list.level], level.kind != list.kind { index = nil }
            // A level's start can change after an ancestor resumes. Split the concrete
            // instance if a fixed OOXML definition would generate a different number.
            if let existing = index {
                var trial = exportedCounters[existing], expected = list
                expected.seriesID = nil; expected.restart = nil
                expected.start = definitions[existing].levels[list.level]?.start ?? number
                if trial.number(for: expected) != number { index = nil }
            }
            if index == nil { index = definitions.count; definitions.append(Definition()); exportedCounters.append(ListNumbering()) }
            let resolved = index!
            if definitions[resolved].levels[list.level] == nil {
                list.start = number; definitions[resolved].levels[list.level] = list
            }
            var exported = list; exported.seriesID = nil; exported.restart = nil
            exported.start = definitions[resolved].levels[list.level]!.start
            _ = exportedCounters[resolved].number(for: exported)
            if let id = list.seriesID { active[id] = resolved } else { anonymous = resolved }
            paragraphIDs[paragraph.id] = resolved + 1
        }
    }
    var xml: String {
        let abstract = definitions.enumerated().map { index, definition in
            let levels = (0...8).map { level -> String in
                let list = definition.levels[level] ?? ListDescriptor(kind: .decimal, level: level)
                let format: String
                switch list.kind {
                case .bullet: format = "bullet"
                case .decimal: format = "decimal"
                case .lowerAlpha: format = "lowerLetter"
                case .upperAlpha: format = "upperLetter"
                case .lowerRoman: format = "lowerRoman"
                case .upperRoman: format = "upperRoman"
                }
                return "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"\(list.start)\"/><w:numFmt w:val=\"\(format)\"/><w:lvlText w:val=\"\(list.kind == .bullet ? "•" : "%\(level + 1).")\"/><w:pPr><w:ind w:left=\"\((level + 1) * 480)\" w:hanging=\"240\"/></w:pPr></w:lvl>"
            }.joined()
            return "<w:abstractNum w:abstractNumId=\"\(index + 1)\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(levels)</w:abstractNum>"
        }.joined()
        // The schema requires abstract definitions before concrete instances.
        let concrete = definitions.indices.map { index in
            "<w:num w:numId=\"\(index + 1)\"><w:abstractNumId w:val=\"\(index + 1)\"/></w:num>"
        }.joined()
        return "<w:numbering xmlns:w=\"\(DOCX.wordNS)\">\(abstract)\(concrete)</w:numbering>"
    }
}
