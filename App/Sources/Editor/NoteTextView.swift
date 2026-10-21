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

    /// The text was edited and AppKit has processed the edit. The styler may have moved paragraphs into or out of a code
    /// block that the edit did not change, and the layout manager can only be told to generate their glyphs again now
    /// (`MarkupStyler.editDidFinish`). It is before the delegate hears of the edit, so that everything it does (scroll
    /// to the caret, say) is on the layout that the edit made.
    override func didChangeText() {
        editCount &+= 1
        styler.editDidFinish()
        super.didChangeText()
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
        editCount &+= 1
        styler.beginLoad()
        string = text
        styler.endLoad()
        typingAttributes = Self.noteAttributes(size: fontSize)
    }

    // MARK: Scrolling

    /// Keeps the top inset on screen when AppKit scrolls to a rect that starts in it.
    ///
    /// A text view keeps its selection visible whenever its frame changes (`-[NSTextView setFrameSize:]` scrolls to the
    /// selection): at launch, when the scrollers change their style, and whenever the window or the sidebar is resized.
    /// With the caret on the first line of a note that is taller than the window, the rect it asks for starts at the top
    /// of the text, `textContainerInset.height` below the top of the view, and AppKit puts it at the top of the window.
    /// That scrolled the huge note 12 pt, so its first line sat higher than the typical note's (Plan 2's final review).
    /// When such a scroll leaves less than the inset above the text, the view is scrolled the rest of the way to the top
    /// (`-contentInsets.top`, which every scroll position of the editor goes through). A call that did not scroll (the
    /// rect was visible already) or that ends further down is left alone.
    override func scrollToVisible(_ rect: NSRect) -> Bool {
        let before = enclosingScrollView?.contentView.bounds.origin.y
        let scrolled = super.scrollToVisible(rect)
        let inset = textContainerInset.height
        guard rect.minY <= inset + 1, let scrollView = enclosingScrollView else { return scrolled }
        let clipView = scrollView.contentView
        let top = -scrollView.contentInsets.top
        let y = clipView.bounds.origin.y
        if y != before, y > top, y <= top + inset + 1 {
            scroll(NSPoint(x: clipView.bounds.origin.x, y: top))
        }
        return scrolled
    }

    // MARK: Paste

    /// A paste is the plain paste first and a code block second (spec §6.5, plan 4 task 6). The plain paste is AppKit's,
    /// as it was: the pasteboard's text takes the note's font (`readablePasteboardTypes`). When the pasted text turns out
    /// to be code, `PasteClassifier` wraps it in a fence on the next turn of the main run loop, an edit of its own, so
    /// that ⌘Z gives back exactly the pasted text and ⌘Z again takes it away. Nothing is classified in a note that
    /// cannot be edited, for a rectangular selection, or when the text was edited between the paste and the wrap.
    ///
    /// Paste, Paste and Match Style and the hosted tests all end in `readSelection(from:)`, and each of the three starts
    /// and ends the paste (`beginPaste`, `endPaste`): a call inside another one is the same paste, and the outer one
    /// decides.
    override func paste(_ sender: Any?) {
        let start = beginPaste()
        super.paste(sender)
        endPaste(start)
    }

    /// "Paste and Match Style" is the same as Paste (spec §6.5).
    override func pasteAsPlainText(_ sender: Any?) {
        let start = beginPaste()
        super.pasteAsPlainText(sender)
        endPaste(start)
    }

    /// What Paste runs: reads the pasteboard's text over the selection. The hosted tests call it with a pasteboard of their
    /// own. A note that cannot be edited takes no text, as in `insertText(_:replacementRange:)`.
    override func readSelection(from pboard: NSPasteboard) -> Bool {
        guard isEditable else { return false }
        let start = beginPaste()
        let didRead = super.readSelection(from: pboard)
        endPaste(start)
        return didRead
    }

    /// How many times the text has been edited or replaced. A paste that is waiting to be classified is dropped when it
    /// is not the same any more (`PendingPaste`): the owner typed, or another note was loaded, in the meantime.
    private var editCount = 0

    /// The pastes that wait for their turn of the run loop, the oldest first. A closure that has to wait for the turn does not
    /// carry a paste: it only asks for the next one (`classifyNextPaste`).
    private var pendingPastes: [PendingPaste] = []

    /// How many pastes wait for their turn. The hosted tests run the loop until it is zero.
    var pendingPasteClassifications: Int { pendingPastes.count }

    /// Greater than zero while a paste is being read, so that the paste that AppKit makes of `paste(_:)` by calling
    /// `readSelection(from:)` is one paste and not two.
    private var pasteDepth = 0

    /// How many times the classification of a paste waits for the undo group of the paste to close. In the app that is the
    /// end of the event's turn; a hosted test never ends its turn, and the wrap goes ahead after this many.
    private static let undoGroupRetries = 8

    /// How long the `paste-code` interval stays open at the most, in seconds, when the colours do not come.
    private static let pasteIntervalLimit: TimeInterval = 5

    /// What the text view looked like before a paste, and the paste's signpost interval.
    private struct PasteStart {
        let selection: NSRange
        let length: Int
        /// True when the paste can be classified: the note can be edited and the selection is one range.
        let canClassify: Bool
        /// True when the paste goes into a fenced block or into inline code.
        let isInCode: Bool
        let interval: OpenInterval
    }

    /// A paste that has been inserted and waits to be classified.
    private struct PendingPaste {
        /// Where the paste is in the text.
        let range: NSRange
        /// `editCount` right after the paste.
        let editCount: Int
        /// True when the paste went into a fenced block or into inline code.
        let isInCode: Bool
        /// The `paste-code` signpost interval, from the paste until the colours are on screen.
        let interval: OpenInterval
    }

    /// Call before a paste reads the pasteboard. Returns what `endPaste` needs, or nil for a paste inside another paste.
    private func beginPaste() -> PasteStart? {
        pasteDepth += 1
        guard pasteDepth == 1 else { return nil }
        let selection = selectedRange()
        let canClassify = isEditable && selectedRanges.count == 1 && styler != nil
        return PasteStart(
            selection: selection, length: textStorage?.length ?? 0, canClassify: canClassify,
            isInCode: canClassify && isPastingIntoCode(selection),
            interval: Signposts.beginOpenEditorInterval("paste-code"))
    }

    /// Call after the paste has read the pasteboard: schedules the classification of what it inserted.
    private func endPaste(_ start: PasteStart?) {
        pasteDepth -= 1
        guard let start else { return }

        // The text that came in is where the selection was and ends where the caret is. Anything else (nothing was pasted,
        // or AppKit did something else with the text) is left alone.
        guard start.canClassify, let length = textStorage?.length else { return start.interval.endWhenIdle() }
        let pasted = NSRange(location: start.selection.location, length: length - start.length + start.selection.length)
        guard pasted.length > 0, NSMaxRange(pasted) <= length,
            selectedRange() == NSRange(location: NSMaxRange(pasted), length: 0)
        else { return start.interval.endWhenIdle() }

        pendingPastes.append(
            PendingPaste(range: pasted, editCount: editCount, isInCode: start.isInCode, interval: start.interval))
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.classifyNextPaste(attempt: 0) }
        }
    }

    /// The oldest paste has had its turn: wraps it in a fence when it is code (`PasteClassifier`), and ends the `paste-code`
    /// interval when the colours of the block are on screen, or at once when nothing is going to be coloured.
    private func classifyNextPaste(attempt: Int) {
        guard let paste = pendingPastes.first else { return }
        // The undo group of the paste has to be closed first, or the wrap would be a part of it.
        if attempt < Self.undoGroupRetries, editCount == paste.editCount, let manager = undoManager,
            manager.groupingLevel > 0
        {
            RunLoopIdle.onNext { [weak self] in self?.classifyNextPaste(attempt: attempt + 1) }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            return
        }
        pendingPastes.removeFirst()

        guard editCount == paste.editCount, isEditable, let storage = textStorage,
            NSMaxRange(paste.range) <= storage.length
        else { return paste.interval.endWhenIdle() }
        let text = storage.string as NSString
        let pasted = text.substring(with: paste.range)
        guard
            let edit = PasteClassifier.wrap(pasted: pasted, at: paste.range, in: text, isInCode: paste.isInCode)
        else { return paste.interval.endWhenIdle() }

        applyAndReveal(edit)
        let interval = paste.interval
        styler.codeBlockStyler.whenHighlighted { interval.endWhenIdle() }
        // A block that is never coloured must not leave the interval open.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteIntervalLimit) {
            MainActor.assumeIsolated { interval.end() }
        }
    }

    /// True when a paste over `selection` goes into code: the selection touches a fenced block (the fence lines included),
    /// or an end of it is inside inline code. Asked before the paste, while the text is what the owner sees: a paste of
    /// several lines splits the line that inline code is on.
    private func isPastingIntoCode(_ selection: NSRange) -> Bool {
        if styler.intersectsCodeBlock(selection) { return true }
        return isInInlineCode(at: selection.location)
            || (selection.length > 0 && isInInlineCode(at: NSMaxRange(selection)))
    }

    /// True when `location` is between the backticks of inline code (not before the first one or after the last one).
    private func isInInlineCode(at location: Int) -> Bool {
        let text = string as NSString
        guard location >= 0, location <= text.length else { return false }
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getParagraphStart(
            &start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        guard contentsEnd > start, contentsEnd - start <= Self.inlineCodeLookLimit else { return false }
        let line = text.substring(with: NSRange(location: start, length: contentsEnd - start))
        return MarkupParser.parseLine(line, at: start).contains { span in
            guard case .inlineCode = span.kind else { return false }
            return span.range.location < location && location < NSMaxRange(span.range)
        }
    }

    /// A line longer than this many UTF-16 units is not looked at for inline code when something is pasted into it.
    private static let inlineCodeLookLimit = 20_000

    // MARK: Edits the owner asks for

    /// Applies an edit that one of the editing rules (`ListEditing`, `InlineEditing`) answered with, as one undo step:
    /// the text is changed through `shouldChangeText` and `didChangeText`, which register the undo and tell the delegate,
    /// then the selection is set. The text view coalesces typing into one undo operation, and `breakUndoCoalescing`
    /// ends that run before and after the edit, so the edit is not amended to what was typed before it and what is typed
    /// next is not amended to the edit. (The undo manager's group ends with the run loop turn, as for any edit.)
    /// Does nothing when the view is not editable. An edit that replaces nothing with nothing only sets the selection.
    func apply(_ edit: TextEdit) {
        guard isEditable else { return }
        breakUndoCoalescing()
        if edit.range.length > 0 || !edit.replacement.isEmpty {
            guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
            textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            didChangeText()
        }
        setSelectedRange(edit.selection)
        breakUndoCoalescing()
    }

    /// The whole paragraphs that cover the selection, which is all a rule of the core is given (never the whole note),
    /// with the selection itself. The range is in UTF-16 units of the text.
    private func coveringParagraphs() -> (text: String, range: NSRange, selection: NSRange) {
        let selection = selectedRange()
        let whole = string as NSString
        let range = whole.paragraphRange(for: selection)
        return (whole.substring(with: range), range, selection)
    }

    /// `apply(_:)` for an edit that a key or ⌘B asked for: the caret is where the edit left it, and the view scrolls to
    /// show it, as it does for typing. (A click on a checkbox does not: the caret is somewhere else, and the click must
    /// not scroll to it.)
    private func applyAndReveal(_ edit: TextEdit) {
        apply(edit)
        if frame.width > 0 { scrollRangeToVisible(selectedRange()) }
    }

    // MARK: Return, Tab and ⇧Tab

    /// The edit that `rule`, one of the list rules of the core, makes of the paragraphs under the selection, or nil when
    /// the key is not a list action and the text view keeps its default: the view cannot be edited, text is being
    /// composed, there is more than one selection (a rectangular one), a fenced block is under the selection (nothing in
    /// a block is a list, and a selection can hold a block that it starts and ends outside of), or the rule says so.
    private func listEdit(_ rule: (String, Int, NSRange) -> TextEdit?) -> TextEdit? {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1 else { return nil }
        let paragraphs = coveringParagraphs()
        guard !styler.intersectsCodeBlock(paragraphs.range) else { return nil }
        return rule(paragraphs.text, paragraphs.range.location, paragraphs.selection)
    }

    /// Return on a bullet or checkbox line continues the list, and on an empty item it ends the list, or outdents the
    /// item (`ListEditing.newline`). Anywhere else, in a code block too, it is a plain line break.
    override func insertNewline(_ sender: Any?) {
        guard let edit = listEdit(ListEditing.newline) else { return super.insertNewline(sender) }
        applyAndReveal(edit)
    }

    /// Tab on a list line indents it, and every list line of the selection (`ListEditing.indent`). On any other line it
    /// inserts a tab, as AppKit does.
    override func insertTab(_ sender: Any?) {
        guard let edit = listEdit(ListEditing.indent) else { return super.insertTab(sender) }
        applyAndReveal(edit)
    }

    /// ⇧Tab on a list line outdents it, and every list line of the selection (`ListEditing.outdent`). A list line that
    /// is not indented has nothing to give back, and the key does nothing there. On any other line it is AppKit's own.
    override func insertBacktab(_ sender: Any?) {
        guard let edit = listEdit(ListEditing.outdent) else { return super.insertBacktab(sender) }
        applyAndReveal(edit)
    }

    // MARK: Checkboxes

    /// A plain click inside the box of a checklist item ticks or unticks it, and goes no further: the caret stays where
    /// it was, so the box can be clicked while typing somewhere else. A plain click on the language label of a code block
    /// opens its menu and goes no further either (`showCodeBlockMenu`), unless the note cannot be edited. A ⌘-click on a
    /// link opens it (`openURL`) and goes no further: it places no caret, and it also works in a note that cannot be
    /// edited. Any other click, also one on a box or a label with a modifier key held (⇧ extends the selection) or in a
    /// note that cannot be edited, is the text view's own: a plain click on a link places the caret and never opens
    /// anything.
    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let point = convert(event.locationInWindow, from: nil)
        if modifiers.isDisjoint(with: [.shift, .command, .option, .control]),
            toggleCheckbox(atViewPoint: point) || showCodeBlockMenu(atViewPoint: point)
        {
            return
        }
        if modifiers.contains(.command), let url = link(atViewPoint: point) {
            openURL(url)
            return
        }
        super.mouseDown(with: event)
    }

    /// The `[?]` of the checkbox whose box is at `point`, in the coordinates of this view, or nil when `point` is
    /// anywhere else: the space after the box, the text of the item, the margin, a line that is no checklist item or
    /// the lines of a code block (`MarkupStyler` gives none of them a role). The box is the rectangle of the three
    /// characters, which is what `MarkupLayoutManager` draws the symbol in.
    func checkboxMarker(atViewPoint point: NSPoint) -> NSRange? {
        guard let layoutManager, let container = textContainer, let styler else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        // The character under the point, not the nearest place to put the caret: the right half of the last `]` would
        // otherwise count as the space after the box.
        let index = layoutManager.characterIndex(
            for: local, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard let marker = styler.checkboxMarker(at: index) else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: marker, actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: container).contains(local) ? marker : nil
    }

    /// Ticks or unticks the checkbox whose box is at `point` (`checkboxMarker(atViewPoint:)`) and returns true, or
    /// returns false and does nothing when there is none there or the view cannot be edited. The selection is passed
    /// through, so the caret stays; the view takes the keyboard, as a click in it does. One undo step.
    @discardableResult
    func toggleCheckbox(atViewPoint point: NSPoint) -> Bool {
        guard isEditable, let marker = checkboxMarker(atViewPoint: point) else { return false }
        let text = string as NSString
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        text.getParagraphStart(
            &lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: marker.location, length: 0))
        let line = text.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        guard
            let edit = ListEditing.toggleCheckmark(line: line, lineStart: lineStart, selection: selectedRange())
        else { return false }
        apply(edit)
        return true
    }

    // MARK: The language label of a code block

    /// Shows the menu of a label, with its top left corner at the point (in the coordinates of this view). Nil, the
    /// default, is `NSMenu.popUp(positioning:at:in:)`, which runs a tracking loop of its own until the menu is dismissed:
    /// a hosted test replaces this, so that it does not wait for a mouse.
    var codeBlockMenuPresenter: ((NSMenu, NSPoint) -> Void)?

    /// How far outside its rectangle a click still counts as being on a label: a label is a few characters of small text.
    private static let labelHitOutset: CGFloat = 3

    /// How far below a point the second look for the block of a label is taken (`labelTarget`): the opening fence line is
    /// 6 pt high, and the line below it is the first line of code, which the label reaches into.
    private static let labelProbeOffset: CGFloat = 8

    /// The block whose label is under `point` (in the coordinates of this view), with the label's rectangle in the same
    /// coordinates, or nil. The block is the one that the character nearest to the point belongs to (a label sits on the
    /// opening fence line and on the first line of code), so only that block is laid out and measured, never every block
    /// of the note. The point is looked at twice, as it is and a few points lower: on the 6 pt line of a hidden fence
    /// (a clear glyph and null glyphs) the nearest character is not something to rely on, and the line below is code.
    /// The label's own rectangle decides.
    private func labelTarget(atViewPoint point: NSPoint) -> (block: NSRange, rect: NSRect)? {
        guard let layoutManager = layoutManager as? MarkupLayoutManager, let container = textContainer,
            let styler, !styler.codeBlockList.isEmpty
        else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        for offset in [0, Self.labelProbeOffset] {
            let probe = NSPoint(x: local.x, y: local.y + offset)
            let index = layoutManager.characterIndex(
                for: probe, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            guard let block = styler.codeBlock(containing: index)?.range,
                let rect = layoutManager.labelRect(forBlockAt: block.location),
                rect.insetBy(dx: -Self.labelHitOutset, dy: -Self.labelHitOutset).contains(local)
            else { continue }
            return (block, rect.offsetBy(dx: origin.x, dy: origin.y))
        }
        return nil
    }

    /// The block whose language label is under `point`, in the coordinates of this view, or nil when `point` is anywhere
    /// else: the code, the margin, a block that has no label (a fence with no name whose code is not code). It does not
    /// ask whether the note can be edited: `showCodeBlockMenu(atViewPoint:)` does.
    func labelHit(atViewPoint point: NSPoint) -> NSRange? {
        labelTarget(atViewPoint: point)?.block
    }

    /// Shows the menu of the label under `point` (`CodeBlockMenu`) with its top left corner under the label, and returns
    /// true, or returns false and shows nothing when no label is there or the note cannot be edited (a note in Recently
    /// Deleted: a menu that changed its text would break spec §6.2).
    @discardableResult
    func showCodeBlockMenu(atViewPoint point: NSPoint) -> Bool {
        guard isEditable, let target = labelTarget(atViewPoint: point), let storage = textStorage else { return false }
        let mark =
            storage.attribute(.scratchCodeBlock, at: target.block.location, effectiveRange: nil) as? CodeBlockMark
        let menu = CodeBlockMenu.menu(for: target.block, current: mark?.language, target: self)
        let anchor = NSPoint(x: target.rect.minX, y: target.rect.maxY)
        if let codeBlockMenuPresenter {
            codeBlockMenuPresenter(menu, anchor)
        } else {
            _ = menu.popUp(positioning: nil, at: anchor, in: self)
        }
        return true
    }

    /// What an item of the label menu does (`CodeBlockMenu.menu`): the action of its `CodeBlockChoice`, on its block.
    @objc func chooseCodeBlockAction(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let choice = item.representedObject as? CodeBlockChoice else { return }
        applyCodeBlockAction(choice.action, to: choice.block)
    }

    /// Changes the code block at `block` as `action` says, as one undo step (`apply(_:)`), with the caret where it was in
    /// the text. Does nothing when the note cannot be edited or `block` is no longer a block of the note exactly as it was
    /// (the menu is up while the note could have changed). The view takes the keyboard, as a click in it does.
    func applyCodeBlockAction(_ action: CodeBlockAction, to block: NSRange) {
        guard isEditable, styler.codeBlock(containing: block.location)?.range == block else { return }
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        apply(CodeBlockMenu.edit(for: action, block: block, in: string as NSString, selection: selectedRange()))
    }

    // MARK: Links

    /// What a ⌘-click on a link does with its URL: it opens it in the default browser. Tests replace it, so that none of
    /// them opens a browser.
    var openURL: (URL) -> Void = { _ = NSWorkspace.shared.open($0) }

    /// The area that has the view told when the mouse moves, which is how the pointing hand follows the mouse while ⌘ is
    /// held. `updateTrackingAreas()` makes it once. It follows the visible part of the view by itself.
    private(set) var linkTrackingArea: NSTrackingArea?

    /// True while this view has set the pointing hand. The view puts the I-beam back only then and leaves the cursor
    /// alone otherwise: it is not the view's to set over the scroll bar, say.
    private var showsLinkCursor = false

    /// The URL of the link under `point`, in the coordinates of this view, or nil. The point must be on a character of
    /// the link itself: the empty space to the right of a link that ends its line is not, although the character nearest
    /// to it is the link's last. Nothing in inline code or in a fenced block is a link (`MarkupStyler.link(at:)`).
    func link(atViewPoint point: NSPoint) -> URL? {
        guard let layoutManager, let container = textContainer, let styler else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let index = layoutManager.characterIndex(
            for: local, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard let url = styler.link(at: index) else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        let box = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        return box.contains(local) ? url : nil
    }

    /// Shows the pointing hand while ⌘ is held over a link (`modifiers` are the keys held, `point` is where the mouse is,
    /// in the coordinates of this view), and puts the I-beam back when the mouse leaves the link or ⌘ is let go. Returns
    /// the cursor it set, or nil when it left the cursor alone, which is every time the view has not set the pointing
    /// hand and does not set it now.
    @discardableResult
    func updateLinkCursor(atViewPoint point: NSPoint, modifiers: NSEvent.ModifierFlags) -> NSCursor? {
        let overLink = modifiers.contains(.command) && link(atViewPoint: point) != nil
        guard overLink || showsLinkCursor else { return nil }
        showsLinkCursor = overLink
        let cursor: NSCursor = overLink ? .pointingHand : .iBeam
        cursor.set()
        return cursor
    }

    /// Asks for the mouse moves over the visible part of the view, which AppKit does not send to a text view otherwise.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = linkTrackingArea, trackingAreas.contains(area) { return }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        linkTrackingArea = area
    }

    /// The mouse moved over the view: the pointing hand shows over a link while ⌘ is held, whichever way ⌘ and the mouse
    /// came there.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateLinkCursor(atViewPoint: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    /// ⌘ was pressed or let go while the mouse is still: the cursor changes without a mouse move. Only the view that has
    /// the keyboard hears it. A mouse that is somewhere else than over this view leaves the cursor to whatever is there.
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(point) else {
            showsLinkCursor = false
            return
        }
        updateLinkCursor(atViewPoint: point, modifiers: event.modifierFlags)
    }

    // MARK: The Format menu

    /// ⇧⌘L (Format > Checklist): the lines of the selection (the caret's line when there is none) become a checklist,
    /// or, when every one of them already is one, plain lines again (`ListEditing.toggleChecklist`). One undo step. It
    /// does nothing but beep when the note cannot be edited, or when a fenced block is among the lines: inside a block
    /// nothing is formatting, so no marker is put there.
    @objc func toggleChecklist(_ sender: Any?) {
        guard isEditable else { return NSSound.beep() }
        let paragraphs = coveringParagraphs()
        guard !styler.intersectsCodeBlock(paragraphs.range) else { return NSSound.beep() }
        apply(
            ListEditing.toggleChecklist(
                paragraphs: paragraphs.text, start: paragraphs.range.location, selection: paragraphs.selection))
    }

    /// ⌘B (Format > Bold): the selection becomes `**selection**`, or loses its stars when it is a bold run, or, with no
    /// selection, `****` goes in with the caret between the pairs (`InlineEditing.toggleBold`). One undo step. It does
    /// nothing but beep when the note cannot be edited, when a fenced block is under the selection (inside a block
    /// every character is literal) and for a rectangular selection. The name is not `toggleBold`: that is AppKit's
    /// action for the font panel, which a plain-text view must not answer.
    @objc func toggleBoldMarkers(_ sender: Any?) {
        guard isEditable, selectedRanges.count == 1 else { return NSSound.beep() }
        let paragraphs = coveringParagraphs()
        guard !styler.intersectsCodeBlock(paragraphs.range) else { return NSSound.beep() }
        applyAndReveal(
            InlineEditing.toggleBold(
                paragraphs: paragraphs.text, start: paragraphs.range.location, selection: paragraphs.selection))
    }
}
