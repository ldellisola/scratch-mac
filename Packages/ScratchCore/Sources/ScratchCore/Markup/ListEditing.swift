import Foundation

/// What Return, Tab, ⇧Tab, ⇧⌘L and a click on a checkbox do to a list (spec §6.4, "List behaviour").
///
/// A rule reads the paragraphs that cover the selection and answers with a ``TextEdit``, or with nil when it is not a
/// list action and the text view keeps its default. `paragraphs` is the text of those whole lines (line breaks
/// included) and `start` is the document offset of the first one, in UTF-16 units. The text view never passes the whole
/// note. A caller checks that the selection is not in a fenced code block first: nothing here knows about fences.
public enum ListEditing {
    /// One level of indentation [call, the spec left it to the builder].
    public static let indentUnit = "  "

    private static let bulletMarker = "- "
    private static let checkboxMarker = "[ ] "

    // MARK: Return

    /// Return at the caret of a bullet or checkbox line.
    ///
    /// - An item with text: a new line follows with the same indentation and an unticked marker (`- ` or `[ ] `, also
    ///   after a ticked item). Text after the caret moves to the new item.
    /// - An empty item: at level 1 or deeper it loses one indent unit, at level 0 its marker goes and the list ends,
    ///   which leaves an empty line.
    /// - Nil, so Return is the text view's own: a selection, a caret before the end of the marker (in the indentation
    ///   or inside `- `), and a line that is not a list item.
    public static func newline(paragraphs: String, start: Int, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let text = ParagraphLines(paragraphs, start: start)
        guard let index = text.lineIndex(containing: selection.location), let item = text.listItem(at: index) else {
            return nil
        }
        let caret = selection.location
        guard caret >= item.content.location else { return nil }
        let lineStart = text.lineStart(index)

        if item.content.length == 0 {
            if item.level > 0 {
                return TextEdit(
                    range: NSRange(location: lineStart, length: indentUnit.utf16.count), replacement: "",
                    selection: NSRange(location: caret - indentUnit.utf16.count, length: 0))
            }
            return TextEdit(
                range: NSRange(location: lineStart, length: text.lineEnd(index) - lineStart), replacement: "",
                selection: NSRange(location: lineStart, length: 0))
        }

        let indentation = String(repeating: " ", count: item.marker.location - lineStart)
        let replacement = "\n" + indentation + (item.isCheckbox ? checkboxMarker : bulletMarker)
        return TextEdit(
            range: NSRange(location: caret, length: 0), replacement: replacement,
            selection: NSRange(location: caret + replacement.utf16.count, length: 0))
    }

    // MARK: Tab and ⇧Tab

    /// Tab: adds one indent unit at the start of every list line of the selection. Nil when none of its lines is a
    /// list line, so Tab inserts a tab. The selection moves with the text.
    public static func indent(paragraphs: String, start: Int, selection: NSRange) -> TextEdit? {
        reindent(paragraphs: paragraphs, start: start, selection: selection, outdenting: false)
    }

    /// ⇧Tab: removes up to one indent unit of leading spaces from every list line of the selection. Nil when none of
    /// its lines is a list line, so ⇧Tab does its default. A list line with nothing to remove is still a list action:
    /// the edit then replaces nothing with nothing and keeps the selection (`range.length` and `replacement.count` are
    /// 0), and a caller may skip it.
    public static func outdent(paragraphs: String, start: Int, selection: NSRange) -> TextEdit? {
        reindent(paragraphs: paragraphs, start: start, selection: selection, outdenting: true)
    }

    private static func reindent(paragraphs: String, start: Int, selection: NSRange, outdenting: Bool) -> TextEdit? {
        let text = ParagraphLines(paragraphs, start: start)
        guard let touched = text.touchedLines(by: selection) else { return nil }
        var changes: [ParagraphLines.Change] = []
        var foundListLine = false
        for index in touched {
            guard let item = text.listItem(at: index) else { continue }
            foundListLine = true
            let lineStart = text.lineStart(index)
            if outdenting {
                let removed = min(indentUnit.utf16.count, item.marker.location - lineStart)
                if removed > 0 { changes.append(.init(location: lineStart, removed: removed, inserted: [])) }
            } else {
                changes.append(.init(location: lineStart, removed: 0, inserted: Array(indentUnit.utf16)))
            }
        }
        guard foundListLine else { return nil }
        return text.edit(applying: changes, selection: selection)
    }

    // MARK: ⇧⌘L

