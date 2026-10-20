import Foundation

@testable import ScratchCore

// Helpers for the tests of the editing rules (`ListEditing`, `InlineEditing`). They stand in for the text view: they
// cut out the paragraphs the app would pass, apply the `TextEdit` that comes back, and show the selection with `|`.

/// A text with its selection marked by `|`: one bar is a caret, two bars are the start and the end of a selection.
struct MarkedText: Equatable {
    let text: String
    let selection: NSRange

    init(text: String, selection: NSRange) {
        self.text = text
        self.selection = selection
    }

    init(_ marked: String) {
        let units = Array(marked.utf16)
        let bar = Array("|".utf16)[0]
        var kept: [UInt16] = []
        var bars: [Int] = []
        for unit in units {
            if unit == bar {
                bars.append(kept.count)
            } else {
                kept.append(unit)
            }
        }
        precondition(bars.count == 1 || bars.count == 2, "a marked text needs one or two bars: \(marked)")
        self.text = String(decoding: kept, as: UTF16.self)
        self.selection = NSRange(location: bars[0], length: (bars.last ?? bars[0]) - bars[0])
    }

    /// The text with `|` at the caret, or at both ends of the selection.
    var marked: String {
        var units = Array(text.utf16)
        let bar = Array("|".utf16)[0]
        units.insert(bar, at: NSMaxRange(selection))
        if selection.length > 0 { units.insert(bar, at: selection.location) }
        return String(decoding: units, as: UTF16.self)
    }
}

/// What the app passes to a rule: the whole lines that cover the selection, and where they start in the document.
func coveringParagraphs(of text: String, selection: NSRange) -> (paragraphs: String, start: Int) {
    let string = text as NSString
    let range = string.paragraphRange(for: selection)
    return (string.substring(with: range), range.location)
}

/// What the text view does with an edit: replace the range, then select.
func apply(_ edit: TextEdit, to text: String) -> (String, NSRange) {
    ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
}

/// The signature of `ListEditing.newline`, `indent` and `outdent`.
typealias ParagraphRule = (_ paragraphs: String, _ start: Int, _ selection: NSRange) -> TextEdit?

/// Runs a rule on a marked text the way the app does, and returns the marked text after the edit, or nil when the
/// rule has nothing to do ("let the text view do its default").
func result(of marked: String, _ rule: ParagraphRule) -> String? {
    let input = MarkedText(marked)
    let cut = coveringParagraphs(of: input.text, selection: input.selection)
    guard let edit = rule(cut.paragraphs, cut.start, input.selection) else { return nil }
    let (text, selection) = apply(edit, to: input.text)
    return MarkedText(text: text, selection: selection).marked
}
