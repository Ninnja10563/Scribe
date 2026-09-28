#if canImport(AppKit)
import AppKit
import DocumentCore

extension PaginatedEditor {
    func applyStyle(_ id: String) {
        guard let owner else { return }
        let selection = activeTextView.selectedRange()
        let range = (storage.string as NSString).paragraphRange(for: selection)
        owner.performEdit("Apply Style") { model in
            var offset = 0
            for i in model.sections[0].paragraphs.indices {
                let count = (model.sections[0].paragraphs[i].text as NSString).length + 1 + (model.sections[0].paragraphs[i].pageBreakBefore ? 1 : 0)
                if NSIntersectionRange(NSRange(location: offset, length: count), range).length > 0 || (selection.length == 0 && selection.location >= offset && selection.location < offset + count) {
                    model.sections[0].paragraphs[i].styleID = id
                    model.sections[0].paragraphs[i].formatting = nil
                }
                offset += count
            }
        }
    }
    func applyList(_ list: ListDescriptor?) {
        let selection = activeTextView.selectedRange()
        owner?.performEdit("List") { model in
            var offset = 0
            for i in model.sections[0].paragraphs.indices {
                let count = (model.sections[0].paragraphs[i].text as NSString).length + 1
                if (selection.length == 0 && selection.location >= offset && selection.location < offset + count)
                    || NSIntersectionRange(NSRange(location: offset, length: count), selection).length > 0 {
                    model.sections[0].paragraphs[i].list = list
                }
                offset += count
            }
        }
    }
}
#endif
