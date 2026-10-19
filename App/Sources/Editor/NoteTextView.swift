import AppKit

/// The editor's text view: plain text in one font, whatever is pasted, and plain text only on the pasteboard
/// (spec §6.4, §6.5). `applyScratchConfiguration()` sets it up. `TextViewFactory` calls it.
final class NoteTextView: NSTextView {
    /// The one font of every note: SF Mono, 13 pt (spec §6.4).
    static let noteFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    /// Keeps the TextKit 1 text storage alive for as long as the view lives. In TextKit 1 the storage owns the layout
    /// manager, which owns the container, while `NSLayoutManager.textStorage` and `NSTextContainer.layoutManager` are
    /// unowned and the view does not own the storage. Without this reference the whole stack is freed when
    /// `TextViewFactory.makeEditor(mode: .one)` returns. Nil on a TextKit 2 view, whose content storage the view owns.
    var ownedTextStorage: NSTextStorage?

    /// How every character of a note looks: the note font in the standard text colour.
    static var noteAttributes: [NSAttributedString.Key: Any] {
        [.font: noteFont, .foregroundColor: NSColor.textColor]
    }

    /// Plain text is the only thing that leaves the editor, so nothing from the note's font or colours reaches Slack,
    /// mail or a terminal (spec §6.5). Copy, Cut, drags and Services all ask here, and write through
    /// `writeSelection(to:types:)` below. Keep copy-out in these two places: rich copy-out would be added here.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    /// Writes the selected text, exactly as it is stored, as the only thing on the pasteboard. Several selections
    /// (a rectangular selection) are joined by line breaks. Returns false, and writes nothing, when no text is
    /// selected or `types` does not ask for plain text. AppKit's own implementation is not used: it writes the types
    /// it prefers, which are not the same on every SDK.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard types.contains(.string), let storage = textStorage else { return false }
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty else { return false }
        let text = ranges.map { storage.attributedSubstring(from: $0).string }.joined(separator: "\n")
        _ = pboard.declareTypes([.string], owner: nil)
        return pboard.setString(text, forType: .string)
    }

    /// Plain text is the only thing that enters the editor. A paste takes the text of whatever was copied and drops
    /// its font, size and colours, so pasted text always looks like the note (spec §6.5, "Paste and Match Style" is
    /// the same as Paste). Attachments (plan 4) extend this.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    /// Starts the `keystroke` signpost interval that the performance tests measure: from the key press until what it
    /// typed is on screen (`Signposts.beginEditorInterval`).
    override func keyDown(with event: NSEvent) {
        Signposts.beginEditorInterval("keystroke")
        super.keyDown(with: event)
    }

    // THROWAWAY (spike/textkit): where does a keystroke's time go? Signpost intervals around the main steps.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let state = Signposts.editor.beginInterval("t-insertText", id: Signposts.editor.makeSignpostID())
        super.insertText(string, replacementRange: replacementRange)
        Signposts.editor.endInterval("t-insertText", state)
    }

    override func layout() {
        let state = Signposts.editor.beginInterval("t-layout", id: Signposts.editor.makeSignpostID())
        super.layout()
        Signposts.editor.endInterval("t-layout", state)
    }

    override func draw(_ dirtyRect: NSRect) {
        let state = Signposts.editor.beginInterval("t-draw", id: Signposts.editor.makeSignpostID())
        super.draw(dirtyRect)
        Signposts.editor.endInterval("t-draw", state)
    }

    /// Makes the view a plain-text editor: the note font and colours, undo, the find bar, and every automatic
    /// substitution off, so the characters a note holds are exactly the ones typed or pasted (spec §4 "Mangled code").
    func applyScratchConfiguration() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true

        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        smartInsertDeleteEnabled = false

        font = Self.noteFont
        textColor = .textColor
        typingAttributes = Self.noteAttributes
        textContainerInset = NSSize(width: 24, height: 12)
    }

    /// Replaces the whole text. All of it takes the note font and colour, and so does what is typed next.
    func load(_ text: String) {
        string = text
        font = Self.noteFont
        textColor = .textColor
        typingAttributes = Self.noteAttributes
    }
}
