import Foundation
import DocumentCore

/// Office Math objects, rather than screenshots or renamed formula source.
enum DOCXEquations {
    static let namespace = "http://schemas.openxmlformats.org/officeDocument/2006/math"
    static func xml(_ equation: Equation) -> String {
        "<m:oMath xmlns:m=\"\(namespace)\">\(expression(equation.expression, size: equation.pointSize))</m:oMath>"
    }
    private static func expression(_ value: MathExpression, size: Double) -> String {
        func child(_ name: String, _ value: MathExpression?) -> String {
            "<m:\(name)>\(value.map { expression($0, size: size) } ?? "")</m:\(name)>"
        }
        let control = "<m:ctrlPr><w:rPr><w:sz w:val=\"\(Int((size * 2).rounded()))\"/></w:rPr></m:ctrlPr>"
        switch value {
        case .row(let values):
            var result = "", index = 0
            while index < values.count {
                if let op = operatorParts(values[index]) {
                    var end = index + 1
                    while end < values.count, !isRelation(values[end]), operatorParts(values[end]) == nil { end += 1 }
                    if end > index + 1 {
                        result += nary(symbol: op.0, lower: op.1, upper: op.2, operand: .row(Array(values[(index + 1)..<end])), size: size)
                        index = end; continue
                    }
                }
                result += expression(values[index], size: size); index += 1
            }
            return result
        case .token(let text, let italic):
            let functions = ["sin", "cos", "tan", "log", "ln", "exp", "lim"]
            return textRun(text, italic: italic, normal: !italic && text.contains(where: \.isLetter) && !functions.contains(text), size: size)
        case .space(let em): return expression(.token(String(repeating: " ", count: max(1, Int((em * 3).rounded()))), italic: false), size: size)
        case .largeOperator(let symbol): return textRun(symbol, italic: false, normal: true, size: size)
        case .fraction(let numerator, let denominator):
            return "<m:f><m:fPr>\(control)</m:fPr>\(child("num", numerator))\(child("den", denominator))</m:f>"
        case .radical(let radicand, let degree):
            return "<m:rad><m:radPr><m:degHide m:val=\"\(degree == nil ? "1" : "0")\"/>\(control)</m:radPr>\(child("deg", degree))\(child("e", radicand))</m:rad>"
        case .scripts(let base, let lower, let upper):
            if case .largeOperator(let symbol) = base, symbol != "∫" {
                var result = expression(base, size: size)
                if let lower { result = "<m:limLow><m:limLowPr>\(control)</m:limLowPr><m:e>\(result)</m:e>\(child("lim", lower))</m:limLow>" }
                if let upper { result = "<m:limUpp><m:limUppPr>\(control)</m:limUppPr><m:e>\(result)</m:e>\(child("lim", upper))</m:limUpp>" }
                return result
            }
            let tag = lower != nil && upper != nil ? "sSubSup" : lower != nil ? "sSub" : "sSup"
            return "<m:\(tag)><m:\(tag)Pr>\(control)</m:\(tag)Pr>\(child("e", base))\(lower.map { child("sub", $0) } ?? "")\(upper.map { child("sup", $0) } ?? "")</m:\(tag)>"
        case .delimited(let left, let body, let right):
            return "<m:d><m:dPr><m:begChr m:val=\"\(DOCX.xml(left))\"/><m:endChr m:val=\"\(DOCX.xml(right))\"/><m:grow m:val=\"1\"/>\(control)</m:dPr>\(child("e", body))</m:d>"
        }
    }
    private static func textRun(_ text: String, italic: Bool, normal: Bool, size: Double) -> String {
        let properties = normal ? "<m:nor m:val=\"1\"/>" : "<m:sty m:val=\"\(italic ? "i" : "p")\"/>"
        return "<m:r><m:rPr>\(properties)</m:rPr><w:rPr><w:sz w:val=\"\(Int((size * 2).rounded()))\"/></w:rPr><m:t xml:space=\"preserve\">\(DOCX.xml(text))</m:t></m:r>"
    }
    private static func operatorParts(_ value: MathExpression) -> (String, MathExpression?, MathExpression?)? {
        if case .largeOperator(let symbol) = value { return (symbol, nil, nil) }
        if case .scripts(.largeOperator(let symbol), let lower, let upper) = value { return (symbol, lower, upper) }
        return nil
    }
    private static func isRelation(_ value: MathExpression) -> Bool {
        if case .token(let text, _) = value { return ["=", "<", ">", "≤", "≥", "≠", "≈", "≡", "→"].contains(text) }
        return false
    }
    private static func nary(symbol: String, lower: MathExpression?, upper: MathExpression?, operand: MathExpression, size: Double) -> String {
        let limits = symbol == "∫" ? "subSup" : "undOvr"
        let control = "<m:ctrlPr><w:rPr><w:sz w:val=\"\(Int((size * 2).rounded()))\"/></w:rPr></m:ctrlPr>"
        let properties = "<m:naryPr><m:chr m:val=\"\(symbol)\"/><m:limLoc m:val=\"\(limits)\"/><m:subHide m:val=\"\(lower == nil ? "1" : "0")\"/><m:supHide m:val=\"\(upper == nil ? "1" : "0")\"/>\(control)</m:naryPr>"
        return "<m:nary>\(properties)<m:sub>\(lower.map { expression($0, size: size) } ?? "")</m:sub><m:sup>\(upper.map { expression($0, size: size) } ?? "")</m:sup><m:e>\(expression(operand, size: size))</m:e></m:nary>"
    }

}
