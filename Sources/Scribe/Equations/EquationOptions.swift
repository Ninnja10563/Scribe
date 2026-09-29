#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class EquationOptions: NSObject, NSTextViewDelegate, NSTextFieldDelegate {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 310))
    let source = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 68))
    let pointSize = NSTextField(string: "18")
    let preview = EquationPreview(frame: NSRect(x: 0, y: 0, width: 520, height: 120))
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    let templates = NSPopUpButton(frame: .zero, pullsDown: true)
    weak var applyButton: NSButton?
    init(equation: Equation?) {
        super.init()
        source.isRichText = false; source.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        source.isAutomaticQuoteSubstitutionEnabled = false; source.isAutomaticDashSubstitutionEnabled = false
        source.isAutomaticTextReplacementEnabled = false; source.isContinuousSpellCheckingEnabled = false
        source.textContainerInset = NSSize(width: 7, height: 6)
        source.string = equation?.source ?? "x^2 + 5x + 6 = 0"
        source.setAccessibilityLabel("Equation source"); source.identifier = NSUserInterfaceItemIdentifier("Equation Source")
        source.delegate = self
        pointSize.stringValue = String(equation?.pointSize ?? 18); pointSize.delegate = self
        pointSize.setAccessibilityLabel("Equation size in points"); pointSize.identifier = NSUserInterfaceItemIdentifier("Equation Size")
        pointSize.frame = NSRect(x: 390, y: 278, width: 70, height: 24)
        let label = NSTextField(labelWithString: "Equation source")
        label.frame = NSRect(x: 0, y: 280, width: 200, height: 20)
        let sizeLabel = NSTextField(labelWithString: "Size")
        sizeLabel.frame = NSRect(x: 350, y: 280, width: 36, height: 20)
        let units = NSTextField(labelWithString: "pt"); units.frame = NSRect(x: 466, y: 280, width: 25, height: 20)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 198, width: 520, height: 74))
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true; scroll.documentView = source
        source.isVerticallyResizable = true; source.isHorizontallyResizable = false
        source.autoresizingMask = [.width]; source.textContainer?.widthTracksTextView = true
        templates.frame = NSRect(x: 0, y: 165, width: 150, height: 26)
        templates.addItem(withTitle: "Insert Structure")
        for (title, markup) in [("Fraction", #"\frac{a}{b}"#), ("Square root", #"\sqrt{x}"#), ("Power", "x^{2}"), ("Subscript", "x_{1}"), ("Sum", #"\sum_{i=1}^{n}x_i"#), ("Integral", #"\int_{0}^{1}x"#), ("Greek letters", #"\alpha + \beta"#)] {
            templates.addItem(withTitle: title); templates.lastItem?.representedObject = markup
        }
        templates.target = self; templates.action = #selector(insertTemplate)
        let help = NSTextField(wrappingLabelWithString: #"Use ^ and _ for scripts; \frac{a}{b}, \sqrt{x}, \alpha and \text{words}."#)
        help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor
        help.frame = NSRect(x: 164, y: 158, width: 356, height: 32)
        preview.frame = NSRect(x: 0, y: 35, width: 520, height: 120)
        errorLabel.frame = NSRect(x: 0, y: 0, width: 520, height: 30); errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .secondaryLabelColor
        for child in [label, sizeLabel, units, pointSize, scroll, templates, help, preview, errorLabel] { view.addSubview(child) }
        refresh()
    }
    func equation() throws -> Equation {
        guard let size = Double(pointSize.stringValue) else { throw DocumentError.invalid("enter an equation size in points") }
        return try Equation(source: source.string, pointSize: size)
    }
    func refresh() {
        do {
            let value = try equation()
            preview.equationLayout = EquationLayout(equation: value); preview.setAccessibilityLabel(value.expression.accessibilityText)
            errorLabel.stringValue = ""; applyButton?.isEnabled = true
        } catch { preview.equationLayout = nil; errorLabel.stringValue = error.localizedDescription; applyButton?.isEnabled = false }
        preview.needsDisplay = true
    }
    func textDidChange(_ notification: Notification) { refresh() }
    func controlTextDidChange(_ notification: Notification) { refresh() }
    @objc private func insertTemplate() {
        guard let value = templates.selectedItem?.representedObject as? String else { return }
        source.insertText(value, replacementRange: source.selectedRange()); refresh()
        source.window?.makeFirstResponder(source)
    }
}

@MainActor final class EquationPreview: NSView {
    var equationLayout: EquationLayout?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        guard let layout = equationLayout, let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(1, (bounds.width - 24) / max(1, layout.width), (bounds.height - 16) / max(1, layout.height))
        context.saveGState()
        context.translateBy(x: (bounds.width - layout.width * scale) / 2, y: (bounds.height - layout.height * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        layout.draw(in: context, baseline: CGPoint(x: 0, y: layout.descent))
        context.restoreGState()
    }
}
#endif
