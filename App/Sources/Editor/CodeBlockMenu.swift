import AppKit
import ScratchCode
import ScratchCore

/// What the owner can ask of a code block from the menu of its label (spec §6.4 "Code highlighting", plan 4 task 7).
enum CodeBlockAction: Equatable {
    /// Names the language on the block's opening fence: `bash` becomes `python`.
    case setLanguage(CodeLanguage)
    /// Names the block `text`: it stays a tinted block and is not coloured.
    case plainText
    /// Takes both fence lines away and keeps the lines of code exactly as they are.
    case notCode
}

/// What a menu item of the label menu stands for: the action, and the block it is for. `NoteTextView.chooseCodeBlockAction`
/// reads it off the item's `representedObject`.
struct CodeBlockChoice {
    let action: CodeBlockAction
    /// The block, from the start of its opening fence line to the end of its closing one, as it was when the menu was made.
    let block: NSRange
}

/// The menu of a code block's language label, and the edits that its items make (`NoteTextView.mouseDown` opens it, and
/// `NoteTextView.applyCodeBlockAction` applies an edit through `apply(_:)`, one undo step).
///
/// The menu lists the 17 languages (the current one ticked), a separator, "Plain Text" and "Not Code". The edits only ever
/// touch the fence lines: a language change replaces the name on the opening fence and nothing else, and "Not Code"
/// replaces the block with its own lines of code, so no character of the code changes (plan 4 "Characters are never
/// changed by highlighting or rendering").
enum CodeBlockMenu {
    /// The fence name that makes a block plain text: not a language, so it is tinted and not coloured, and its label says
    /// `text`.
    static let plainTextName = "text"

