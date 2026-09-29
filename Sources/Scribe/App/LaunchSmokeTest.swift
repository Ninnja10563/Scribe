#if canImport(AppKit)
import AppKit
import DocumentCore
import ImportExport

/// Explicit --smoke-test launch path; sample content is isolated from user-document lifecycle code.
extension AppDelegate {
    func smokeTest() async {
        do {
            guard MathFont.isAvailable else { throw DocumentError.invalid("bundled equation font is missing from the application") }
            let document = ScribeFileDocument()
            try document.model.setMetadata(title: "Scribe Smoke Test", author: "Scribe", language: "en-GB")
            document.model.sections[0].paragraphs = [Paragraph("Scribe", style: "title"), Paragraph("A native document workspace", style: "subtitle"), Paragraph("A considered place to write", style: "heading1"), Paragraph("Scribe brings named styles, an outline, flowing pages and familiar macOS editing together. This document exercises the same layout used for PDF and printing.")]
            document.model.insertTable(rows: 3, columns: 3, after: document.model.paragraphs.last!.id)
            let cellValues = ["Section", "Purpose", "Status", "Structure", "Styles and outline", "Ready", "Layout", "Flowing pages", "Ready"]
            var cellIndex = 0
            for index in document.model.sections[0].paragraphs.indices where document.model.sections[0].paragraphs[index].tableCell != nil {
                document.model.sections[0].paragraphs[index].runs = [TextRun(cellValues[cellIndex])]; cellIndex += 1
            }
            if let tableID = document.model.tables.first?.id {
                var cell = TableCellStyle(row: 2, column: 1)
                cell.background = "#E7EFF8"; cell.padding = 10; cell.borderWidth = 1; cell.borderColor = "#456789"; cell.verticalAlignment = .center
                try document.model.setCellStyles([cell], tableID: tableID)
                try document.model.setMinimumRowHeight(42, row: 2, tableID: tableID)
                try document.model.mergeTableCells(tableID: tableID, region: TableMerge(row: 1, column: 0, rowSpan: 1, columnSpan: 2))
            }
            let chart = NSImage(size: NSSize(width: 240, height: 80), flipped: false) { rect in
                NSColor(white: 0.96, alpha: 1).setFill(); rect.fill()
                NSColor(srgbRed: 0.25, green: 0.38, blue: 0.49, alpha: 1).setFill()
                for (index, width) in [90.0, 150.0, 210.0].enumerated() { NSRect(x: 12, y: 10 + Double(index) * 22, width: width, height: 12).fill() }
                return true
            }
            if let tiff = chart.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                var run = TextRun("\u{FFFC}"); run.image = InlineImage(data: png, fileExtension: "png", width: 240, height: 80, altText: "Three horizontal bars of increasing length")
                document.model.sections[0].paragraphs[document.model.paragraphs.count - 1].runs = [run]
            }
            let series = UUID()
            let listSamples: [(String, ListDescriptor?)] = [
                ("Numbered item", .init(kind: .upperRoman, start: 4, seriesID: series)),
                ("Supporting detail", .init(kind: .lowerAlpha, level: 1, seriesID: series)),
                ("Body text between list items.", nil),
                ("Continued item", .init(kind: .upperRoman, start: 4, seriesID: series)),
                ("Restarted item", .init(kind: .upperRoman, start: 9, seriesID: series, restart: true))
            ]
            for (text, list) in listSamples { var p = Paragraph(text); p.list = list; document.model.sections[0].paragraphs.append(p) }
            document.model.sections[0].pageNumbering = PageNumbering()
            for i in 1...80 { document.model.sections[0].paragraphs.append(Paragraph("Paragraph \(i). " + String(repeating: "Professional documents need clear structure and dependable editing. ", count: 6))) }
            let reviewed = document.model.paragraphs[2]
            let lastIndex = document.model.sections[0].paragraphs.count - 1
            let finalText = document.model.sections[0].paragraphs[lastIndex].text
            document.model.sections[0].paragraphs[lastIndex].runs = [TextRun(finalText, link: DocumentLink.paragraph(reviewed.id))]
            if let bookmark = document.model.addParagraphBookmark(name: "Writing_workspace", paragraphID: document.model.paragraphs[3].id) {
                document.model.sections[0].paragraphs[lastIndex - 1].runs[0].link = DocumentLink.bookmark(bookmark)
            }
            document.model.comments = [Comment(anchor: TextAnchor(paragraphID: reviewed.id, offset: 0, length: (reviewed.text as NSString).length), text: "Check the section structure before sharing this draft.\nThe outline and page layout should agree.", author: "Scribe reviewer")]
            var resolvedComment = Comment(anchor: TextAnchor(paragraphID: document.model.paragraphs[3].id, offset: 0, length: 6), text: "Checked in an earlier review.", author: "Copy editor")
            resolvedComment.resolved = true; document.model.comments.append(resolvedComment)
            documents.addDocument(document); document.makeWindowControllers(); document.showWindows()
            guard let controller = document.editorController else { fatalError("Missing editor") }
            controller.editor.jump(to: document.model.paragraphs[1].id)
            controller.addTableOfContents(title: "Contents", maximumLevel: 3)
            controller.editor.paginate()
            controller.commentsSidebar.isHidden = false
            controller.commentsSidebar.reload(document.snapshot(), selecting: document.model.comments[0].id)
            controller.zoomPicker.selectItem(withTitle: "75%"); controller.changeZoom()
            controller.window?.makeFirstResponder(controller.editor.textViews[0])
            controller.selectComment(document.model.comments[0])
            let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCRIBE_SMOKE_OUTPUT"] ?? NSTemporaryDirectory())
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                document.save(to: folder.appendingPathComponent("Smoke.scribe"), ofType: ScribeFileDocument.typeName, for: .saveOperation) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            guard !document.isDocumentEdited else { throw DocumentError.invalid("native save did not clear the edited state") }
            print("Native document save completed"); fflush(stdout)
            try PrintRenderer(editor: controller.editor).exportPDF(to: folder.appendingPathComponent("Smoke.pdf"), title: "Scribe Smoke Test", author: "Scribe")
            let exportModel = document.snapshot(), wordBytes = try DOCX.encode(document.snapshot())
            try wordBytes.write(to: folder.appendingPathComponent("Smoke.docx"))
            let imported = try DOCX.decode(wordBytes).document
            guard imported.plainText == exportModel.plainText, imported.comments.map(\.text) == exportModel.comments.map(\.text), imported.comments.map(\.resolved) == exportModel.comments.map(\.resolved), imported.bookmarks.map(\.name) == exportModel.bookmarks.map(\.name) else {
                throw DocumentError.invalid("release-build DOCX import did not preserve text and review data")
            }
            try PrintRenderer(editor: controller.editor).exportPDF(to: folder.appendingPathComponent("Selected-pages.pdf"), title: "Selected pages", author: "Scribe", pages: [0, controller.editor.textViews.count - 1], subject: "Range export", keywords: ["Scribe", "validation"])
            let pages = controller.editor.textViews.count
            guard pages > 1 else { fatalError("Text did not paginate") }
            try await Task.sleep(nanoseconds: 500_000_000)
            controller.window?.displayIfNeeded()
            if let view = controller.window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: folder.appendingPathComponent("Scribe.png")) }
            }
            controller.window?.appearance = NSAppearance(named: .darkAqua)
            controller.window?.contentView?.needsDisplay = true
            controller.window?.displayIfNeeded()
            if let view = controller.window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: folder.appendingPathComponent("Scribe-Dark.png")) }
            }
            print("Scribe launch smoke test passed: \(pages) pages, native save, DOCX re-import, PDF and window rendering")
            NSApp.terminate(nil)
        } catch { fputs("Smoke test failed: \(error)\n", stderr); exit(1) }
    }
}
#endif
