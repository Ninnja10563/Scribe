import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import DocumentCore

/// Shared author identities across body and notes. Office annotation numbers are
/// scoped to a reader; native identities are fresh and never collide with content.
final class DOCXRevisionImportContext {
    var failure: String?
    private var authors: [String: RevisionAuthor] = [:]
    private var identities: [String: RevisionIdentity] = [:]
    private let dates = ISO8601DateFormatter()
    private let fractionalDates: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions.insert(.withFractionalSeconds); return value
    }()
    func identity(_ attributes: [String: String], kind: String, scope: UUID) throws -> RevisionIdentity {
        guard let number = wordAttribute(attributes, "id"), Int(number) != nil,
              let name = wordAttribute(attributes, "author"),
              let rawDate = wordAttribute(attributes, "date"),
              let date = dates.date(from: rawDate) ?? fractionalDates.date(from: rawDate) else {
            throw DocumentError.invalid("Preserving DOCX revisions requires an author, numeric identifier and valid date.")
        }
        try DocumentMetadata.validateText(name)
        let author = authors[name] ?? RevisionAuthor(name: name); authors[name] = author
        let key = "\(scope)/\(kind)/\(number)"
        if let existing = identities[key] {
            guard existing.author == author, existing.date == date else {
                throw DocumentError.invalid("Conflicting DOCX revision metadata.")
            }
            return existing
        }
        guard identities.count < 100_000 else { throw DocumentError.invalid("Too many DOCX revisions.") }
        let value = RevisionIdentity(author: author, date: date); identities[key] = value; return value
    }
}

/// Focused revision state layered onto WordReader. Unsupported structural review
/// fails in this internal mode instead of silently flattening the imported copy.
final class DOCXRevisionReader {
    private let context: DOCXRevisionImportContext
    private let scope = UUID()
    private var elements: [(String?, String)] = []
    private var insertion: RevisionIdentity?, deletion: RevisionIdentity?
    private(set) var paragraphBreak: RunReview?
    private var previousDepth = 0
    private var previous = TextFormatting()
    private var formattingIdentity: RevisionIdentity?
    init(_ context: DOCXRevisionImportContext) { self.context = context }

    func start(_ name: String, namespace: String?, attributes: [String: String],
               inRun: Bool, run: inout TextRun, parser: XMLParser) -> Bool {
        let parent = elements.last
        elements.append((namespace, name))
        do {
            guard elements.count <= 4096 else { throw DocumentError.invalid("DOCX XML nesting is too deep.") }
            if previousDepth > 0 {
                previousDepth += 1
                guard namespace == DOCX.wordNS, ["rPr", "rFonts", "b", "i", "strike", "color", "sz", "u", "shd", "vertAlign"].contains(name) else {
                    throw DocumentError.invalid("Unsupported nested DOCX formatting history.")
                }
                applyRun(name, attributes, &previous)
                return true
            }
            let formatting = inRun && !(run.review?.formatting.isEmpty ?? true)
            if formatting && ((namespace == DOCX.wordNS && ["drawing", "pict", "footnoteReference", "endnoteReference"].contains(name)) || (namespace == DOCXEquations.namespace && name == "oMath")) {
                throw DocumentError.invalid("Preserving DOCX object formatting revisions is not yet supported.")
            }
            if hasActiveRevision && namespace == DOCX.wordNS && name == "pict" {
                throw DocumentError.invalid("Preserving legacy drawing revisions is not yet supported.")
            }
            guard namespace == DOCX.wordNS else { return false }
            if ["pPrChange", "tblPrChange", "trPrChange", "tcPrChange", "tblGridChange", "sectPrChange", "moveFrom", "moveTo", "cellIns", "cellDel", "cellMerge", "numberingChange"].contains(name) || name.hasPrefix("customXmlIns") || name.hasPrefix("customXmlDel") || name.hasPrefix("customXmlMove") {
                throw DocumentError.invalid("Preserving this DOCX structural revision is not yet supported.")
            }
            switch name {
            case "p": paragraphBreak = nil
            case "ins", "del":
                if !inRun, parent?.0 == DOCX.wordNS, parent?.1 == "rPr", elements.count >= 3,
                   elements[elements.count - 3].0 == DOCX.wordNS, elements[elements.count - 3].1 == "pPr" {
                    var review = paragraphBreak ?? RunReview()
                    guard name == "ins" ? review.insertion == nil : review.deletion == nil else {
                        throw DocumentError.invalid("Duplicate DOCX paragraph-mark revision.")
                    }
                    let identity = try context.identity(attributes, kind: name, scope: scope)
                    if name == "ins" { review.insertion = identity } else { review.deletion = identity }
                    paragraphBreak = review; return true
                }
                guard parent?.0 == DOCX.wordNS, ["p", "hyperlink", "ins", "del"].contains(parent?.1 ?? ""),
                      name == "ins" ? insertion == nil : deletion == nil else {
                    throw DocumentError.invalid("Unsupported nested or structural DOCX revision.")
                }
                let identity = try context.identity(attributes, kind: name, scope: scope)
                if name == "ins" { insertion = identity } else { deletion = identity }
                return true
            case "rPrChange":
                guard inRun, parent?.0 == DOCX.wordNS, parent?.1 == "rPr", run.review?.formatting.isEmpty ?? true else {
                    throw DocumentError.invalid("Unsupported DOCX run formatting history.")
                }
                formattingIdentity = try context.identity(attributes, kind: name, scope: scope)
                previous = TextFormatting(); previousDepth = 1
                return true
            case "delText":
                guard deletion != nil else { throw DocumentError.invalid("Deleted DOCX text has no revision container.") }
            default: break
            }
            return false
        } catch {
            context.failure = error.localizedDescription; parser.abortParsing(); return true
        }
    }

    func end(_ name: String, namespace: String?, run: inout TextRun) -> Bool {
        defer { if !elements.isEmpty { elements.removeLast() } }
        if previousDepth > 0 {
            previousDepth -= 1
            if previousDepth == 0, let identity = formattingIdentity {
                var review = run.review ?? RunReview()
                review.formattingBase = previous
                review.formatting = [.init(identity: identity, before: previous, after: run.format)]
                run.review = review; formattingIdentity = nil
            }
            return true
        }
        guard namespace == DOCX.wordNS else { return false }
        if name == "ins" { insertion = nil; return true }
        if name == "del" { deletion = nil; return true }
        return false
    }

    var hasActiveRevision: Bool { insertion != nil || deletion != nil }
    func failObject(_ parser: XMLParser) {
        context.failure = "A revised DOCX object could not be imported without losing its content."
        parser.abortParsing()
    }
    var collectingHistory: Bool { previousDepth > 0 }
    func apply(to run: inout TextRun) {
        guard insertion != nil || deletion != nil else { return }
        var review = run.review ?? RunReview()
        review.insertion = insertion; review.deletion = deletion; run.review = review
    }
}
