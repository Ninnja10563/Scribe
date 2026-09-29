#if canImport(AppKit)
import AppKit
import DocumentCore

extension PaginatedEditor {
    func selectedParagraphIndices() -> Set<Int> {
        let selection = activeTextView.selectedRange()
        var offset = 0, selected: Set<Int> = []
        for (index, component) in storage.string.components(separatedBy: "\n").enumerated() {
            let length = (component as NSString).length + 1
            let range = NSRange(location: offset, length: length)
            if selection.length == 0 ? NSLocationInRange(selection.location, range) : NSIntersectionRange(selection, range).length > 0 { selected.insert(index) }
            offset += length
        }
        return selected
    }
    func applyStyle(_ id: String) {
        let indices = selectedParagraphIndices()
        owner?.performEdit("Apply Style") { model in
            for index in indices where model.sections[0].paragraphs.indices.contains(index) {
                model.sections[0].paragraphs[index].styleID = id
                model.sections[0].paragraphs[index].formatting = nil
            }
        }
    }
    func applyList(_ list: ListDescriptor?) {
        let indices = selectedParagraphIndices()
        let first = indices.min()
        owner?.performEdit("List") { model in
            for index in indices where model.sections[0].paragraphs.indices.contains(index) {
                var descriptor = list
                if index != first { descriptor?.restart = nil }
                model.sections[0].paragraphs[index].list = descriptor
            }
        }
    }
}
#endif
