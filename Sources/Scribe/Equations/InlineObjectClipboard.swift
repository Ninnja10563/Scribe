#if canImport(AppKit)
import AppKit
import DocumentCore

/// Optional, bounded JSON accompanies standard RTFD. No object unarchiving is used.
@MainActor enum InlineObjectClipboard {
    static let type = NSPasteboard.PasteboardType("org.scribe.inline-objects.v1")
    private struct Entry: Codable {
        let location: Int
        let equation: Equation?
        let image: InlineImage?
    }
    private struct Payload: Codable {
        let version: Int
        let text: String
        let objects: [Entry]
    }
    static func encode(_ value: NSAttributedString) throws -> Data {
        var objects: [Entry] = []
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
            let equation = (attributes[.scribeEquation] as? Data).flatMap { try? JSONDecoder().decode(Equation.self, from: $0) }
            let image = (attributes[.scribeImage] as? Data).flatMap { try? JSONDecoder().decode(InlineImage.self, from: $0) }
            guard equation != nil || image != nil else { return }
            for location in range.location..<NSMaxRange(range) where (value.string as NSString).character(at: location) == 0xFFFC {
                objects.append(Entry(location: location, equation: equation, image: image))
            }
        }
        let payload = Payload(version: 1, text: value.string, objects: objects)
        try validate(payload)
        let data = try JSONEncoder().encode(payload)
        guard data.count <= NativeFormat.maximumBytes else { throw DocumentError.tooLarge }
        return data
    }
    static func restore(_ data: Data, in value: NSAttributedString) throws -> NSAttributedString {
        guard data.count <= NativeFormat.maximumBytes else { throw DocumentError.tooLarge }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        try validate(payload)
        guard payload.text == value.string else { throw DocumentError.invalid("clipboard text and objects do not match") }
        let result = NSMutableAttributedString(attributedString: value)
        for object in payload.objects {
            let range = NSRange(location: object.location, length: 1)
            result.removeAttribute(.scribeEquation, range: range); result.removeAttribute(.scribeImage, range: range)
            if let equation = object.equation {
                result.addAttributes([.attachment: EquationProjection.attachment(equation), .scribeEquation: try JSONEncoder().encode(equation)], range: range)
            } else if let image = object.image, let attachment = ImageProjection.attachment(image) {
                result.addAttributes([.attachment: attachment, .scribeImage: try JSONEncoder().encode(image)], range: range)
            }
        }
        return result
    }
    private static func validate(_ payload: Payload) throws {
        let text = payload.text as NSString
        guard payload.version == 1, payload.objects.count <= 10000,
              payload.text.utf8.count <= NativeFormat.maximumBytes,
              Set(payload.objects.map(\.location)).count == payload.objects.count else { throw DocumentError.invalid("invalid clipboard object list") }
        var check = ScribeDocument(); check.sections[0].paragraphs[0].runs = []
        for object in payload.objects {
            guard object.location >= 0, object.location < text.length, text.character(at: object.location) == 0xFFFC,
                  (object.equation != nil) != (object.image != nil) else { throw DocumentError.invalid("invalid clipboard object position") }
            var run = TextRun("\u{FFFC}"); run.equation = object.equation; run.image = object.image
            check.sections[0].paragraphs[0].runs.append(run)
        }
        try NativeFormat.validate(check)
    }
}
#endif
