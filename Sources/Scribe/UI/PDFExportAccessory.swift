#if canImport(AppKit)
import AppKit
import ImportExport

/// Native save-panel controls; invalid ranges keep the panel open for correction.
@MainActor final class PDFExportAccessory: NSView, NSOpenSavePanelDelegate {
    let pages = NSTextField(), title = NSTextField(), author = NSTextField(), subject = NSTextField(), keywords = NSTextField()
    let pageCount: Int
    init(pageCount: Int, title: String, author: String) {
        self.pageCount = pageCount
        super.init(frame: NSRect(x: 0, y: 0, width: 440, height: 190))
        self.title.stringValue = title; self.author.stringValue = author
        pages.placeholderString = "All \(pageCount) pages"
        let rows: [(String, NSTextField)] = [("Pages", pages), ("Title", self.title), ("Author", self.author), ("Subject", subject), ("Keywords", keywords)]
        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        grid.rowSpacing = 8; grid.columnSpacing = 12; grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        for (label, field) in rows { field.setAccessibilityLabel(label) }
        let help = NSTextField(wrappingLabelWithString: "Pages: 1, 3–5. Original page numbering is retained. Text remains vector; images retain their source quality.")
        help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor; help.translatesAutoresizingMaskIntoConstraints = false
        addSubview(help)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 8), grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            help.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 10), help.leadingAnchor.constraint(equalTo: grid.leadingAnchor), help.trailingAnchor.constraint(equalTo: grid.trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    func selectedPages() throws -> [Int] { try ExportPageSelection.indices(pages.stringValue, pageCount: pageCount) }
    func panel(_ sender: Any, validate url: URL) throws { _ = try selectedPages() }
}
#endif
