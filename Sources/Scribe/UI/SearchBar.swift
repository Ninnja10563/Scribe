#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class SearchBar: NSStackView, NSSearchFieldDelegate {
    let query = NSSearchField()
    let replacement = NSTextField()
    private let count = NSTextField(labelWithString: "")
    private let matchCase = NSButton(checkboxWithTitle: "Case", target: nil, action: nil)
    private let wholeWord = NSButton(checkboxWithTitle: "Whole word", target: nil, action: nil)
    weak var editor: PaginatedEditor?
    private var matches: [NSRange] = []
    private var task: Task<Void, Never>?
    override init(frame: NSRect) {
        super.init(frame: frame)
        orientation = .horizontal; spacing = 8; edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        query.placeholderString = "Find in document"; query.delegate = self; query.setAccessibilityLabel("Find text")
        replacement.placeholderString = "Replace with"; replacement.setAccessibilityLabel("Replacement text")
        query.widthAnchor.constraint(equalToConstant: 160).isActive = true
        replacement.widthAnchor.constraint(equalToConstant: 130).isActive = true
        addArrangedSubview(query); addArrangedSubview(replacement)
        for button in [matchCase, wholeWord] { button.target = self; button.action = #selector(search); button.font = .systemFont(ofSize: 11); addArrangedSubview(button) }
        addArrangedSubview(NSButton(title: "Previous", target: self, action: #selector(previous)))
        addArrangedSubview(NSButton(title: "Next", target: self, action: #selector(next)))
        addArrangedSubview(NSButton(title: "Replace", target: self, action: #selector(replace)))
        addArrangedSubview(NSButton(title: "All", target: self, action: #selector(replaceAll)))
        count.font = .systemFont(ofSize: 11); count.textColor = .secondaryLabelColor; addArrangedSubview(count)
        addArrangedSubview(NSButton(title: "Done", target: self, action: #selector(close)))
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    func controlTextDidChange(_ obj: Notification) { search() }
    @objc func search() {
        task?.cancel()
        guard let editor else { return }
        let text = editor.storage.string, query = query.stringValue
        let options = SearchOptions(matchCase: matchCase.state == .on, wholeWord: wholeWord.state == .on)
        task = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            let found = await Task.detached { DocumentSearch.matches(in: text, query: query, options: options) }.value
            guard !Task.isCancelled, editor.storage.string == text else { return }
            matches = found; count.stringValue = "\(found.count) found"
            editor.layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: editor.storage.length))
            for range in found { editor.layout.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.4), forCharacterRange: range) }
        }
    }
    private func refreshMatchesForNavigation() {
        guard let editor else { return }
        matches = DocumentSearch.matches(in: editor.storage.string, query: query.stringValue, options: SearchOptions(matchCase: matchCase.state == .on, wholeWord: wholeWord.state == .on))
    }
    @objc func next() {
        refreshMatchesForNavigation()
        guard let editor, !matches.isEmpty else { return }
        let selection = editor.activeTextView.selectedRange()
        let match = matches.first { $0.location >= NSMaxRange(selection) && $0 != selection } ?? matches[0]
        editor.select(match)
    }
    @objc func previous() {
        refreshMatchesForNavigation()
        guard let editor, !matches.isEmpty else { return }
        let selection = editor.activeTextView.selectedRange()
        editor.select(matches.last { $0.location < selection.location } ?? matches.last!)
    }
    @objc func replace() {
        guard let editor else { return }
        let selection = editor.activeTextView.selectedRange()
        let fresh = DocumentSearch.matches(in: editor.storage.string, query: query.stringValue, options: SearchOptions(matchCase: matchCase.state == .on, wholeWord: wholeWord.state == .on))
        guard fresh.contains(selection) else { next(); return }
        editor.activeTextView.insertText(replacement.stringValue, replacementRange: selection); search()
    }
    @objc func replaceAll() {
        guard let editor else { return }
        let found = DocumentSearch.matches(in: editor.storage.string, query: query.stringValue, options: SearchOptions(matchCase: matchCase.state == .on, wholeWord: wholeWord.state == .on))
        let view = editor.activeTextView
        view.breakUndoCoalescing(); view.undoManager?.beginUndoGrouping()
        for range in found.reversed() { view.insertText(replacement.stringValue, replacementRange: range) }
        view.undoManager?.endUndoGrouping(); view.undoManager?.setActionName("Replace All")
        search()
    }
    @objc func close() {
        isHidden = true; task?.cancel()
        if let editor { editor.layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: editor.storage.length)); window?.makeFirstResponder(editor.activeTextView) }
    }
}
#endif
