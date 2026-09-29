import Foundation

/// Deliberately bounded mathematical input, not a general TeX interpreter.
public struct MathParser {
    private let input: [Character]
    private var offset = 0
    private var nodes = 0
    public static func parse(_ source: String) throws -> MathExpression {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DocumentError.invalid("enter an equation") }
        guard !source.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && !CharacterSet.whitespacesAndNewlines.contains($0) }) else { throw DocumentError.invalid("equation contains an unsupported control character") }
        guard source.utf8.count <= 8192 else { throw DocumentError.invalid("equation input exceeds 8 KB") }
        var parser = MathParser(input: Array(source))
        let value = try parser.row(until: nil, depth: 0)
        guard parser.offset == parser.input.count else { throw parser.error("unexpected closing delimiter") }
        guard value.hasVisibleContent else { throw parser.error("equation needs mathematical content") }
        return value
    }
    private var next: Character? { offset < input.count ? input[offset] : nil }
    private mutating func spaces() { while next?.isWhitespace == true { offset += 1 } }
    private func error(_ message: String) -> DocumentError { .invalid("\(message) at equation character \(offset + 1)") }
    private mutating func count(_ value: MathExpression) throws -> MathExpression {
        nodes += 1; guard nodes <= 2048 else { throw error("equation is too complex") }; return value
    }
    private mutating func row(until end: Character?, depth: Int, stopsAtRight: Bool = false) throws -> MathExpression {
        guard depth <= 32 else { throw error("equation nesting exceeds 32 levels") }
        var values: [MathExpression] = []
        while true {
            spaces()
            if next == nil || next == end || (stopsAtRight && commandAhead == "right") { break }
            if next == "}" || next == ")" || next == "]" { throw error("unexpected closing delimiter") }
            var base = try atom(depth: depth)
            var lower: MathExpression?, upper: MathExpression?
            while true {
                spaces()
                guard let marker = next, marker == "^" || marker == "_" else { break }
                offset += 1; spaces()
                if marker == "^" {
                    guard upper == nil else { throw error("duplicate superscript") }
                    upper = try atom(depth: depth + 1)
                } else {
                    guard lower == nil else { throw error("duplicate subscript") }
                    lower = try atom(depth: depth + 1)
                }
            }
            if lower != nil || upper != nil { base = try count(.scripts(base: base, lower: lower, upper: upper)) }
            values.append(base)
        }
        if values.count == 1 { return values[0] }
        return try count(.row(values))
    }
    private mutating func group(depth: Int) throws -> MathExpression {
        spaces(); guard next == "{" else { throw error("expected a braced argument") }
        offset += 1
        let value = try row(until: "}", depth: depth + 1)
        guard next == "}" else { throw error("missing closing brace") }
        offset += 1
        if case .row(let values) = value, values.isEmpty { throw error("empty mathematical argument") }
        return value
    }
    private var commandAhead: String? {
        guard next == "\\" else { return nil }
        var index = offset + 1, result = ""
        while index < input.count, input[index].isASCII, input[index].isLetter { result.append(input[index]); index += 1 }
        return result
    }
    private mutating func atom(depth: Int) throws -> MathExpression {
        guard depth <= 32 else { throw error("equation nesting exceeds 32 levels") }
        spaces(); guard let character = next else { throw error("missing mathematical argument") }
        if character == "{" { return try group(depth: depth) }
        if character == "(" || character == "[" {
            offset += 1; let closing: Character = character == "(" ? ")" : "]"
            let body = try row(until: closing, depth: depth + 1)
            guard next == closing else { throw error("missing closing delimiter") }
            offset += 1; return try count(.delimited(left: String(character), body: body, right: String(closing)))
        }
        if character == "\\" {
            offset += 1
            var command = ""
            while let c = next, c.isASCII, c.isLetter { command.append(c); offset += 1 }
            if command.isEmpty {
                guard let escaped = next, "{}_%#&|".contains(escaped) || escaped == "," || escaped == ";" || escaped == " " else { throw error("unsupported escape") }
                offset += 1
                if escaped == "," { return try count(.space(1.0 / 6)) }
                if escaped == ";" { return try count(.space(5.0 / 18)) }
                if escaped == " " { return try count(.space(1.0 / 3)) }
                return try count(.token(String(escaped), italic: false))
            }
            switch command {
            case "frac":
                let numerator = try group(depth: depth), denominator = try group(depth: depth)
                return try count(.fraction(numerator: numerator, denominator: denominator))
            case "sqrt":
                spaces(); var degree: MathExpression?
                if next == "[" {
                    offset += 1; degree = try row(until: "]", depth: depth + 1)
                    guard next == "]" else { throw error("missing root-degree delimiter") }; offset += 1
                }
                return try count(.radical(radicand: group(depth: depth), degree: degree))
            case "sum", "prod", "int": return try count(.largeOperator(["sum": "∑", "prod": "∏", "int": "∫"][command]!))
            case "left":
                let left = try delimiter()
                let body = try row(until: nil, depth: depth + 1, stopsAtRight: true)
                guard commandAhead == "right" else { throw error("missing \\right delimiter") }
                offset += 6
                return try count(.delimited(left: left, body: body, right: delimiter()))
            case "text": return try count(.token(literalText(), italic: false))
            case "quad": return try count(.space(1))
            case "qquad": return try count(.space(2))
            case "sin", "cos", "tan", "log", "ln", "exp", "lim": return try count(.token(command, italic: false))
            default:
                if let symbol = Self.symbols[command] { return try count(.token(symbol, italic: Self.greek.contains(command))) }
                throw error("unsupported command \\\(command)")
            }
        }
        guard !"^_})]".contains(character), !character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { throw error("unexpected mathematical character") }
        offset += 1
        if "∑∏∫".contains(character) { return try count(.largeOperator(String(character))) }
        return try count(.token(String(character), italic: character.isLetter))
    }
    private mutating func delimiter() throws -> String {
        spaces(); if next == "\\" { offset += 1 }
        guard let value = next, "()[]{}|.".contains(value) else { throw error("unsupported delimiter") }
        offset += 1; return value == "." ? "" : String(value)
    }
    private mutating func literalText() throws -> String {
        spaces(); guard next == "{" else { throw error("expected braced text") }
        offset += 1; var text = "", nesting = 1
        while let value = next {
            offset += 1
            if value == "\\", let escaped = next, "{}\\".contains(escaped) { text.append(escaped); offset += 1; continue }
            if value == "{" { nesting += 1; guard nesting <= 32 else { throw error("text nesting exceeds 32 levels") } }
            if value == "}" { nesting -= 1; if nesting == 0 { return text } }
            text.append(value.isWhitespace ? " " : value)
        }
        throw error("missing closing text brace")
    }
    private static let greek: Set<String> = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega"]
    private static let symbols = ["alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω", "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓", "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠", "approx": "≈", "equiv": "≡", "infty": "∞", "partial": "∂", "nabla": "∇", "in": "∈", "notin": "∉", "to": "→"]
}
