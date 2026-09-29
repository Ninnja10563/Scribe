import Foundation
import DocumentCore
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A bounded subtree reader keeps Office Math's runs separate from Word text runs.
final class DOCXEquationReader {
    private final class Node {
        let name: String
        let attributes: [String: String]
        var children: [Node] = []
        var text = ""
        init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
        func child(_ name: String) -> Node? { children.first { $0.name == name } }
        var value: String? { attributes["m:val"] }
        var fallback: String { ([name == "m:t" ? text : ""] + children.map(\.fallback)).filter { !$0.isEmpty }.joined(separator: " ") }
    }
    private var stack: [Node] = []
    private var count = 0, textBytes = 0
    private var size: Double?
    var defaultSize: Double = 12
    private var approximatedFormatting = false
    var active: Bool { !stack.isEmpty }
    func start(_ name: String, namespace: String?, attributes: [String: String], parser: XMLParser) {
        if stack.isEmpty { count = 0; textBytes = 0; size = nil; approximatedFormatting = false }
        count += 1
        guard count <= 4096, stack.count < 64 else { parser.abortParsing(); return }
        let prefix = namespace == DOCXEquations.namespace ? "m:" : namespace == DOCX.wordNS ? "w:" : "unknown:"
        let node = Node(prefix + name, attributes)
        stack.last?.children.append(node); stack.append(node)
        if node.name == "w:sz", size == nil { size = attributes["w:val"].flatMap(Double.init).map { $0 / 2 } }
        if node.name == "m:sty", ["b", "bi"].contains(node.value ?? "") { approximatedFormatting = true }
        if ["w:b", "w:color", "w:highlight", "w:shd"].contains(node.name) { approximatedFormatting = true }
    }
    func characters(_ value: String, parser: XMLParser) {
        textBytes += value.utf8.count
        guard textBytes <= 32768 else { parser.abortParsing(); return }
        if stack.last?.name == "m:t" { stack.last?.text += value }
    }
    func end() -> (run: TextRun, warning: String?)? {
        guard let node = stack.popLast(), stack.isEmpty else { return nil }
        do {
            let markup = try source(node)
            let equation = try Equation(source: markup, pointSize: min(144, max(8, size ?? defaultSize)))
            var run = TextRun("\u{FFFC}"); run.equation = equation
            return (run, approximatedFormatting ? "Equation color, highlighting and bold styling are approximated by Scribe’s current monochrome math renderer." : nil)
        } catch {
            let fallback = node.fallback
            return (TextRun(fallback.isEmpty ? "[Unsupported equation]" : "[Equation: \(fallback)]"), "An unsupported equation was retained as readable text; its mathematical layout could not be imported.")
        }
    }
    private func source(_ node: Node) throws -> String {
        func argument(_ name: String) throws -> String {
            guard let child = node.child("m:" + name) else { throw DocumentError.invalid("missing equation argument") }
            return try source(child)
        }
        func children() throws -> String { try node.children.map(source).joined() }
        func literal(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "{", with: "\\{").replacingOccurrences(of: "}", with: "\\}")
        }
        let allowed: [String: Set<String>] = [
            "m:f": ["m:fPr", "m:num", "m:den"], "m:rad": ["m:radPr", "m:deg", "m:e"],
            "m:sSub": ["m:sSubPr", "m:e", "m:sub"], "m:sSup": ["m:sSupPr", "m:e", "m:sup"],
            "m:sSubSup": ["m:sSubSupPr", "m:e", "m:sub", "m:sup"],
            "m:nary": ["m:naryPr", "m:sub", "m:sup", "m:e"], "m:d": ["m:dPr", "m:e"], "m:box": ["m:boxPr", "m:e"],
            "m:limLow": ["m:limLowPr", "m:e", "m:lim"], "m:limUpp": ["m:limUppPr", "m:e", "m:lim"]
        ]
        if let names = allowed[node.name], !node.children.allSatisfy({ names.contains($0.name) }) {
            throw DocumentError.invalid("unsupported equation content")
        }
        switch node.name {
        case "m:argPr":
            guard node.children.isEmpty else { throw DocumentError.invalid("unsupported math argument properties") }
            return ""
        case "m:oMath", "m:e", "m:num", "m:den", "m:deg", "m:sub", "m:sup", "m:lim": return try children()
        case "m:r":
            let value = node.children.filter { $0.name == "m:t" }.map(\.text).joined()
            let properties = node.child("m:rPr")
            let normal = properties?.child("m:nor")
            let upright = properties?.child("m:sty")?.value == "p" || (normal != nil && !["0", "false", "off"].contains(normal?.value ?? "1"))
            guard node.children.allSatisfy({ ["m:t", "m:rPr", "w:rPr"].contains($0.name) }) else { throw DocumentError.invalid("unsupported math run") }
            if value.isEmpty { return "" }
            if ["∑", "∏", "∫"].contains(value) { return value }
            if upright || value.contains(where: { "\\{}_^".contains($0) }) { return "\\text{\(literal(value))}" }
            return value
        case "m:f":
            if let kind = node.child("m:fPr")?.child("m:type")?.value, kind != "bar" { throw DocumentError.invalid("unsupported fraction") }
            return try "\\frac{\(argument("num"))}{\(argument("den"))}"
        case "m:rad":
            let degree = try argument("deg"), body = try argument("e")
            let hidden = node.child("m:radPr")?.child("m:degHide")?.value
            return "\\sqrt\(hidden == "1" || hidden == "true" || degree.isEmpty ? "" : "[" + degree + "]"){\(body)}"
        case "m:sSub", "m:sSup", "m:sSubSup":
            var result = try "{\(argument("e"))}"
            if node.name != "m:sSup" { result += try "_{\(argument("sub"))}" }
            if node.name != "m:sSub" { result += try "^{\(argument("sup"))}" }
            return result
        case "m:limLow", "m:limUpp":
            let base = try argument("e"), limit = try argument("lim")
            let parsed = try MathParser.parse(base)
            switch parsed {
            case .largeOperator, .scripts(.largeOperator, _, _): break
            default: throw DocumentError.invalid("unsupported limit layout")
            }
            return base + (node.name == "m:limLow" ? "_{" : "^{") + limit + "}"
        case "m:nary":
            let properties = node.child("m:naryPr")
            let symbol = properties?.child("m:chr")?.value ?? "∫"
            guard ["∑", "∏", "∫"].contains(symbol) else { throw DocumentError.invalid("unsupported n-ary operator") }
            var result = symbol
            let lower = try argument("sub"), upper = try argument("sup")
            if !["1", "true", "on"].contains(properties?.child("m:subHide")?.value ?? "0"), !lower.isEmpty { result += "_{\(lower)}" }
            if !["1", "true", "on"].contains(properties?.child("m:supHide")?.value ?? "0"), !upper.isEmpty { result += "^{\(upper)}" }
            result += try argument("e")
            return result
        case "m:d":
            let properties = node.child("m:dPr")
            let left = properties?.child("m:begChr")?.value ?? "(", right = properties?.child("m:endChr")?.value ?? ")"
            guard node.children.filter({ $0.name == "m:e" }).count == 1,
                  ["", "(", ")", "[", "]", "{", "}", "|"].contains(left), ["", "(", ")", "[", "]", "{", "}", "|"].contains(right) else { throw DocumentError.invalid("unsupported equation delimiter") }
            return try "\\left\(left.isEmpty ? "." : left)\(argument("e"))\\right\(right.isEmpty ? "." : right)"
        case "m:box": return try argument("e")
        default: throw DocumentError.invalid("unsupported Office Math construct")
        }
    }
}
