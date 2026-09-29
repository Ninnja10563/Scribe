#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class ReviewSidebar: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var owner: EditorWindowController?
    let table = NSTableView()
    let detail = NSTextField(wrappingLabelWithString: "No pending changes.")
    let accept = NSButton(title: "Accept", target: nil, action: nil)
    let reject = NSButton(title: "Reject", target: nil, action: nil)
    private let count = NSTextField(labelWithString: "Changes")
    private var changes: [IndexedRevision] = []
    private var reloading = false
    private var model: ScribeDocument?
    var selectedChange: IndexedRevision? { changes.indices.contains(table.selectedRow) ? changes[table.selectedRow] : nil }
    override init(frame: NSRect) { super.init(frame: frame); build() }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    private func build() {
        count.font = .systemFont(ofSize: 12, weight: .semibold)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close changes")!, target: self, action: #selector(closePanel))
        close.isBordered = false
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [count, spacer, close])
        table.addTableColumn(NSTableColumn(identifier: .init("change")))
        table.headerView = nil; table.style = .plain; table.rowHeight = 54
        table.backgroundColor = .windowBackgroundColor; table.dataSource = self; table.delegate = self
        table.setAccessibilityLabel("Tracked changes")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        detail.font = .systemFont(ofSize: 12); detail.maximumNumberOfLines = 12
        detail.setAccessibilityLabel("Selected change details")
        let previous = NSButton(title: "Previous", target: self, action: #selector(previousChange))
        let next = NSButton(title: "Next", target: self, action: #selector(nextChange))
        let navigation = NSStackView(views: [previous, next])
        accept.target = self; accept.action = #selector(acceptChange)
        reject.target = self; reject.action = #selector(rejectChange)
        let actions = NSStackView(views: [accept, reject])
        for button in [previous, next, accept, reject] { button.bezelStyle = .rounded; button.controlSize = .small }
        let stack = NSStackView(views: [header, navigation, scroll, detail, actions])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
        for view in [header, scroll, detail] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        updateDetail()
    }
    func reload(_ document: ScribeDocument) {
        let selected = owner?.reviewNavigation.selectedID ?? selectedChange?.id
        model = document; changes = RevisionIndex(document: document).changes
        reloading = true; table.reloadData()
        if let index = changes.firstIndex(where: { $0.id == selected }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
        reloading = false
        count.stringValue = "Changes (\(changes.count))"; updateDetail()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { changes.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard changes.indices.contains(row) else { return nil }
        let change = changes[row], field = NSTextField(wrappingLabelWithString: "\(summary(change))\n\(change.author.name)")
        field.font = .systemFont(ofSize: 12); field.maximumNumberOfLines = 2
        field.setAccessibilityLabel("\(summary(change)), by \(change.author.name)")
        return field
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading else { return }
        updateDetail()
        if let change = selectedChange { _ = owner?.reviewNavigation.select(change.id); focusList() }
    }
    private func summary(_ change: IndexedRevision) -> String {
        let kinds = Set(change.locations.map(\.kind))
        var labels: [String] = []
        if kinds.contains(.insertion) { labels.append("Insertion") }
        if kinds.contains(.deletion) { labels.append("Deletion") }
        if kinds.contains(.characterFormatting) || kinds.contains(.paragraphFormatting) { labels.append("Formatting") }
        return labels.joined(separator: " and ")
    }
    private func updateDetail() {
        accept.isEnabled = selectedChange != nil; reject.isEnabled = selectedChange != nil
        guard let change = selectedChange else { detail.stringValue = changes.isEmpty ? "No pending changes." : "Select a change to review it."; return }
        var excerpt = ""
        if let location = change.locations.first, let model {
            let paragraphs = location.noteID.flatMap { id in model.notes.first(where: { $0.id == id })?.paragraphs } ?? model.paragraphs
            if let paragraph = paragraphs.first(where: { $0.id == location.paragraphID }) {
                excerpt = location.isParagraphSeparator ? "Paragraph break" : String(paragraph.text.prefix(160))
                if location.noteID != nil { excerpt = "Note: " + excerpt }
            }
        }
        detail.stringValue = "\(summary(change))\n\(change.author.name)\n\(change.date.formatted(date: .abbreviated, time: .shortened))\n\n\(excerpt)"
    }
    func focusList() { window?.makeFirstResponder(table) }
    @objc func previousChange() { navigate(backwards: true) }
    @objc func nextChange() { navigate(backwards: false) }
    private func navigate(backwards: Bool) {
        guard let owner else { return }; _ = owner.reviewNavigation.navigate(backwards: backwards)
        reload(owner.fileDocument.snapshot()); focusList()
    }
    @objc func acceptChange() { decide(accepting: true) }
    @objc func rejectChange() { decide(accepting: false) }
    private func decide(accepting: Bool) {
        guard let owner, let change = selectedChange, owner.reviewNavigation.select(change.id) else { return }
        do { try owner.reviewNavigation.resolveCurrent(accepting: accepting); reload(owner.fileDocument.snapshot()); focusList() }
        catch { owner.window?.presentError(error) }
    }
    @objc private func closePanel() { isHidden = true; owner?.window?.makeFirstResponder(owner?.editor.activeTextView) }
}
#endif
