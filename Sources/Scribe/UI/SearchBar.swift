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
    private var matches: [DocumentSearchMatch] = []
    private(set) var currentMatch: DocumentSearchMatch?
    private let presentation = NoteSearchPresentation()
    private var task: Task<Void, Never>?
    override init(frame: NSRect) {
        super.init(frame: frame)
        orientation = .vertical; alignment = .leading; spacing = 8
        edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        query.placeholderString = "Find in document"; query.delegate = self; query.setAccessibilityLabel("Find text")
        replacement.placeholderString = "Replace with"; replacement.setAccessibilityLabel("Replacement text")
        query.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        query.setContentHuggingPriority(.defaultLow, for: .horizontal)
        replacement.widthAnchor.constraint(equalToConstant: 260).isActive = true
        for button in [matchCase, wholeWord] { button.target = self; button.action = #selector(search); button.font = .systemFont(ofSize: 11) }
        count.font = .systemFont(ofSize: 11); count.textColor = .secondaryLabelColor
        let top = NSStackView(views: [query, matchCase, wholeWord,
            NSButton(title: "Previous", target: self, action: #selector(previous)),
            NSButton(title: "Next", target: self, action: #selector(next)), count,
            NSButton(title: "Done", target: self, action: #selector(close))])
        let bottom = NSStackView(views: [replacement,
            NSButton(title: "Replace", target: self, action: #selector(replace)),
            NSButton(title: "Replace All", target: self, action: #selector(replaceAll))])
        for row in [top, bottom] { row.spacing = 8; addArrangedSubview(row) }
        top.widthAnchor.constraint(equalTo: widthAnchor, constant: -32).isActive = true

    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    func controlTextDidChange(_ obj: Notification) { search() }
    @objc func search() {
        task?.cancel()
        guard let editor else { return }
        let revision = editor.revision, query = query.stringValue
        let options = SearchOptions(matchCase: matchCase.state == .on, wholeWord: wholeWord.state == .on)
        task = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            guard editor.revision == revision else { return }
            let snapshot = editor.semanticText
            let found = await Task.detached { snapshot.documentMatches(query: query, options: options) }.value
            guard !Task.isCancelled, editor.revision == revision else { return }
            matches = found; count.stringValue = "\(found.count) found"
            presentation.highlight(found, in: editor)
            if let currentMatch, !found.contains(currentMatch) { self.currentMatch = nil }
        }
    }
    private func refreshMatchesForNavigation() {
        guard let editor else { return }
        matches = editor.semanticText.documentMatches(query: query.stringValue, options: SearchOptions(matchCase: matchCase.state == .on, wholeWord: wholeWord.state == .on))
        count.stringValue = "\(matches.count) found"
    }
    @objc func next() { navigate(forward: true) }
    @objc func previous() { navigate(forward: false) }
    private func navigate(forward: Bool) {
        refreshMatchesForNavigation()
        guard let editor, !matches.isEmpty else { return }
        let selection = editor.activeTextView.selectedRange()
        let match: DocumentSearchMatch
        if let currentMatch, isSelected(currentMatch, selection: selection), let index = matches.firstIndex(of: currentMatch) {
            match = matches[(index + (forward ? 1 : matches.count - 1)) % matches.count]
        } else if forward {
            match = matches.first { $0.sourceLocation >= NSMaxRange(selection) && $0 != .body(selection) } ?? matches[0]
        } else {
            match = matches.last { $0.sourceLocation < selection.location } ?? matches.last!
        }
        currentMatch = match
        switch match {
        case .body(let range): editor.select(range)
        case .note:
            _ = presentation.reveal(match, in: editor)
            window?.makeFirstResponder(query)
        }
        presentation.highlight(matches, in: editor)
    }
    private func isSelected(_ match: DocumentSearchMatch, selection: NSRange) -> Bool {
        switch match {
        case .body(let range): return range == selection
        case .note(_, _, let reference): return reference == selection
        }
    }
    @objc func replace() {
        guard let editor else { return }
        refreshMatchesForNavigation()
        let selection = editor.activeTextView.selectedRange()
        let selected = currentMatch.flatMap { matches.contains($0) && isSelected($0, selection: selection) ? $0 : nil }
            ?? matches.first { $0 == .body(selection) }
        guard let selected else { next(); return }
        performReplacement([selected], action: "Replace")
    }
    @objc func replaceAll() {
        refreshMatchesForNavigation(); performReplacement(matches, action: "Replace All")
    }
    private func performReplacement(_ found: [DocumentSearchMatch], action: String) {
        guard let editor else { return }
        do {
            try DocumentSearchReplacement.apply(found, replacement: replacement.stringValue, in: editor, action: action)
            currentMatch = nil; search()
        } catch { presentError(error) }
    }
    func refreshHighlights() {
        guard !isHidden, let editor else { return }
        refreshMatchesForNavigation(); presentation.highlight(matches, in: editor)
    }
    func cancelPendingWork() { task?.cancel(); task = nil; presentation.clear(); currentMatch = nil }
    @objc func close() {
        isHidden = true; cancelPendingWork()
        if let editor { editor.canvas.needsDisplay = true; window?.makeFirstResponder(editor.activeTextView) }
    }
}
#endif
