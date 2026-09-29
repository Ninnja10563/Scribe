#if canImport(AppKit)
import AppKit
import DocumentCore

/// Native tree navigation; expansion and focus are window state, never document edits.
@MainActor final class DocumentOutlineView: NSOutlineView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    final class Node: NSObject {
        var entry: OutlineEntry
        var children: [Node] = []
        init(_ entry: OutlineEntry) { self.entry = entry }
    }
    private(set) var roots: [Node] = []
    private var nodes: [UUID: Node] = [:]
    private var collapsed: Set<UUID> = []
    private var isRefreshing = false
    var navigate: ((UUID, Bool) -> Void)?
    var returnToDocument: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        addTableColumn(column); outlineTableColumn = column
        headerView = nil; backgroundColor = .windowBackgroundColor; rowHeight = 30
        style = .sourceList; indentationPerLevel = 13
        delegate = self; dataSource = self
        target = self; action = #selector(previewHeading); doubleAction = #selector(activateHeading)
        setAccessibilityLabel("Document outline")
        let menu = NSMenu()
        let expand = NSMenuItem(title: "Expand All Headings", action: #selector(expandAllHeadings), keyEquivalent: "")
        expand.target = self; menu.addItem(expand)
        let collapse = NSMenuItem(title: "Collapse All Headings", action: #selector(collapseAllHeadings), keyEquivalent: "")
        collapse.target = self; menu.addItem(collapse); self.menu = menu
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    func refresh(_ entries: [OutlineEntry]) {
        let selectedID = (item(atRow: selectedRow) as? Node)?.entry.id
        isRefreshing = true; defer { isRefreshing = false }
        var updated: [UUID: Node] = [:], stack: [Node] = []
        roots = []
        for entry in entries {
            let node = nodes[entry.id] ?? Node(entry)
            node.entry = entry; node.children = []; updated[entry.id] = node
            while let parent = stack.last, parent.entry.level >= entry.level { stack.removeLast() }
            if let parent = stack.last { parent.children.append(node) } else { roots.append(node) }
            stack.append(node)
        }
        nodes = updated; collapsed.formIntersection(Set(nodes.keys))
        reloadData()
        func restore(_ children: [Node]) {
            for node in children where !collapsed.contains(node.entry.id) {
                expandItem(node); restore(node.children)
            }
        }
        restore(roots)
        if let selectedID, let node = nodes[selectedID], row(forItem: node) >= 0 {
            selectRowIndexes(IndexSet(integer: row(forItem: node)), byExtendingSelection: false)
        } else { deselectAll(nil) }
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Node)?.children.count ?? roots.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? Node)?.children ?? roots)[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !(item as! Node).children.isEmpty }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let entry = (item as! Node).entry
        let title = entry.title.isEmpty ? "Untitled heading" : entry.title
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: entry.level == 1 ? .medium : .regular)
        label.lineBreakMode = .byTruncatingTail; label.toolTip = title
        label.setAccessibilityLabel(title); label.setAccessibilityHelp("Heading level \(entry.level)")
        return label
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isRefreshing, let node = item(atRow: selectedRow) as? Node else { return }
        navigate?(node.entry.id, false)
    }
    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isRefreshing, let node = notification.userInfo?["NSObject"] as? Node else { return }
        collapsed.insert(node.entry.id)
    }
    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isRefreshing, let node = notification.userInfo?["NSObject"] as? Node else { return }
        collapsed.remove(node.entry.id)
    }
    @objc func expandAllHeadings() { collapsed.removeAll(); expandItem(nil, expandChildren: true) }
    @objc func collapseAllHeadings() { collapsed = Set(nodes.values.filter { !$0.children.isEmpty }.map { $0.entry.id }); collapseItem(nil, collapseChildren: true) }
    @objc func previewHeading() {
        if let node = item(atRow: selectedRow) as? Node { navigate?(node.entry.id, false) }
    }
    @objc func activateHeading() {
        if let node = item(atRow: selectedRow) as? Node { navigate?(node.entry.id, true) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { activateHeading(); return }
        super.keyDown(with: event)
    }
    override func cancelOperation(_ sender: Any?) { returnToDocument?() }
}
#endif