    /// The menu for the block at `block`, whose language is `current` (nil for none, as for a block named `text`). Its items
    /// are sent to `target`, which is not asked to validate them: the menu does not enable its items by itself.
    static func menu(for block: NSRange, current: CodeLanguage?, target: NoteTextView) -> NSMenu {
        let menu = NSMenu(title: "Language")
        menu.autoenablesItems = false
        let isPlainText = namesPlainText(block: block, in: target.string as NSString)
        let languages = CodeLanguage.allCases.sorted { $0.label.caseInsensitiveCompare($1.label) == .orderedAscending }
        for language in languages {
            let item = makeItem(title: language.label, action: .setLanguage(language), block: block, target: target)
            item.state = language == current && !isPlainText ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let plain = makeItem(title: "Plain Text", action: .plainText, block: block, target: target)
        plain.state = isPlainText ? .on : .off
        menu.addItem(plain)
        menu.addItem(makeItem(title: "Not Code", action: .notCode, block: block, target: target))
        return menu
    }

    private static func makeItem(
        title: String, action: CodeBlockAction, block: NSRange, target: NoteTextView
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title, action: #selector(NoteTextView.chooseCodeBlockAction(_:)), keyEquivalent: "")
        item.target = target
        item.isEnabled = true
        item.representedObject = CodeBlockChoice(action: action, block: block)
        return item
    }

    /// True when the opening fence of the block names it `text` (in any case): the one name that stands for plain text.
    private static func namesPlainText(block: NSRange, in text: NSString) -> Bool {
        guard let parts = CodeBlockParts(block: block, in: text) else { return false }
        return parts.info.caseInsensitiveCompare(plainTextName) == .orderedSame
    }

    // MARK: Edits (Foundation, ScratchCore and ScratchCode only)

    /// The edit that `action` makes of the block at `block` in `text`, with the caret at the end of the new fence name
    /// (for the two that name the block) or at the start of the lines that are left ("Not Code"). It is a no-op, with the
    /// caret where the block starts, when `block` is not a block of `text`.
    static func edit(for action: CodeBlockAction, block: NSRange, in text: NSString) -> TextEdit {
        edit(for: action, block: block, in: text, selection: nil)
    }

    /// The same edit, with the selection that the view had before it carried over it: a caret in the code stays in the
    /// same place of the code, one in the opening fence goes to the end of the new name, and one in the closing fence to the
    /// end of the code that is left. `selection` nil is the edit above.
    static func edit(for action: CodeBlockAction, block: NSRange, in text: NSString, selection: NSRange?) -> TextEdit {
        guard let parts = CodeBlockParts(block: block, in: text) else {
            let at = min(max(block.location, 0), text.length)
            return TextEdit(
                range: NSRange(location: at, length: 0), replacement: "",
                selection: selection ?? NSRange(location: at, length: 0))
        }
        switch action {
        case .setLanguage(let language):
            return nameFence(of: parts, as: language.fenceName, in: text, selection: selection)
        case .plainText:
            return nameFence(of: parts, as: plainTextName, in: text, selection: selection)
        case .notCode:
            return removeFences(of: parts, in: text, selection: selection)
        }
    }

    /// Replaces what follows the backticks of the opening fence (the spaces before the name, the name and the spaces after
    /// it) with `name`. The spaces in front of the backticks, the backticks themselves (there may be more than three) and the
    /// line break stay. Naming the block what it is named already changes nothing.
    private static func nameFence(
        of parts: CodeBlockParts, as name: String, in text: NSString, selection: NSRange?
    ) -> TextEdit {
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        text.getParagraphStart(
            &lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
            for: NSRange(location: parts.range.location, length: 0))
        var index = parts.range.location
        while index < contentsEnd, text.character(at: index) == 0x20 { index += 1 }
        while index < contentsEnd, text.character(at: index) == 0x60 { index += 1 }
        let replaced = NSRange(location: index, length: max(contentsEnd - index, 0))
        let newLength = (name as NSString).length

        if replaced.length == newLength, text.substring(with: replaced) == name {
            // Nothing to change: no edit, and so no undo step.
            return TextEdit(
                range: NSRange(location: index, length: 0), replacement: "",
                selection: selection ?? NSRange(location: index + newLength, length: 0))
        }

        let mapping = EditMapping(replaced: replaced, newLength: newLength)
        let end = NSRange(location: replaced.location + newLength, length: 0)
        var after = end
        if let selection {
            let isCaretInName =
                selection.length == 0 && selection.location >= replaced.location
                && selection.location <= NSMaxRange(replaced)
            // A caret in or at the name goes to the end of the new one; anything else goes where its text goes.
            after = isCaretInName ? end : mapping.mapped(selection)
        }
        return TextEdit(range: replaced, replacement: name, selection: after)
    }

    /// Replaces the block with the lines between its fences, as they are. Two fences with nothing between them have no
    /// lines to keep, and they are taken away with one of the line breaks next to them (the one after the block, or the one
    /// before it when the block ends the text), so that no empty line is left behind.
    private static func removeFences(of parts: CodeBlockParts, in text: NSString, selection: NSRange?) -> TextEdit {
        let block = parts.range
        guard parts.closingLine.location > NSMaxRange(parts.openingParagraph) else {
            return removeEmptyBlock(block, in: text, selection: selection)
        }
        let content = parts.content
        let kept = content.length > 0 ? text.substring(with: content) : ""
        // The same text as taking the closing fence line and the line break before it away, and then the opening fence
        // line, which is how the selection is carried over.
        let steps = [
            EditMapping(
                replaced: NSRange(location: NSMaxRange(content), length: NSMaxRange(block) - NSMaxRange(content)),
                newLength: 0),
            EditMapping(
                replaced: NSRange(location: block.location, length: content.location - block.location), newLength: 0),
        ]
        let start = NSRange(location: block.location, length: 0)
        return TextEdit(
            range: block, replacement: kept, selection: selection.map { carry($0, through: steps) } ?? start)
    }

    private static func removeEmptyBlock(_ block: NSRange, in text: NSString, selection: NSRange?) -> TextEdit {
        var removal = block
        // The closing fence line with the line break that ends it.
        let closing = text.paragraphRange(for: NSRange(location: NSMaxRange(block) - 1, length: 0))
        if NSMaxRange(closing) > NSMaxRange(block) {
            removal = NSRange(location: block.location, length: NSMaxRange(closing) - block.location)
        } else if block.location > 0 {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            text.getParagraphStart(
                &lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                for: NSRange(location: block.location - 1, length: 0))
            removal = NSRange(location: contentsEnd, length: NSMaxRange(block) - contentsEnd)
        }
        let start = NSRange(location: removal.location, length: 0)
        let step = EditMapping(replaced: removal, newLength: 0)
        return TextEdit(
            range: removal, replacement: "", selection: selection.map { carry($0, through: [step]) } ?? start)
    }

    /// `selection` after each of `steps` in turn. A caret that is in the text a step takes away goes to where it was
    /// taken from, and a selection that had an end in it ends there.
    private static func carry(_ selection: NSRange, through steps: [EditMapping]) -> NSRange {
        var result = selection
        for step in steps {
            if result.length == 0 {
                result = NSRange(location: step.mapEnd(result.location), length: 0)
            } else {
                result = step.mapped(result)
            }
        }
        return result
    }
}
