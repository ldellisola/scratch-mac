import AppKit
import ScratchCore
import UniformTypeIdentifiers

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

    /// Writes the selected text, as it is stored, as the only thing on the pasteboard, except for attachments (spec §6.5): a
    /// token line is written as the name of its file, and a selection that is exactly one attachment also writes the stored
    /// file's URL and, for an image, the image as PNG and TIFF (`AttachmentCopying`, `AttachmentPasteboard`). Several
    /// selections (a rectangular selection) are joined by line breaks. Returns false, and writes nothing, when no text is
    /// selected or `types` does not ask for plain text. AppKit's own implementation is not used: it writes the types it
    /// prefers, which are not the same on every SDK. Copy, Cut, drags and Services all end here.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard types.contains(.string), let storage = textStorage else { return false }
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty else { return false }
        let text = storage.string as NSString
        // A token in a fenced block is text, and is copied as it was typed.
        let isLiteral: (NSRange) -> Bool = { self.styler?.isInCodeBlock($0.location) ?? false }
        let catalog = styler?.catalog
        let name: (AttachmentID) -> String = { catalog?.attachment($0)?.fileName ?? Self.missingAttachmentName }
        let copied = ranges.map { AttachmentCopying.text(of: $0, in: text, name: name, ignoring: isLiteral) }
            .joined(separator: "\n")

        if ranges.count == 1, let id = AttachmentCopying.soleAttachment(in: ranges[0], of: text, ignoring: isLiteral),
            let attachment = catalog?.attachment(id), let url = catalog?.fileURL(id),
            FileManager.default.fileExists(atPath: url.path)
        {
            let made = AttachmentPasteboard.item(name: copied, fileURL: url, isImage: attachment.isImage)
            // The pasteboard asks the provider when an application wants the image, which is after this returns.
            attachmentImageProvider = made.provider
            _ = pboard.clearContents()
            return pboard.writeObjects([made.item])
        }
        _ = pboard.declareTypes([.string], owner: nil)
        return pboard.setString(copied, forType: .string)
    }

    /// What the text of a copy has where the token of an attachment that no row knows was (spec §6.5).
    private static let missingAttachmentName = "Missing attachment"

    /// The provider of the image of the attachment that was copied last, kept for as long as the pasteboard may ask it: an
    /// application that pastes the image asks when it pastes, after Copy has returned.
    private var attachmentImageProvider: AttachmentImageProvider?

    /// What a paste or a drop takes: text first, which is plain text whatever was copied and drops its font, size and
    /// colours, so pasted text always looks like the note (spec §6.5, "Paste and Match Style" is the same as Paste), and
    /// then what makes an attachment (spec §6.5, plan 5 task 5): file references and images. AppKit offers Paste, and
    /// accepts a drag, only when the pasteboard holds one of these types. What is done with each is decided in
    /// `readSelection(from:)`, in the order of the spec, and not by the order of this list.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string, .fileURL, .png, .tiff] }

    /// What the view registers for dragging: what a paste takes, so that a file or an image can be dropped on the note.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        var types = super.acceptableDragTypes
        for type in [NSPasteboard.PasteboardType.fileURL, .png, .tiff] where !types.contains(type) {
            types.append(type)
        }
        return types
    }

    /// AppKit registers the drag types again whenever the view becomes editable or not editable, which is for every note
    /// that is shown. The types of an attachment are registered here too, in case its own registration is not made of
    /// `acceptableDragTypes`. A note that cannot be edited registers nothing: it takes no drop.
    override func updateDragTypeRegistration() {
        super.updateDragTypeRegistration()
        if isEditable { registerForDraggedTypes(acceptableDragTypes) }
    }

    /// A text view that is not editable (a note in Recently Deleted, spec §6.2) takes no text from anywhere. AppKit
    /// already refuses it in most paths, and this makes sure of the rest.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard isEditable else { return }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// True while `setMarkedText(_:selectedRange:replacementRange:)` runs: the edit that it makes puts composed text in the
    /// note, and the styler keeps the attributes that AppKit gave that text (`MarkupStyler.composedAttributes`). Only
    /// `setMarkedText` sets it, except in `MarkupStylerTests`, which edit the storage directly with it set: AppKit
    /// gives a hosted view's composed text none of the input method's attributes, so that is the one way to hand the
    /// styler an edit that carries them.
    var isSettingMarkedText = false

    /// An input method is composing text (the owner types, say, pinyin, and has not chosen the characters yet): the text
    /// is in the note, underlined, until it is entered. Every step replaces it, which is an edit that the styler styles
    /// the paragraph for, and composed text must keep its underline through that. A note that cannot be edited takes
    /// nothing, as in `insertText(_:replacementRange:)`.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard isEditable else { return }
        isSettingMarkedText = true
        defer { isSettingMarkedText = false }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
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
        updateDragTypeRegistration()
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
        if !readAttachments(from: NSPasteboard.general) { super.paste(sender) }
        endPaste(start)
    }

    /// "Paste and Match Style" is the same as Paste (spec §6.5).
    override func pasteAsPlainText(_ sender: Any?) {
        let start = beginPaste()
        if !readAttachments(from: NSPasteboard.general) { super.pasteAsPlainText(sender) }
        endPaste(start)
    }

    /// Which type of a pasteboard AppKit reads when it pastes or accepts a drop: any text wins over every other type, with
    /// an image next to it or not (spec §6.5, Excel, Word and browsers put both on the pasteboard). Files and images are
    /// made into attachments before AppKit is asked (`paste(_:)`, `readSelection(from:)`, `performDragOperation(_:)`), so
    /// what is left for it is text, and what it does with a pasteboard of an image and no text is not asked of it.
    override func preferredPasteboardType(
        from availableTypes: [NSPasteboard.PasteboardType],
        restrictedToTypesFrom allowedTypes: [NSPasteboard.PasteboardType]?
    ) -> NSPasteboard.PasteboardType? {
        if availableTypes.contains(.string), allowedTypes?.contains(.string) ?? true { return .string }
        return super.preferredPasteboardType(from: availableTypes, restrictedToTypesFrom: allowedTypes)
    }

    /// What Paste runs: reads the pasteboard over the selection, in the order of spec §6.5. File references come first and
    /// become attachments, then any text, which is pasted as plain text (and is classified as code or not on the next turn,
    /// below), then an image with no text, which becomes an image attachment. The hosted tests call it with a pasteboard
    /// of their own. A note that cannot be edited takes nothing, as in `insertText(_:replacementRange:)`.
    override func readSelection(from pboard: NSPasteboard) -> Bool {
        guard isEditable else { return false }
        let start = beginPaste()
        let didRead = readAttachmentsOrText(from: pboard)
        endPaste(start)
        return didRead
    }

    /// The order of a paste (spec §6.5): files, then text, then an image. Text is read as `.string` and nothing else, so
    /// that the image types that `readablePasteboardTypes` lists for the sake of Paste never come between the text of a
    /// pasteboard and the note: Excel, Word and browsers put an image of the selection next to its text, and the text wins.
    private func readAttachmentsOrText(from pboard: NSPasteboard) -> Bool {
        readAttachments(from: pboard) || super.readSelection(from: pboard, type: .string)
    }

    /// Makes attachments of the files, or the image with no text, on `pboard` and puts them in the note, which is what a
    /// paste does first (`attachmentSources(from:)`). Returns false, and changes nothing, when there are none or they cannot
    /// be put in (`insertAttachments`).
    private func readAttachments(from pboard: NSPasteboard) -> Bool {
        guard isEditable, let sources = attachmentSources(from: pboard), insertAttachments(sources) else {
            return false
        }
        attachmentPasteWasInserted = true
        return true
    }

    /// True while the paste that is being read has put attachments, or the names of files, in the note. Such a paste is not
    /// looked at for code on the next turn: its text is token lines.
    private var attachmentPasteWasInserted = false

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

    /// A paste that has been inserted and waits for its turn.
    private struct PendingPaste {
        /// What `PasteClassifier` made of the paste, when it was asked.
        enum Wrap {
            /// Asked at once, when the paste was read (`endPaste`): the edit that wraps it, or nil to leave it plain. The
            /// turn applies this edit when the text is the one that was looked at.
            case decided(TextEdit?)
            /// A paste too big to be looked at inside the paste's own turn (`PasteClassifier.earlyWrapLimit`): the turn asks.
            case later
        }

        /// Where the paste is in the text.
        let range: NSRange
        /// `editCount` right after the paste.
        let editCount: Int
        /// True when the paste went into a fenced block or into inline code.
        let isInCode: Bool
        /// The wrap that was decided when the paste was read, or `.later`.
        let wrap: Wrap
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
        if attachmentPasteWasInserted {
            attachmentPasteWasInserted = false
            return start.interval.endWhenIdle()
        }

        // The text that came in is where the selection was and ends where the caret is. Anything else (nothing was pasted,
        // or AppKit did something else with the text) is left alone.
        guard start.canClassify, let length = textStorage?.length else { return start.interval.endWhenIdle() }
        let pasted = NSRange(location: start.selection.location, length: length - start.length + start.selection.length)
        guard pasted.length > 0, NSMaxRange(pasted) <= length,
            selectedRange() == NSRange(location: NSMaxRange(pasted), length: 0)
        else { return start.interval.endWhenIdle() }

        pendingPastes.append(
            PendingPaste(
                range: pasted, editCount: editCount, isInCode: start.isInCode,
                wrap: decideWrap(of: pasted, start: start),
                interval: start.interval))
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.classifyNextPaste(attempt: 0) }
        }
    }

    /// Looks at the paste that was just read, which `PasteClassifier.wrap` only needs its text for, and when it is going to be
    /// wrapped asks the highlighter for the colours of the block to come (`CodeBlockStyler.prefetch`): the highlighting then
    /// runs on its queue while the main thread waits for the turn of the wrap, and the block finds its colours when it
    /// appears. A paste of more than `PasteClassifier.earlyWrapLimit` units is not looked at here: such a block is over the
    /// highlighter's cap, so there are no colours to get ahead with, and the paste's own turn stays as short as the 50,000-line
    /// paste of `LargeInsertTests` needs it to be.
    private func decideWrap(of pasted: NSRange, start: PasteStart) -> PendingPaste.Wrap {
        guard pasted.length <= PasteClassifier.earlyWrapLimit, let storage = textStorage,
            NSMaxRange(pasted) <= storage.length
        else { return .later }
        let text = storage.string as NSString
        let edit = PasteClassifier.wrap(
            pasted: text.substring(with: pasted), at: pasted, in: text, isInCode: start.isInCode)
        if let edit { styler.codeBlockStyler.prefetch(block: edit.replacement) }
        return .decided(edit)
    }

    /// The oldest paste has had its turn: wraps it in a fence when it is code (`PasteClassifier`, decided when the paste was
    /// read, `decideWrap`, unless it was too big for that), and ends the `paste-code` interval when the colours of the block
    /// are on screen, or at once when nothing is going to be coloured.
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
        // The text is the one that was looked at (`editCount` has not moved), so what was decided then still holds.
        let decided: TextEdit?
        switch paste.wrap {
        case .decided(let edit):
            decided = edit
        case .later:
            let text = storage.string as NSString
            decided = PasteClassifier.wrap(
                pasted: text.substring(with: paste.range), at: paste.range, in: text, isInCode: paste.isInCode)
        }
        guard let edit = decided else { return paste.interval.endWhenIdle() }

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

    // MARK: Attachments

    /// Makes attachments of what is pasted, dropped or chosen (the session coordinator, through `AttachmentImporter`). Nil in a
    /// view that is not wired to the app's storage, which then pastes and drops text only. Held weakly: the coordinator
    /// owns it.
    weak var attachmentImporter: (any AttachmentImporting)?

    /// The note that the view shows, which an attachment is added to (`EditorViewController.show` sets it).
    var noteID: NoteID?

    /// What a paste or a drop would make of `pboard`, in the order of spec §6.5, or nil when it is text (or nothing that can
    /// be pasted): file references first, then, when there is no text, an image. A file that is not there is left out, and a
    /// pasteboard whose files are all gone has none. An image is the pasteboard's own bytes, PNG or TIFF, exactly as they are
    /// (`imageSource(on:)`): the importer reads the header for the size and stores a TIFF as PNG on the storage queue, so
    /// nothing here decodes a picture (spec §4, "Visible lag"). Excel, Word and browsers put an image of the selection next
    /// to the text, and then the text wins, so there are no sources.
    ///
    /// This reads the pasteboard's data: it is for the paste and the drop themselves, and never for a drag that is still
    /// moving over the note (`wouldMakeAttachments(from:)` answers that from the types).
    func attachmentSources(from pboard: NSPasteboard) -> [AttachmentSource]? {
        let files = Self.fileURLs(on: pboard)
        if !files.isEmpty { return files.map { .file($0) } }
        if Self.hasText(on: pboard) { return nil }
        return Self.imageSource(on: pboard).map { [$0] }
    }

    /// Whether `pboard` is a paste or a drag that makes attachments, decided from the types that are on it and nothing else:
    /// files, or an image and no text. No image is read, decoded or converted. A drag asks this from `draggingEntered(_:)`,
    /// `draggingUpdated(_:)` (on every move of the mouse, and again while it waits), `prepareForDragOperation(_:)` and
    /// `performDragOperation(_:)`, so it has to cost nothing whatever the size of the picture. The data is read once, by
    /// `performDrop(of:atViewPoint:)`.
    ///
    /// It can say yes for a pasteboard that `attachmentSources(from:)` finds nothing on: a file that went away since, or an
    /// image whose bytes do not come. The drop then does nothing.
    func wouldMakeAttachments(from pboard: NSPasteboard) -> Bool {
        if pboard.availableType(from: Self.fileTypes) != nil { return true }
        return pboard.availableType(from: Self.imageTypes) != nil && !Self.hasText(on: pboard)
    }

    /// The types that a file reference is on a pasteboard as: the file URL of every item, and the property list of paths that
    /// older applications still put there.
    private static let fileTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType"),
    ]

    /// The types that an image is on a pasteboard as: PNG, which is stored as it is, and TIFF, which is stored as PNG.
    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    /// True when `pboard` holds text: any text wins over an image (spec §6.5), and an image is what Excel, Word and browsers
    /// put next to a few cells or a few words. A drag asks only when an image is there to lose to the text
    /// (`wouldMakeAttachments(from:)`), so what is read is the text that came with a picture, never the picture.
    private static func hasText(on pboard: NSPasteboard) -> Bool {
        guard let text = pboard.string(forType: .string) else { return false }
        return !text.isEmpty
    }

    /// The file URLs of `pboard` that exist, as plain paths (a file reference URL, which Finder may put there, is turned
    /// into one), in the order they are on it.
    private static func fileURLs(on pboard: NSPasteboard) -> [URL] {
        let objects = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        return objects.compactMap { object -> URL? in
            guard let url = object as? NSURL, url.isFileURL else { return nil }
            let resolved = url.filePathURL ?? (url as URL)
            return FileManager.default.fileExists(atPath: resolved.path) ? resolved : nil
        }
    }

    /// The image on `pboard`, as the bytes it is there in: its PNG, or else its TIFF (a screenshot, or a picture copied from
    /// Preview or another Cocoa application, which put a TIFF there). Nothing is decoded or converted here, on the main thread:
    /// a TIFF of a full-size picture takes hundreds of milliseconds to decode and encode again. The importer reads its size
    /// from the header, and makes the PNG that the row says it is on the storage queue (`AttachmentImporter`). Nil when the
    /// pasteboard has no image data.
    private static func imageSource(on pboard: NSPasteboard) -> AttachmentSource? {
        if let png = pboard.data(forType: .png), !png.isEmpty {
            return .image(png, typeIdentifier: UTType.png.identifier)
        }
        if let tiff = pboard.data(forType: .tiff), !tiff.isEmpty {
            return .image(tiff, typeIdentifier: UTType.tiff.identifier)
        }
        return nil
    }

    /// Puts `sources` into the note over the selection (spec §6.4): an attachment each, as token lines of their own and one
    /// undo step, with the caret on the line after the last of them (`AttachmentEditing.insertion`). Inside code, a fenced
    /// block or inline code, a block is literal, so the names of the files go in as text instead and an image, which has
    /// none, goes in nowhere. Returns false, and changes nothing, when the note cannot be edited, the selection is not one
    /// range, nothing could be made of the sources, or there is no importer to make attachments.
    @discardableResult
    private func insertAttachments(_ sources: [AttachmentSource]) -> Bool {
        guard isEditable, selectedRanges.count == 1, styler != nil else { return false }
        let selection = selectedRange()
        if isPastingIntoCode(selection) { return insertNames(of: sources, over: selection) }
        guard let attachmentImporter, let noteID else { return false }
        let ids = attachmentImporter.importAttachments(sources, into: noteID)
        guard !ids.isEmpty else { return false }
        applyAndReveal(AttachmentEditing.insertion(of: ids, over: selection, in: string as NSString))
        return true
    }

    /// The names of the files among `sources`, one on each line, over `selection`: what a file is pasted as inside code.
    private func insertNames(of sources: [AttachmentSource], over selection: NSRange) -> Bool {
        let names = sources.compactMap { source -> String? in
            guard case .file(let url) = source else { return nil }
            return url.lastPathComponent
        }
        guard !names.isEmpty else { return false }
        let text = names.joined(separator: "\n")
        applyAndReveal(
            TextEdit(
                range: selection, replacement: text,
                selection: NSRange(location: selection.location + text.utf16.count, length: 0)))
        return true
    }

    // MARK: The paperclip

    /// The completion of the open panel, with the files that were chosen (none when it was cancelled).
    typealias OpenPanelCompletion = @MainActor @Sendable ([URL]) -> Void

    /// Shows the panel that chooses the files to attach, and calls the completion with them. The default shows an
    /// `NSOpenPanel` as a sheet of the window that allows several files: the hosted tests replace it, so that none of them
    /// shows a real panel.
    lazy var presentOpenPanel: @MainActor (@escaping OpenPanelCompletion) -> Void = { [weak self] completion in
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Attach"
        panel.message = "Choose the files to attach to the note."
        if let window = self?.window {
            panel.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { completion(response == .OK ? panel.urls : []) }
            }
        } else {
            panel.begin { response in
                MainActor.assumeIsolated { completion(response == .OK ? panel.urls : []) }
            }
        }
    }

    /// File > Attach File… and the paperclip: asks which files to attach, then puts them in at the caret, as a paste of
    /// files does. Beeps when the note cannot take attachments (Recently Deleted, or a view with no importer).
    func attachFiles() {
        guard isEditable, attachmentImporter != nil, noteID != nil else { return NSSound.beep() }
        presentOpenPanel { [weak self] urls in
            guard let self, !urls.isEmpty else { return }
            if self.window?.firstResponder !== self { self.window?.makeFirstResponder(self) }
            self.insertAttachments(urls.map { .file($0) })
        }
    }

    // MARK: Drops

    /// True when a drop of `pboard` would make attachments: the note can be edited and the pasteboard holds files, or an image
    /// and no text (`wouldMakeAttachments(from:)`, which looks at the types and never at the data). Any other drop, text
    /// included, is the text view's own.
    func acceptsDrop(of pboard: NSPasteboard) -> Bool {
        isEditable && wouldMakeAttachments(from: pboard)
    }

    /// Makes attachments of what was dropped at `point` (in the coordinates of this view): the caret goes there, and the
    /// attachments are inserted as a paste of them is. This is where the data of the drop is read, once. Returns false when
    /// the drop is not an attachment drop, or when nothing could be read from it.
    func performDrop(of pboard: NSPasteboard, atViewPoint point: NSPoint) -> Bool {
        guard acceptsDrop(of: pboard), let sources = attachmentSources(from: pboard) else { return false }
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        let length = textStorage?.length ?? 0
        setSelectedRange(NSRange(location: min(max(characterIndexForInsertion(at: point), 0), length), length: 0))
        return insertAttachments(sources)
    }

    /// A drag of files, or of an image with no text, over the note: copy, when it can be dropped, and nothing when it cannot
    /// (a note in Recently Deleted). Any other drag is the text view's own. The four callbacks decide from the types of the
    /// drag pasteboard (`wouldMakeAttachments(from:)`) and read no data: `draggingUpdated(_:)` runs on every move of the
    /// mouse.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard wouldMakeAttachments(from: sender.draggingPasteboard) else { return super.draggingEntered(sender) }
        return isEditable ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard wouldMakeAttachments(from: sender.draggingPasteboard) else { return super.draggingUpdated(sender) }
        return isEditable ? .copy : []
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard wouldMakeAttachments(from: sender.draggingPasteboard) else {
            return super.prepareForDragOperation(sender)
        }
        return isEditable
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard wouldMakeAttachments(from: sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        return performDrop(of: sender.draggingPasteboard, atViewPoint: convert(sender.draggingLocation, from: nil))
    }

    // MARK: Selecting and deleting a token

    /// The selection that the text view should have when it is about to change from `old` to `new` (the delegate asks, for
    /// every change of the selection, by the user or by code): the caret never stops inside an attachment's token line, and a
    /// selection never starts or ends inside one (`AttachmentEditing.snappedSelection`). A click puts the caret at the end of
    /// the token; a move in the text's direction steps over it. A token in a fenced block is text and is left alone.
    func snappedSelection(from old: NSRange, to new: NSRange) -> NSRange {
        guard let styler, let storage = textStorage, storage.length > 0 else { return new }
        let eventType = NSApplication.shared.currentEvent?.type
        let isClick = eventType == .leftMouseDown || eventType == .leftMouseUp || eventType == .leftMouseDragged
        return AttachmentEditing.snappedSelection(
            from: old, to: new, in: storage.string as NSString, isClick: isClick,
            ignoring: { styler.isInCodeBlock($0.location) })
    }

    /// Backspace next to a token selects it, and with it selected deletes it and its line break (`AttachmentEditing`), so
    /// that a key meant for the character beside a picture does not delete the picture. Anywhere else it is the text view's.
    override func deleteBackward(_ sender: Any?) {
        guard let action = attachmentDeletion(.backward) else { return super.deleteBackward(sender) }
        carryOut(action)
    }

    /// Delete (forward) next to a token: the mirror of `deleteBackward(_:)`.
    override func deleteForward(_ sender: Any?) {
        guard let action = attachmentDeletion(.forward) else { return super.deleteForward(sender) }
        carryOut(action)
    }

    /// What Backspace or Delete does around a token at the selection, or nil when the key is the text view's own: the note
    /// cannot be edited, text is being composed, there is more than one selection, or no token is involved.
    private func attachmentDeletion(_ direction: AttachmentEditing.DeletionDirection) -> AttachmentEditing.KeyAction? {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1, let styler, let storage = textStorage else {
            return nil
        }
        return AttachmentEditing.deletion(
            direction, selection: selectedRange(), in: storage.string as NSString,
            ignoring: { styler.isInCodeBlock($0.location) })
    }

    private func carryOut(_ action: AttachmentEditing.KeyAction) {
        switch action {
        case .selectToken(let range):
            setSelectedRange(range)
        case .moveCaret(let location):
            setSelectedRange(NSRange(location: location, length: 0))
        case .removeToken(let edit):
            apply(edit)
        }
        if frame.width > 0 { scrollRangeToVisible(selectedRange()) }
    }

    // MARK: Opening an attachment and dragging it out

    /// A click on an attachment that `mouseDown` took, until its mouse button comes up (`mouseUp(with:)`), or the drag that it
    /// became has begun. Nil the rest of the time.
    private struct AttachmentPress {
        /// What the attachment's token line is drawn as.
        let mark: AttachmentMark
        /// Where its preview or chip is drawn, in the coordinates of this view, and where the mouse went down in them.
        let rect: NSRect
        let location: NSPoint
        /// True while moving the mouse far enough can start a drag: for a file that is there, until one has started.
        var canDrag: Bool
    }

    private var attachmentPress: AttachmentPress?

    /// Says what happens when a drag of an attachment starts. Nil, the default, begins an `NSDraggingSession`, which runs
    /// until the mouse button is released (the window server drives it): a hosted test replaces this, so that no drag session is
    /// started on a runner, and receives the item and the event that start it.
    var attachmentDragPresenter: ((NSDraggingItem, NSEvent) -> Void)?

    /// The source of the drags that begin here: copy only (`AttachmentDragSource`). The drag session does not keep it.
    private let attachmentDragSource = AttachmentDragSource()

    /// What the layout manager draws for the token line that `point` is on, in the coordinates of this view: the token's
    /// range, the mark it is drawn from and the rectangle of the preview or chip. The point must be inside that rectangle, so
    /// the padding above and below a picture and the room beside a chip are not the attachment. Nil anywhere else.
    ///
    /// The line is found from the character that the layout manager puts under the point, and again from the start of the
    /// line at the same height: the characters of a token but the first have no glyph, and which character the layout
    /// manager names for a point beside the one glyph that is left is not something to rely on. The rectangle decides.
    private func attachmentTarget(atViewPoint point: NSPoint) -> (range: NSRange, mark: AttachmentMark, rect: NSRect)? {
        guard let layoutManager = layoutManager as? MarkupLayoutManager, layoutManager.hasAttachments,
            let container = textContainer, let storage = textStorage, storage.length > 0
        else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let text = storage.string as NSString
        for probe in [local, NSPoint(x: container.lineFragmentPadding, y: local.y)] {
            let found = layoutManager.characterIndex(
                for: probe, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            guard found != NSNotFound else { continue }
            let start = text.paragraphRange(for: NSRange(location: min(found, storage.length - 1), length: 0)).location
            guard let mark = storage.attribute(.scratchAttachment, at: start, effectiveRange: nil) as? AttachmentMark,
                let rect = layoutManager.attachmentRect(forTokenAt: start), rect.contains(local)
            else { continue }
            return (
                NSRange(location: start, length: AttachmentToken.lineLength), mark,
                rect.offsetBy(dx: origin.x, dy: origin.y)
            )
        }
        return nil
    }

    /// The attachment whose preview or chip is drawn at `point` (in the coordinates of this view): the range of its token and
    /// its id, or nil when `point` is anywhere else. It is the rectangle that `MarkupLayoutManager` draws in
    /// (`attachmentRect(forTokenAt:)`), like `labelHit(atViewPoint:)` for the label of a code block.
    func attachmentHit(atViewPoint point: NSPoint) -> (NSRange, AttachmentID)? {
        attachmentTarget(atViewPoint: point).map { ($0.range, $0.mark.id) }
    }

    /// A plain click on an attachment, which goes no further (never to `super.mouseDown`: AppKit would run a tracking loop
    /// and put the caret inside the token). The view takes the keyboard and the attachment is selected whole, which draws
    /// its outline. A double-click then opens its file, and when the mouse moves on with the button down a drag begins
    /// (`mouseDragged(with:)`). Returns false and does nothing when there is no attachment at `point`.
    private func pressAttachment(with event: NSEvent, atViewPoint point: NSPoint) -> Bool {
        guard let target = attachmentTarget(atViewPoint: point) else { return false }
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        setSelectedRange(target.range)
        let isDouble = event.clickCount == 2
        if isDouble { openAttachment(target.mark) }
        attachmentPress = AttachmentPress(
            mark: target.mark, rect: target.rect, location: point,
            canDrag: !isDouble && storedFile(of: target.mark) != nil)
        return true
    }

    /// The stored file of the attachment drawn as `mark`, when there is one to open or take out: the line is a preview or a
    /// chip of a file, and the file is there. A missing attachment, one that is still being copied and one whose file went
    /// away have none.
    private func storedFile(of mark: AttachmentMark) -> URL? {
        guard mark.kind == .image || mark.kind == .file, let url = styler?.catalog?.fileURL(mark.id),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    /// Opens the file of the attachment drawn as `mark` with its default application (`openURL`), or beeps and opens nothing
    /// when there is no file to open (a missing attachment).
    private func openAttachment(_ mark: AttachmentMark) {
        guard let url = storedFile(of: mark) else { return NSSound.beep() }
        openURL(url)
    }

    /// The mouse moved with the button down. After a press on an attachment, once it has moved `AttachmentDrag.threshold`
    /// points from where it went down, the attachment's stored file is dragged out of the note, and that is the one drag of
    /// the press. Nothing else moves while the button is down on an attachment: the view never began a selection.
    override func mouseDragged(with event: NSEvent) {
        guard let press = attachmentPress else { return super.mouseDragged(with: event) }
        guard press.canDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - press.location.x, point.y - press.location.y) >= AttachmentDrag.threshold else { return }
        attachmentPress?.canDrag = false
        beginAttachmentDrag(of: press.mark, in: press.rect, event: event)
    }

    /// The button came up: the press on an attachment is over. A mouse up that follows any other mouse down is the text
    /// view's.
    override func mouseUp(with event: NSEvent) {
        guard attachmentPress != nil else { return super.mouseUp(with: event) }
        attachmentPress = nil
    }

    /// Starts the drag of the stored file of the attachment drawn as `mark` in `rect`. The picture that follows the mouse is
    /// the preview, or the chip, as it is drawn in the note. Copy is the only thing a drop may do (`AttachmentDragSource`).
    private func beginAttachmentDrag(of mark: AttachmentMark, in rect: NSRect, event: NSEvent) {
        guard let url = storedFile(of: mark) else { return }
        let preview =
            mark.kind == .image
            ? (layoutManager as? MarkupLayoutManager)?.previews?.cachedImage(forID: mark.id, minPixelSize: 1) : nil
        let item = AttachmentDrag.draggingItem(for: url, mark: mark, preview: preview, frame: rect)
        if let attachmentDragPresenter {
            attachmentDragPresenter(item, event)
        } else {
            let session = beginDraggingSession(with: [item], event: event, source: attachmentDragSource)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }
    }

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
    /// it was, so the box can be clicked while typing somewhere else. The second click of a double-click on a box (and a
    /// third) is taken and does nothing, so a double-click ticks the box once. A plain click on the language label of a
    /// code block opens its menu and goes no further either (`showCodeBlockMenu`), unless the note cannot be edited. A
    /// plain click on the preview or the chip of an attachment selects it, and a double-click opens its file
    /// (`pressAttachment`), in a note that cannot be edited as well: a drag from it then takes the file out
    /// (`mouseDragged(with:)`). A ⌘-click on a link opens it (`openURL`) and goes no further: it places no caret, and it
    /// also works in a note that cannot be edited. Any other click, also one on a box, a label or an attachment with a
    /// modifier key held (⇧ extends the selection) or in a note that cannot be edited, is the text view's own: a plain
    /// click on a link places the caret and never opens anything.
    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let point = convert(event.locationInWindow, from: nil)
        attachmentPress = nil
        if modifiers.isDisjoint(with: [.shift, .command, .option, .control]) {
            // The second click of a double-click on a box is part of the gesture that the first one made: it would
            // untick the box again, or select a word. It is taken, and does nothing (a click that is not the first of its
            // series is not a toggle).
            if event.clickCount > 1, isEditable, checkboxMarker(atViewPoint: point) != nil { return }
            if toggleCheckbox(atViewPoint: point) || showCodeBlockMenu(atViewPoint: point)
                || pressAttachment(with: event, atViewPoint: point)
            {
                return
            }
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
    /// does nothing but beep when the note cannot be edited, when a fenced block is among the lines (inside a block
    /// nothing is formatting, so no marker is put there) and when the lines hold nothing it may change. The token line
    /// of an attachment is never one of them: a box in front of it would make it text.
    @objc func toggleChecklist(_ sender: Any?) {
        guard isEditable else { return NSSound.beep() }
        let paragraphs = coveringParagraphs()
        guard !styler.intersectsCodeBlock(paragraphs.range) else { return NSSound.beep() }
        let edit = ListEditing.toggleChecklist(
            paragraphs: paragraphs.text, start: paragraphs.range.location, selection: paragraphs.selection)
        guard edit.range.length > 0 || !edit.replacement.isEmpty else { return NSSound.beep() }
        apply(edit)
    }

    /// ⌘B (Format > Bold): the selection becomes `**selection**`, or loses its stars when it is a bold run; each line of a
    /// selection of several lines is its own run; a caret in a word makes the word bold, and in a run takes its stars off;
    /// and with a caret anywhere else `****` goes in with the caret between the pairs (`InlineEditing.toggleBold`). One
    /// undo step. It does nothing but beep when the note cannot be edited, when a fenced block is under the selection
    /// (inside a block every character is literal), for a rectangular selection, when the selection touches the token
    /// line of an attachment (a selected attachment, a selection that holds one, or a caret at either end of its line:
    /// stars there would make the token text, `InlineEditing.touchesAttachment`) and when the rule has nothing to bold (a
    /// selection of white space only). The name is not `toggleBold`: that is AppKit's action for the font panel, which a
    /// plain-text view must not answer.
    @objc func toggleBoldMarkers(_ sender: Any?) {
        guard isEditable, selectedRanges.count == 1 else { return NSSound.beep() }
        let paragraphs = coveringParagraphs()
        guard !styler.intersectsCodeBlock(paragraphs.range) else { return NSSound.beep() }
        guard
            !InlineEditing.touchesAttachment(
                paragraphs: paragraphs.text, start: paragraphs.range.location, selection: paragraphs.selection)
        else { return NSSound.beep() }
        guard
            let edit = InlineEditing.toggleBold(
                paragraphs: paragraphs.text, start: paragraphs.range.location, selection: paragraphs.selection)
        else { return NSSound.beep() }
        applyAndReveal(edit)
    }

    /// ⇧⌘U (Format > Mark as Checked): the checklist lines of the selection (the caret's line when there is none) are
    /// ticked when any of them is open, and unticked when all are ticked (`ListEditing.toggleCheckmarks`). One undo step,
    /// and the selection stays. It does nothing but beep when the note cannot be edited, when a fenced block is among the
    /// lines (nothing in a block is a checkbox), for a rectangular selection and when none of the lines is a checkbox.
    @objc func toggleCheckmarks(_ sender: Any?) {
        guard isEditable, selectedRanges.count == 1 else { return NSSound.beep() }
        let paragraphs = coveringParagraphs()
        guard !styler.intersectsCodeBlock(paragraphs.range) else { return NSSound.beep() }
        guard
            let edit = ListEditing.toggleCheckmarks(
                paragraphs: paragraphs.text, start: paragraphs.range.location, selection: paragraphs.selection)
        else { return NSSound.beep() }
        apply(edit)
    }
}
