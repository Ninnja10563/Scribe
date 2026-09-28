#if canImport(AppKit)
import AppKit
import DocumentCore
import ImportExport

@main struct ScribeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let documents = ScribeDocumentController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        MainMenu.install()
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--smoke-test") { Task { await smokeTest() }; return }
        Task {
            let snapshots = (try? await ScribeFileDocument.recovery.snapshots()) ?? []
            for snapshot in snapshots {
                let alert = NSAlert(); alert.messageText = "Recover \(snapshot.document.title)?"
                alert.informativeText = "Scribe found a recovery copy from \(snapshot.savedAt.formatted()). It opens as an unsaved document; the original is kept intact."
                alert.addButton(withTitle: "Recover Copy"); alert.addButton(withTitle: "Keep for Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    let document = ScribeFileDocument(); document.model = snapshot.document
                    document.model.title += " — Recovered"
                    documents.addDocument(document); document.makeWindowControllers(); document.showWindows(); document.updateChangeCount(.changeDone)
                }
            }
            if documents.documents.isEmpty { _ = try? documents.openUntitledDocumentAndDisplay(true) }
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for file in filenames {
            let url = URL(fileURLWithPath: file)
            if url.pathExtension == "scribe" {
                documents.openDocument(withContentsOf: url, display: true) { _, _, error in if let error { NSApp.presentError(error) } }
            } else { documents.importDocument(url) }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Scribe", .applicationVersion: "0.2.0", .credits: NSAttributedString(string: "A native document workspace for macOS.\nEarly development release.")])
    }
    private func smokeTest() async {
        do {
            let document = ScribeFileDocument()
            document.model.sections[0].paragraphs = [Paragraph("Scribe", style: "title"), Paragraph("A native document workspace", style: "subtitle"), Paragraph("A considered place to write", style: "heading1"), Paragraph("Scribe brings named styles, an outline, flowing pages and familiar macOS editing together. This document exercises the same layout used for PDF and printing.")]
            document.model.insertTable(rows: 3, columns: 3, after: document.model.paragraphs.last!.id)
            let cellValues = ["Section", "Purpose", "Status", "Structure", "Styles and outline", "Ready", "Layout", "Flowing pages", "Ready"]
            var cellIndex = 0
            for index in document.model.sections[0].paragraphs.indices where document.model.sections[0].paragraphs[index].tableCell != nil {
                document.model.sections[0].paragraphs[index].runs = [TextRun(cellValues[cellIndex])]; cellIndex += 1
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
            document.model.sections[0].pageNumbering = PageNumbering()
            for i in 1...80 { document.model.sections[0].paragraphs.append(Paragraph("Paragraph \(i). " + String(repeating: "Professional documents need clear structure and dependable editing. ", count: 6))) }
            documents.addDocument(document); document.makeWindowControllers(); document.showWindows()
            guard let controller = document.editorController else { fatalError("Missing editor") }
            controller.editor.paginate()
            controller.window?.makeFirstResponder(controller.editor.textViews[0])
            let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCRIBE_SMOKE_OUTPUT"] ?? NSTemporaryDirectory())
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try NativeFormat.save(document.snapshot(), to: folder.appendingPathComponent("Smoke.scribe"))
            try PrintRenderer(editor: controller.editor).exportPDF(to: folder.appendingPathComponent("Smoke.pdf"), title: "Scribe Smoke Test", author: "Scribe")
            try DOCX.encode(document.snapshot()).write(to: folder.appendingPathComponent("Smoke.docx"))
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
            print("Scribe launch smoke test passed: \(pages) pages, native save, PDF and window rendering")
            NSApp.terminate(nil)
        } catch { fputs("Smoke test failed: \(error)\n", stderr); exit(1) }
    }
}
#else
import Foundation
@main struct ScribeMain {
    static func main() {
        print("Scribe is a native macOS application. Build on macOS 14 or later. The document core and import/export tests run on Linux with swift test.")
    }
}
#endif
