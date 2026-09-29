import XCTest
import DocumentCore
@testable import ImportExport

final class MetadataTests: XCTestCase {
    func testIndependentMetadataFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "DocumentProperties", withExtension: "docx", subdirectory: "Fixtures"))
        let imported = try DOCX.decode(Data(contentsOf: url))
        XCTAssertEqual(imported.document.title, "Independent résumé & 東京")
        XCTAssertEqual(imported.document.author, "Zoë Example")
        XCTAssertEqual(imported.document.language, "en-GB")
        XCTAssertTrue(imported.document.plainText.contains("Colour is checked using British English."))
    }
    func testCorePropertiesAndSpellingDefaultRoundTrip() throws {
        var document = ScribeDocument()
        try document.setMetadata(title: "Résumé 東京 & <research>", author: "Zoë \"Writer\"", language: "fr_CA")
        let bytes = try DOCX.encode(document), parts = try ZipArchive.decode(bytes)
        let core = String(decoding: parts["docProps/core.xml"]!, as: UTF8.self)
        let styles = String(decoding: parts["word/styles.xml"]!, as: UTF8.self)
        XCTAssertTrue(core.contains("&amp; &lt;research&gt;"))
        XCTAssertTrue(styles.contains("<w:lang w:val=\"fr-CA\"/>"))
        let imported = try DOCX.decode(bytes)
        XCTAssertEqual(imported.document.title, document.title)
        XCTAssertEqual(imported.document.author, document.author)
        XCTAssertEqual(imported.document.language, "fr-CA")
        XCTAssertTrue(imported.warnings.isEmpty)
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent("DocumentProperties.docx"))
        }
    }
    func testMetadataRelationshipAndNamespaceAliasesAreRespected() throws {
        var parts = try ZipArchive.decode(DOCX.encode(ScribeDocument()))
        parts["docProps/core.xml"] = nil
        parts["properties/custom.xml"] = Data("<p:coreProperties xmlns:p=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:d=\"http://purl.org/dc/elements/1.1/\"><d:title><![CDATA[Independent title & text]]></d:title><d:creator>Author</d:creator><d:language>de</d:language></p:coreProperties>".utf8)
        parts["_rels/.rels"] = Data(String(decoding: parts["_rels/.rels"]!, as: UTF8.self).replacingOccurrences(of: "docProps/core.xml", with: "properties/custom.xml").utf8)
        parts["word/styles.xml"] = Data("<w:styles xmlns:w=\"\(DOCX.wordNS)\"/>".utf8)
        let imported = try DOCX.decode(ZipArchive.encode(parts))
        XCTAssertEqual(imported.document.title, "Independent title & text")
        XCTAssertEqual(imported.document.author, "Author"); XCTAssertEqual(imported.document.language, "de")
    }
    func testAutomaticLanguageOmitsWordSpellingOverride() throws {
        var document = ScribeDocument(); document.language = "und"
        let bytes = try DOCX.encode(document), parts = try ZipArchive.decode(bytes)
        XCTAssertFalse(String(decoding: parts["word/styles.xml"]!, as: UTF8.self).contains("<w:lang"))
        XCTAssertEqual(try DOCX.decode(bytes).document.language, "und")
    }
}
