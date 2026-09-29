#if canImport(AppKit)
import AppKit
import DocumentCore

extension EditorWindowController {
    @objc func insertEquation() { equationDialog(editing: false) }
    @objc func editEquation() { equationDialog(editing: true) }
    private func equationDialog(editing: Bool) {
        let range = editor.activeTextView.selectedRange()
        let original: Equation?
        if editing {
            guard range.location < editor.storage.length,
                  let data = editor.storage.attribute(.scribeEquation, at: range.location, effectiveRange: nil) as? Data,
                  let value = try? JSONDecoder().decode(Equation.self, from: data) else { showStatus("Select an equation first."); return }
            original = value
        } else { original = nil }
        let originalStorage = NSAttributedString(attributedString: editor.storage)
        let options = EquationOptions(equation: original), alert = NSAlert()
        alert.messageText = editing ? "Edit Equation" : "Insert Equation"
        alert.informativeText = "Enter mathematical notation and check the preview."
        alert.accessoryView = options.view
        options.applyButton = alert.addButton(withTitle: editing ? "Apply" : "Insert")
        alert.addButton(withTitle: "Cancel"); options.refresh()
        alert.window.initialFirstResponder = options.source
        while !isClosing {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do {
                guard originalStorage.isEqual(to: editor.storage) else { throw DocumentError.invalid("the document changed while the equation was being edited; reopen the equation dialog") }
                try applyEquation(options.equation(), replacing: editing ? NSRange(location: range.location, length: 1) : range, action: editing ? "Edit Equation" : "Insert Equation")
                return
            } catch { alert.informativeText = error.localizedDescription }
        }
    }
    func applyEquation(_ equation: Equation, replacing range: NSRange, action: String) throws {
        guard !isClosing, range.location >= 0, range.length >= 0, range.location <= editor.storage.length, range.length <= editor.storage.length - range.location else { throw DocumentError.invalid("the equation selection is no longer available") }
        let layout = EquationLayout(equation: equation), page = editor.canvas.pageSettings
        guard layout.width + 4 <= page.contentWidth, layout.height + 4 <= page.contentHeight - 24 else { throw DocumentError.invalid("this equation is larger than the page writing area; reduce its size or simplify it") }
        let view = editor.activeTextView
        var attributes = range.length > 0 ? editor.storage.attributes(at: range.location, effectiveRange: nil) : view.typingAttributes
        attributes.removeValue(forKey: .scribeImage)
        attributes[.attachment] = EquationProjection.attachment(equation)
        attributes[.scribeEquation] = try JSONEncoder().encode(equation)
        editor.select(range)
        editor.activeTextView.replaceSelection(NSAttributedString(string: "\u{FFFC}", attributes: attributes), action: action)
        for key in [NSAttributedString.Key.attachment, .scribeEquation, .scribeImage] { editor.activeTextView.typingAttributes.removeValue(forKey: key) }
    }
}
#endif
