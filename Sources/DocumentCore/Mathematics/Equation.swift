import Foundation

/// A parsed mathematical object. Native serialization stores bounded mathematical
/// markup, never executable TeX or a recursive untrusted object archive.
public struct Equation: Codable, Equatable, Sendable {
    public let source: String
    public let expression: MathExpression
    public let pointSize: Double
    public init(source: String, pointSize: Double = 18) throws {
        guard pointSize.isFinite, (8...144).contains(pointSize) else { throw DocumentError.invalid("equation size must be between 8 and 144 points") }
        self.source = source; self.pointSize = pointSize
        expression = try MathParser.parse(source)
    }
    private enum CodingKeys: String, CodingKey { case source, pointSize }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(source: values.decode(String.self, forKey: .source), pointSize: values.decode(Double.self, forKey: .pointSize))
    }
    public func encode(to encoder: Encoder) throws {
        guard pointSize.isFinite, (8...144).contains(pointSize) else { throw DocumentError.invalid("invalid equation size") }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(source, forKey: .source); try values.encode(pointSize, forKey: .pointSize)
    }
}

public indirect enum MathExpression: Equatable, Sendable {
    case row([MathExpression])
    case token(String, italic: Bool)
    case largeOperator(String)
    case fraction(numerator: MathExpression, denominator: MathExpression)
    case radical(radicand: MathExpression, degree: MathExpression?)
    case scripts(base: MathExpression, lower: MathExpression?, upper: MathExpression?)
    case delimited(left: String, body: MathExpression, right: String)
    case space(Double)
}

extension MathExpression {
    var hasVisibleContent: Bool {
        switch self {
        case .row(let values): return values.contains { $0.hasVisibleContent }
        case .token(let text, _): return text.contains { !$0.isWhitespace }
        case .space: return false
        case .largeOperator, .fraction, .radical: return true
        case .scripts(let base, let lower, let upper): return base.hasVisibleContent || lower?.hasVisibleContent == true || upper?.hasVisibleContent == true
        case .delimited(let left, let body, let right): return !left.isEmpty || !right.isEmpty || body.hasVisibleContent
        }
    }
}

public extension MathExpression {
    var accessibilityText: String {
        switch self {
        case .row(let values):
            var result: [String] = [], digits = ""
            for value in values {
                if case .token(let text, _) = value, !text.isEmpty, text.allSatisfy(\.isNumber) { digits += text; continue }
                if !digits.isEmpty { result.append(digits); digits = "" }
                let description = value.accessibilityText
                if !description.isEmpty { result.append(description) }
            }
            if !digits.isEmpty { result.append(digits) }
            return result.joined(separator: " ")
        case .token(let text, _): return ["+": "plus", "-": "minus", "=": "equals", "×": "times", "÷": "divided by", "≤": "less than or equal to", "≥": "greater than or equal to", "≠": "not equal to", "∞": "infinity"][text] ?? text
        case .largeOperator(let symbol): return ["∑": "sum", "∏": "product", "∫": "integral"][symbol] ?? symbol
        case .fraction(let numerator, let denominator): return "fraction, numerator \(numerator.accessibilityText), denominator \(denominator.accessibilityText), end fraction"
        case .radical(let radicand, let degree): return "\(degree.map { "root of degree " + $0.accessibilityText } ?? "square root") of \(radicand.accessibilityText), end root"
        case .scripts(let base, let lower, let upper):
            return base.accessibilityText + (lower.map { ", subscript " + $0.accessibilityText } ?? "") + (upper.map { ", superscript " + $0.accessibilityText } ?? "") + ", end scripts"
        case .delimited(let left, let body, let right): return [left, body.accessibilityText, right].filter { !$0.isEmpty }.joined(separator: " ")
        case .space: return ""
        }
    }
}