    /// ⇧⌘L on the lines of the selection (the caret's line when there is no selection).
    ///
    /// - When every line with text in it is a checkbox, the `[?] ` markers go.
    /// - Otherwise each line that is not a checkbox becomes one: a bullet's `- ` is replaced with `[ ] `, and any other
    ///   line gets `[ ] ` after its indentation. A blank line gets none when the selection has a line with text, so a
    ///   selection over paragraphs leaves the gaps between them empty. A caret on a blank line still gets its box.
    /// - A token line (`AttachmentToken`, the line of an attachment) is never changed: a box in front of the token would
    ///   make it text and the picture would be gone. It is not a line with text for the rules above, and it keeps the
    ///   blank lines around it empty like one. The edit is empty when the selection holds nothing else.
    public static func toggleChecklist(paragraphs: String, start: Int, selection: NSRange) -> TextEdit {
        let text = ParagraphLines(paragraphs, start: start)
        guard let touched = text.touchedLines(by: selection) else {
            return TextEdit(
                range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
        }
        let items = touched.map { text.listItem(at: $0) }
        let isToken = touched.map { text.isAttachmentLine($0) }
        // The lines that are not blank, a token line included: with one of them there, a blank line keeps to itself.
        let hasContent = touched.contains { !text.isBlank($0) }
        let withText = touched.filter { !text.isBlank($0) && !isToken[$0 - touched.lowerBound] }
        let allChecked = !withText.isEmpty && withText.allSatisfy { items[$0 - touched.lowerBound]?.isCheckbox == true }

        var changes: [ParagraphLines.Change] = []
        for index in touched {
            if isToken[index - touched.lowerBound] { continue }
            let item = items[index - touched.lowerBound]
            if allChecked {
                // `[?]` and the space after it.
                if let item, item.isCheckbox {
                    changes.append(.init(location: item.marker.location, removed: item.marker.length + 1, inserted: []))
                }
                continue
            }
            if item?.isCheckbox == true { continue }
            if hasContent, text.isBlank(index) { continue }
            let box = Array(checkboxMarker.utf16)
            if let item {
                // The bullet's `-` and the space after it.
                changes.append(.init(location: item.marker.location, removed: item.marker.length + 1, inserted: box))
            } else {
                changes.append(.init(location: text.firstNonSpace(of: index), removed: 0, inserted: box))
            }
        }
        return text.edit(applying: changes, selection: selection)
    }

    // MARK: ⇧⌘U

    /// ⇧⌘U (Format > Mark as Checked) on the checklist lines under the selection (the caret's line when there is no
    /// selection). When any of them is open, every open one is ticked (`[ ]` to `[x]`, the ticked ones stay as they are,
    /// `[X]` too). When all are ticked, they are all unticked. Lines that are not checkboxes (a bullet, a plain line, a token
    /// line, and `- [ ] a`, which is a bullet) have no say and are left alone. The edit is one character for each box, and the
    /// selection stays where it was.
    ///
    /// Nil when none of the lines is a checkbox, so a caller beeps. A caller checks that the selection is not in a fenced
    /// code block first.
    public static func toggleCheckmarks(paragraphs: String, start: Int, selection: NSRange) -> TextEdit? {
        let text = ParagraphLines(paragraphs, start: start)
        guard let touched = text.touchedLines(by: selection) else { return nil }
        var boxes: [(marker: NSRange, isChecked: Bool)] = []
        for index in touched {
            guard let item = text.listItem(at: index), case .checkbox(let isChecked, _) = item.span.kind else {
                continue
            }
            boxes.append((item.marker, isChecked))
        }
        guard !boxes.isEmpty else { return nil }

        let ticking = boxes.contains { !$0.isChecked }
        let mark = Array((ticking ? "x" : " ").utf16)
        let changes = boxes.compactMap { box -> ParagraphLines.Change? in
            // Only the boxes that change: with some open, the ticked ones stay as typed (`[X]` too).
            guard box.isChecked != ticking else { return nil }
            return ParagraphLines.Change(location: box.marker.location + 1, removed: 1, inserted: mark)
        }
        return text.edit(applying: changes, selection: selection)
    }

    // MARK: A click on the box

    /// A click on a checkbox: flips the `[ ]` or `[x]` at the start of `line` (one line, without its line break, whose
    /// first character is at document offset `lineStart`). Nil when the line is not a checkbox. The selection is
    /// passed through unchanged, so the caret stays where it was. `[X]` counts as ticked and becomes `[ ]`.
    public static func toggleCheckmark(line: String, lineStart: Int, selection: NSRange) -> TextEdit? {
        for span in MarkupParser.parseLine(line, at: lineStart) {
            guard case .checkbox(let checked, _) = span.kind else { continue }
            return TextEdit(
                range: NSRange(location: span.markers[0].location + 1, length: 1),
                replacement: checked ? " " : "x", selection: selection)
        }
        return nil
    }
}
