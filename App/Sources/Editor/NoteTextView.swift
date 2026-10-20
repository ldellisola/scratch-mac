import AppKit
import ScratchCore

/// The editor's text view: plain text in one font, whatever is pasted, and plain text only on the pasteboard
/// (spec §6.4, §6.5). `applyScratchConfiguration()` sets it up. `TextViewFactory` calls it.
final class NoteTextView: NSTextView {
    /// The one font of every note at `size` points: SF Mono, regular weight (spec §6.4). The size is the same for every
    /// note and can be changed with ⌘+ and ⌘− (`FontSize`).
    static func noteFont(size: Double) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }

    /// The note font at the default size: SF Mono, 13 pt.
    static let noteFont: NSFont = noteFont(size: FontSize.standard)

    /// The font of a bold run (`**bold**`) at `size` points: the note font in bold weight. Bold is the only thing that
    /// changes the font of a note's text (spec §6.4: emphasis comes from weight and colour only).
    static func boldNoteFont(size: Double) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .bold)
    }

    /// The space between the text and the left and right edges of the view, in points. The title field above the
    /// editor lines up with the text by using it.
    static let horizontalInset: CGFloat = 24

    /// The space between the text and the top and bottom edges of the view, in points.
    static let verticalInset: CGFloat = 12

    /// The size in points of the text this view shows and of what is typed or pasted next. `applyFontSize(_:)` sets it.
    private(set) var fontSize: Double = FontSize.standard

    /// The undo manager of the note being shown, which the editor sets for each note (`EditorViewController.show`).
    /// Undo history is per note and lasts for the session (spec §6.6), so each note brings its own manager and the
    /// history is not shared with the other notes or with the window. Nil falls back to AppKit's own.
    var noteUndoManager: UndoManager?

    /// The note's own manager. A view that is not editable (a note in Recently Deleted) has none: undo would still change
    /// its text, which spec §6.2 says is read-only. The note keeps its manager for when it is editable again.
    override var undoManager: UndoManager? {
        guard isEditable else { return nil }
        return noteUndoManager ?? super.undoManager
    }

    /// Keeps the TextKit 1 text storage alive for as long as the view lives. In TextKit 1 the storage owns the layout
    /// manager, which owns the container, while `NSLayoutManager.textStorage` and `NSTextContainer.layoutManager` are
    /// unowned and the view does not own the storage. Without this reference the whole stack is freed when
    /// `TextViewFactory.makeEditor()` returns.
    var ownedTextStorage: NSTextStorage?

    /// Styles the markers of the text: bullets, checkboxes, bold, inline code and links. It is the text storage's
    /// delegate, which does not keep it alive, so the view does. `TextViewFactory` sets it before the view is
    /// configured. Everything that loads or sizes the text goes through it (`load(_:)`, `applyFontSize(_:)`).
    var styler: MarkupStyler!

    /// How every character of a note looks at `size` points: the note font in the standard text colour.
    static func noteAttributes(size: Double) -> [NSAttributedString.Key: Any] {
        [.font: noteFont(size: size), .foregroundColor: NSColor.textColor]
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

    /// A text view that is not editable (a note in Recently Deleted, spec §6.2) takes no text from anywhere. AppKit
    /// already refuses it in most paths, and this makes sure of the rest.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard isEditable else { return }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// Starts the `keystroke` signpost interval that the performance tests measure: from the key press until what it
    /// typed is on screen (`Signposts.beginEditorInterval`).
    override func keyDown(with event: NSEvent) {
        Signposts.beginEditorInterval("keystroke")
        super.keyDown(with: event)
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

        applyFontSize(fontSize)
        textContainerInset = NSSize(width: Self.horizontalInset, height: Self.verticalInset)
    }

    /// Gives all the text, and what is typed or pasted next, the note font at `size` points (limited to what
    /// `FontSize` allows). Pasted text takes the typing attributes, so it takes the size too (spec §6.5). The text
    /// that is there is styled again by the styler, so that its bold runs keep their weight at the new size: setting
    /// `font` on a plain-text view would reset every run to the regular weight.
    func applyFontSize(_ size: Double) {
        fontSize = FontSize.clamped(size)
        if (textStorage?.length ?? 0) == 0 {
            font = Self.noteFont(size: fontSize)
            textColor = .textColor
        }
        typingAttributes = Self.noteAttributes(size: fontSize)
        styler?.fontSize = fontSize
    }

    /// Replaces the whole text. All of it takes the note font and colour at the current size, and so does what is
    /// typed next. The markers in it are not styled until the styler is told the note is shown
    /// (`MarkupStyler.noteDidLoad(visibleRange:)`, which `EditorViewController.show` calls).
    func load(_ text: String) {
        styler.beginLoad()
        string = text
        styler.endLoad()
        typingAttributes = Self.noteAttributes(size: fontSize)
    }
}
