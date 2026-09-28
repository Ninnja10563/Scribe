#if canImport(AppKit)
import AppKit
import DocumentCore

extension EditorWindowController {
    @objc func toggleComments() {
        if commentsSidebar.isHidden {
            commentsSidebar.isHidden = false; commentsSidebar.reload(fileDocument.snapshot()); commentsSidebar.focusList()
        } else { hideComments() }
    }
    func hideComments() {
        commentsSidebar.isHidden = true; window?.makeFirstResponder(editor.activeTextView)
    }
    @objc func addComment() {
        let model = fileDocument.snapshot(), selection = editor.activeTextView.selectedRange()
        guard selection.length > 0, let anchor = CommentProjection.anchor(for: selection, in: editor.storage, document: model), anchor.length > 0 else {
            showStatus("Select the text you want to comment on."); return
        }
        guard let value = commentDialog(text: "", author: model.author.isEmpty ? NSFullUserName() : model.author, adding: true) else { return }
        let comment = Comment(anchor: anchor, text: value.text, author: value.author)
        fileDocument.performEdit("Add Comment") { $0.comments.append(comment) }
        commentsSidebar.isHidden = false; commentsSidebar.reload(fileDocument.snapshot(), selecting: comment.id)
        selectComment(comment)
    }
    func editComment(_ comment: Comment) {
        let previous = window?.firstResponder as? NSView
        let restoreFocus = previous?.isDescendant(of: commentsSidebar) == true
        guard let value = commentDialog(text: comment.text, author: comment.author, adding: false) else { return }
        fileDocument.performEdit("Edit Comment") { document in
            guard let index = document.comments.firstIndex(where: { $0.id == comment.id }) else { return }
            document.comments[index].text = value.text; document.comments[index].author = value.author
        }
        if restoreFocus { window?.makeFirstResponder(previous) }
    }
    func selectComment(_ comment: Comment, keepSidebarFocus: Bool = false) {
        guard comment.isDetached != true, let range = CommentProjection.range(for: comment.anchor, in: editor.storage, document: fileDocument.snapshot()) else {
            showStatus("This comment's associated text was deleted."); return
        }
        editor.select(range, focus: !keepSidebarFocus)
    }
    private func commentDialog(text: String, author: String, adding: Bool) -> (text: String, author: String)? {
        let alert = NSAlert(); alert.messageText = adding ? "Add Comment" : "Edit Comment"
        let name = NSTextField(string: author); name.setAccessibilityLabel("Comment author")
        let body = NSTextView(frame: NSRect(x: 0, y: 0, width: 340, height: 140))
        body.isRichText = false; body.string = text; body.font = .systemFont(ofSize: 13)
        body.isVerticallyResizable = true; body.autoresizingMask = .width; body.textContainer?.widthTracksTextView = true
        body.textContainerInset = NSSize(width: 6, height: 6); body.setAccessibilityLabel("Comment text")
        let scroll = NSScrollView(); scroll.documentView = body; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: 340).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 140).isActive = true
        name.widthAnchor.constraint(equalToConstant: 340).isActive = true
        let stack = NSStackView(views: [NSTextField(labelWithString: "Author"), name, scroll]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 198); alert.accessoryView = stack
        alert.addButton(withTitle: adding ? "Add" : "Save"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = body
        while alert.runModal() == .alertFirstButtonReturn {
            if !body.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (body.string, name.stringValue) }
            alert.informativeText = "Enter some comment text before saving."
        }
        return nil
    }
}
#endif
