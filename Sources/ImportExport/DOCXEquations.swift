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
        case .row(let values): return values.map { expression($0, size: size) }.joined()
        case .token(let text, let italic):
            return "<m:r><m:rPr><m:sty m:val=\"\(italic ? "i" : "p")\"/></m:rPr><w:rPr><w:sz w:val=\"\(Int((size * 2).rounded()))\"/></w:rPr><m:t xml:space=\"preserve\">\(DOCX.xml(text))</m:t></m:r>"
        case .space(let em): return expression(.token(String(repeating: " ", count: max(1, Int((em * 3).rounded()))), italic: false), size: size)
        case .largeOperator(let symbol): return expression(.token(symbol, italic: false), size: size)
        case .fraction(let numerator, let denominator):
            return "<m:f><m:fPr>\(control)</m:fPr>\(child("num", numerator))\(child("den", denominator))</m:f>"
        case .radical(let radicand, let degree):
            return "<m:rad><m:radPr><m:degHide m:val=\"\(degree == nil ? "1" : "0")\"/>\(control)</m:radPr>\(child("deg", degree))\(child("e", radicand))</m:rad>"
        case .scripts(let base, let lower, let upper):
            if case .largeOperator(let symbol) = base {
                return "<m:nary><m:naryPr><m:chr m:val=\"\(symbol)\"/><m:limLoc m:val=\"\(symbol == "∫" ? "subSup" : "undOvr")\"/><m:subHide m:val=\"\(lower == nil ? "1" : "0")\"/><m:supHide m:val=\"\(upper == nil ? "1" : "0")\"/>\(control)</m:naryPr>\(child("sub", lower))\(child("sup", upper))<m:e/></m:nary>"
            }
            let tag = lower != nil && upper != nil ? "sSubSup" : lower != nil ? "sSub" : "sSup"
            return "<m:\(tag)><m:\(tag)Pr>\(control)</m:\(tag)Pr>\(child("e", base))\(lower.map { child("sub", $0) } ?? "")\(upper.map { child("sup", $0) } ?? "")</m:\(tag)>"
        case .delimited(let left, let body, let right):
            return "<m:d><m:dPr><m:begChr m:val=\"\(DOCX.xml(left))\"/><m:endChr m:val=\"\(DOCX.xml(right))\"/><m:grow m:val=\"1\"/>\(control)</m:dPr>\(child("e", body))</m:d>"
        }
    }
}
