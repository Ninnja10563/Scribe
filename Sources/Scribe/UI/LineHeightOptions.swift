#if canImport(AppKit)
import AppKit
import DocumentCore

/// Shared native controls for paragraph overrides and named style definitions.
@MainActor final class LineHeightOptions: NSObject {
    let mode = NSPopUpButton()
    let amount = NSTextField(string: "1.5")
    let unit = NSTextField(labelWithString: "×")
    let valueView = NSStackView()
    var onModeChange: (() -> Void)?
    private var previousMode = 0
    init(_ height: ParagraphLineHeight?) {
        super.init()
        mode.addItems(withTitles: ["Natural", "Multiple", "At least", "Exactly"])
        if let height {
            mode.selectItem(at: (ParagraphLineHeight.Rule.allCases.firstIndex(of: height.rule) ?? 0) + 1)
            amount.stringValue = String(height.value)
        }
        previousMode = mode.indexOfSelectedItem
        mode.target = self; mode.action = #selector(changed)
        mode.setAccessibilityLabel("Line height mode"); mode.identifier = .init("Line height mode")
        amount.setAccessibilityLabel("Line height value"); amount.identifier = .init("Line height value")
        valueView.orientation = .horizontal; valueView.spacing = 8
        valueView.addArrangedSubview(amount); valueView.addArrangedSubview(unit)
        amount.widthAnchor.constraint(equalToConstant: 90).isActive = true
        updateUnits()
    }
    @objc private func changed() {
        let index = mode.indexOfSelectedItem
        if index == 1 && previousMode != 1 { amount.stringValue = "1.5" }
        else if index > 1 && previousMode <= 1 { amount.stringValue = "24" }
        previousMode = index; updateUnits(); onModeChange?()
    }
    private func updateUnits() {
        amount.isEnabled = mode.indexOfSelectedItem > 0
        unit.stringValue = mode.indexOfSelectedItem == 1 ? "×" : "pt"
        unit.textColor = amount.isEnabled ? .labelColor : .disabledControlTextColor
    }
    func value() throws -> ParagraphLineHeight? {
        let index = mode.indexOfSelectedItem
        guard index != 0 else { return nil }
        guard (1...3).contains(index), let value = Double(amount.stringValue) else {
            throw DocumentError.invalid("enter a line-height value")
        }
        let result = ParagraphLineHeight(rule: ParagraphLineHeight.Rule.allCases[index - 1], value: value)
        try result.validate(); return result
    }
}
#endif
