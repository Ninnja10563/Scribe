#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class CommentsSidebar: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var owner: EditorWindowController?
    private let table = NSTableView(), detail = NSTextView()
    private let title = NSTextField(labelWithString: "Comments"), location = NSTextField(wrappingLabelWithString: "")
    private let resolved = NSButton(checkboxWithTitle: "Show resolved", target: nil, action: nil)
    private let edit = NSButton(title: "Edit…", target: nil, action: nil)
    private let resolve = NSButton(title: "Resolve", target: nil, action: nil)
    private let delete = NSButton(title: "Delete", target: nil, action: nil)
    private var comments: [Comment] = [], reloading = false
    private var model: ScribeDocument?
    var selectedComment: Comment? { comments.indices.contains(table.selectedRow) ? comments[table.selectedRow] : nil }
    override init(frame: NSRect) { super.init(frame: frame); build() }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    private func build() {
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        let add = NSButton(title: "Add", target: self, action: #selector(addComment))
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close comments")!, target: self, action: #selector(closeComments))
        close.isBordered = false; close.setAccessibilityLabel("Close comments")
        let flex = NSView(); flex.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let heading = NSStackView(views: [title, flex, add, close]); heading.spacing = 8
        resolved.target = self; resolved.action = #selector(changeFilter)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("comment")))
        table.headerView = nil; table.rowHeight = 54; table.style = .plain; table.backgroundColor = .windowBackgroundColor
        table.target = self; table.action = #selector(revealComment)
        table.dataSource = self; table.delegate = self; table.setAccessibilityLabel("Document comments")
        let list = NSScrollView(); list.documentView = table; list.hasVerticalScroller = true; list.autohidesScrollers = true
        list.drawsBackground = false; list.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        detail.isEditable = false; detail.isRichText = false; detail.isSelectable = true
        detail.font = .systemFont(ofSize: 12); detail.textColor = .labelColor; detail.drawsBackground = false
        detail.textContainerInset = NSSize(width: 6, height: 8); detail.setAccessibilityLabel("Selected comment")
        let body = NSScrollView(); body.documentView = detail; body.hasVerticalScroller = true; body.autohidesScrollers = true; body.drawsBackground = false
        let preferredHeight = body.heightAnchor.constraint(equalToConstant: 170); preferredHeight.priority = .defaultHigh; preferredHeight.isActive = true
        body.heightAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
        detail.isVerticallyResizable = true; detail.isHorizontallyResizable = false; detail.autoresizingMask = .width; detail.textContainer?.widthTracksTextView = true
        location.font = .systemFont(ofSize: 11); location.textColor = .secondaryLabelColor
        location.maximumNumberOfLines = 3; location.lineBreakMode = .byTruncatingTail
        for button in [edit, resolve, delete] { button.target = self; button.bezelStyle = .rounded; button.controlSize = .small }
        edit.action = #selector(editComment); resolve.action = #selector(resolveComment); delete.action = #selector(deleteComment)
        let actions = NSStackView(views: [edit, resolve, delete]); actions.spacing = 8
        let stack = NSStackView(views: [heading, resolved, list, location, body, actions])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
        for child in [heading, list, location, body, actions] { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        updateDetail()
    }
    func reload(_ document: ScribeDocument, selecting id: UUID? = nil) {
        let selection = id ?? selectedComment?.id
        reloading = true; model = document
        comments = document.comments.filter { resolved.state == .on || !$0.resolved }
        title.stringValue = "Comments (\(comments.count))"; table.reloadData()
        if let selection, let row = comments.firstIndex(where: { $0.id == selection }) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
        reloading = false; updateDetail()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { comments.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let comment = comments[row]
        let label = NSTextField(wrappingLabelWithString: "\(comment.author)\(comment.resolved ? " · Resolved" : "")\n\(comment.text)")
        label.font = .systemFont(ofSize: 11); label.maximumNumberOfLines = 2; label.lineBreakMode = .byTruncatingTail; label.toolTip = comment.text
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading else { return }
        updateDetail()
        revealComment()
    }
    @objc private func revealComment() { if let comment = selectedComment { owner?.selectComment(comment) } }
    private func updateDetail() {
        let comment = selectedComment
        detail.string = comment?.text ?? "Select text in your document, then choose Add Comment."
        if let comment, comment.isDetached == true { location.stringValue = "Associated text was deleted. The comment is retained." }
        else if let comment, let paragraph = model?.paragraphs.first(where: { $0.id == comment.anchor.paragraphID }) {
            let text = paragraph.text as NSString
            let offset = min(text.length, max(0, comment.anchor.offset))
            let length = comment.anchor.endParagraphID == nil ? min(comment.anchor.length, text.length - offset) : text.length - offset
            let excerpt = String(text.substring(with: NSRange(location: offset, length: length)).prefix(100))
            location.stringValue = excerpt.isEmpty ? "Linked to a paragraph break." : "Linked text: “\(excerpt)”"
        } else { location.stringValue = "" }
        for button in [edit, resolve, delete] { button.isEnabled = comment != nil }
        resolve.title = comment?.resolved == true ? "Reopen" : "Resolve"
    }
    @objc private func addComment() { owner?.addComment() }
    @objc private func closeComments() { isHidden = true }
    @objc private func changeFilter() { if let owner { reload(owner.fileDocument.snapshot()) } }
    @objc private func editComment() { if let comment = selectedComment { owner?.editComment(comment) } }
    @objc private func resolveComment() {
        guard let comment = selectedComment else { return }
        owner?.fileDocument.performEdit(comment.resolved ? "Reopen Comment" : "Resolve Comment") { document in
            guard let index = document.comments.firstIndex(where: { $0.id == comment.id }) else { return }
            document.comments[index].resolved.toggle()
        }
    }
    @objc private func deleteComment() {
        guard let id = selectedComment?.id else { return }
        owner?.fileDocument.performEdit("Delete Comment") { $0.comments.removeAll { $0.id == id } }
    }
}
#endif
