import Foundation
import DocumentCore

enum DOCXLineHeight {
    static func attributes(_ height: ParagraphLineHeight?) -> String {
        guard let height else { return "" }
        let rule: String, unit: Double
        switch height.rule {
        case .multiple: rule = "auto"; unit = 240
        case .minimum: rule = "atLeast"; unit = 20
        case .exact: rule = "exact"; unit = 20
        }
        return " w:line=\"\(Int((height.value * unit).rounded()))\" w:lineRule=\"\(rule)\""
    }
    static func apply(_ attributes: [String: String], to format: inout ParagraphFormatting) throws {
        let line = wordAttribute(attributes, "line"), rawRule = wordAttribute(attributes, "lineRule")
        guard line != nil || rawRule != nil else { return }
        let rule: ParagraphLineHeight.Rule
        if let rawRule {
            switch rawRule {
            case "auto": rule = .multiple
            case "atLeast": rule = .minimum
            case "exact": rule = .exact
            default: throw DocumentError.invalid("unsupported Office line-height rule")
            }
        } else { rule = format.lineHeight?.rule ?? .multiple }
        let priorUnits = format.lineHeight.map { $0.value * ($0.rule == .multiple ? 240 : 20) } ?? 240
        let units: Double
        if let line {
            guard let value = Int(line), value > 0 else { throw DocumentError.invalid("invalid Office line-height value") }
            units = Double(value)
        } else { units = priorUnits }
        let height = ParagraphLineHeight(rule: rule, value: units / (rule == .multiple ? 240 : 20))
        try height.validate()
        format.lineHeight = height; format.lineSpacing = 0
    }
}
