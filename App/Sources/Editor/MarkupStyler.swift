import AppKit
import ScratchCode
import ScratchCore

/// Renders the markers of a note (spec §6.4): bullets, checkboxes, bold, inline code and links. It only sets
/// attributes on the text storage, so the stored characters, and with them copy, search and storage, never change.
///
/// - **Styling is by paragraph, from the core's parser.** A paragraph gets the base attributes and then what its
///   `MarkupSpan`s ask for (`MarkupAppearance`). Lines inside a fenced block are never parsed (`CodeBlockIndex`), and a
///   line that cannot hold a span is not parsed either (`MarkupParser.mayHaveSpans`).
/// - **A keystroke styles only the paragraphs it edited** (`textStorage(_:didProcessEditing:…)`). The fenced blocks
///   are carried over the edit, and the note is scanned for fences again only when the edit touched a fence line or
///   made a new one.
/// - **A note that is shown is styled in two steps** (`noteDidLoad(visibleRange:)`): the paragraphs around the visible
///   ones at once, so the first frame is right, and the rest in chunks, one per main run loop turn, after the frame
///   (`RunLoopIdle`). A note of 10,000 lines is on screen after the first step and fully styled a few turns later.
/// - **Markers are hidden unless the caret is at them.** The `**` of a closed bold run get the role `hidden`, which
///   `MarkupLayoutManager` turns into null glyphs. While the caret or selection touches the run (its edges included)
///   they are `revealed` and show dimmed, so that Backspace never deletes a character the owner cannot see.
/// - **A fenced block is a block.** Its fence lines are hidden (null glyphs, and a paragraph style that makes the line 6 pt
///   high) unless the caret or selection touches them, its lines are indented, and every paragraph carries a
///   `CodeBlockMark` that `MarkupLayoutManager` draws the tint and the label from. The colours of the code are not
///   this class's: `CodeBlockStyler` highlights each block on a background queue and applies the result when the
///   block's text is still the text that was highlighted. A keystroke in a block keeps the colours of its paragraph
///   until the new result replaces them (`resetAttributes`).
///
/// - **An attachment line is a picture.** A line that is exactly `[[attachment:<id>]]` (outside a fenced block) gets the role
///   `attachment` on every character but the first (null glyphs, `MarkupLayoutManager`), a clear first character that keeps
///   the line's own fragment, a paragraph style as high as what is drawn on it, and an `AttachmentMark` that the layout
///   manager draws the preview or the chip from. What the line shows, and how big, comes from `AttachmentCatalog` and the
///   text width, so the lines are styled again when either changes (`attachmentDidChange`, `refreshAttachmentLayout`).
///   Previews are decoded off the main thread (`AttachmentPreviews`), and one that arrives only invalidates the display.
///   Like the fenced blocks, the attachment lines above the window are styled whole when the note is shown, because the
///   scroll position depends on their height (`styleAttachmentLines`).
///
/// Styling never registers undo: attribute changes made to the text storage directly are not undo steps.
@MainActor
final class MarkupStyler: NSObject, @preconcurrency NSTextStorageDelegate {
    // MARK: Tuning

    /// Paragraphs styled above and below the visible ones when a note is shown.
    static let marginParagraphs = 200
    /// Paragraphs per chunk of the styling that follows.
    static let chunkParagraphs = 1_000
    /// A chunk stops after this long, so that a slow chunk (a Debug build, a note full of markers) does not hold up a key.
    static let chunkTimeBudget: Duration = .milliseconds(12)
    /// An edit that changes the code blocks restyles the paragraphs that moved in or out of one at once up to this many
    /// characters, and in chunks beyond it.
    static let synchronousRestyleLimit = 20_000
    /// An edit of more than this many characters (a big paste) is styled in chunks, like a note that is shown.
    static let largeEdit = 20_000
    /// A selection longer than this reveals no markers: selecting a whole note does not unhide all of them.
    static let selectionRevealLimit = 20_000
    /// The paragraphs one change of the selection looks at, at most.
    static let refreshParagraphLimit = 500
    /// What every attachment line starts with (`AttachmentToken`), searched for to find the lines above the window.
    private static let attachmentOpening = "[[attachment:"

    // MARK: State

    private weak var textView: NoteTextView?
    private var appearance: MarkupAppearance
    private var codeBlocks = CodeBlockIndex()
    /// True after a big edit, until the next chunk has scanned the note for fences.
    private var needsFenceRescan = false
    /// What is still to be styled, in document coordinates, first range first. A range is at the base attributes.
    private var pending: [NSRange] = []
    /// Changes whenever the job is cancelled, so that a chunk scheduled for an older note does nothing.
    private var jobGeneration = 0
    private var isChunkScheduled = false
    private var selection = NSRange(location: 0, length: 0)
    private var isLoading = false
    /// True while the styler itself edits the text storage, so that none of its own edits is taken for the owner's.
    private var isApplying = false
    /// Ranges in which the code blocks have to be looked at again once the text has been scanned for fences: the
    /// paragraphs of a big paste, whose blocks are found by a chunk (`runChunk`).
    private var blockProbes: [NSRange] = []
    /// What the last edit moved into or out of a block, outside of the paragraphs it edited: the layout manager makes the
    /// glyphs of these again when the edit is over (`editDidFinish`), which cannot be done from inside it.
    private var invalidationAfterEdit: NSRange?
    /// The ranges whose code colours (the layout manager's, `CodeBlockStyler`) are cleared when the last edit is over.
    private var coloursToClearAfterEdit: [NSRange] = []

    /// True when every paragraph of the text has been styled. False while a note is still being styled in chunks.
    private(set) var isFullyStyled = true

    /// What the attachments of the notes are: their rows, whether they are being copied. Set by `EditorViewController`
    /// before a note is shown. Without it every attachment line is a missing attachment.
    var catalog: AttachmentCatalog? {
        didSet { catalog?.onChange = { [weak self] id in self?.attachmentDidChange(id) } }
    }

    /// The decoded previews of the images that the notes hold, which `MarkupLayoutManager` draws.
    let previews = AttachmentPreviews()
    /// True once a line of the note shown has been styled as an attachment, until the next note is loaded. A note without
    /// one is never looked through for them.
    private var hasAttachmentLines = false {
        didSet { (textView?.layoutManager as? MarkupLayoutManager)?.hasAttachments = hasAttachmentLines }
    }
    /// The text width that the attachment lines were last sized for by `refreshAttachmentLayout`, or 0 for none yet.
    private var attachmentLayoutWidth: CGFloat = 0
    private var isAttachmentRefreshScheduled = false

    /// Colours the code of the fenced blocks and says which language each is (Plan 4).
    let codeBlockStyler: CodeBlockStyler

    init(textView: NoteTextView) {
        self.textView = textView
        appearance = MarkupAppearance(fontSize: FontSize.standard)
        codeBlockStyler = CodeBlockStyler(
            textView: textView,
            queue: DispatchQueue(label: "io.github.ldellisola.Scratch.highlight", qos: .userInitiated))
        super.init()
        (textView.layoutManager as? MarkupLayoutManager)?.previews = previews
        previews.onChange = { [weak self] id, decoded in self?.previewDidFinish(id, decoded: decoded) }
    }

    private var storage: NSTextStorage? { textView?.textStorage }

    /// The font size of the text, in points. Changing it styles all the text again, around what is visible first.
    var fontSize: Double {
        get { appearance.fontSize }
        set {
            guard newValue != appearance.fontSize else { return }
            appearance = MarkupAppearance(fontSize: newValue)
            restyleAfterFontChange()
        }
    }

    // MARK: Loading a note

    /// Call before replacing all the text (`NoteTextView.load`): the edit is a new note, not an edit to style.
    func beginLoad() {
        isLoading = true
        cancelJob()
    }

    /// Call after the text was replaced. The text gets the base attributes, and the code blocks of the new text are
    /// found. Nothing is styled yet: `noteDidLoad(visibleRange:)` does that.
    func endLoad() {
        isLoading = false
        selection = NSRange(location: 0, length: 0)
        (textView?.layoutManager as? MarkupLayoutManager)?.attachmentSelection = selection
        hasAttachmentLines = false
        attachmentLayoutWidth = 0
        needsFenceRescan = false
        guard let storage else { return }
        let length = storage.length
        codeBlocks = length > 0 ? scanCodeBlocks(in: storage) : CodeBlockIndex()
        isFullyStyled = length == 0
        if length > 0 {
            isApplying = true
            storage.setAttributes(appearance.base, range: NSRange(location: 0, length: length))
            isApplying = false
            // The colours of the code of the note that was shown are the layout manager's, and not gone with its text.
            codeBlockStyler.clearColours(in: [NSRange(location: 0, length: length)])
        }
    }

    /// Styles the note that was loaded: the paragraphs of `visibleRange` and `marginParagraphs` on each side of them now,
    /// and the rest in chunks of `chunkParagraphs`, one per main run loop turn. A note that is loaded or shown cancels
    /// the job of the one before. `visibleRange` is a range of the text and can be empty (an anchor).
    func noteDidLoad(visibleRange: NSRange) {
        cancelJob()
        guard let storage, storage.length > 0 else {
            isFullyStyled = true
            return
        }
        let text = storage.string as NSString
        let length = text.length
        let visible = text.paragraphRange(for: Self.clamp(visibleRange, toLength: length))
        let start = Self.paragraphStart(stepping: Self.marginParagraphs, backFrom: visible.location, in: text)
        let end = Self.paragraphEnd(stepping: Self.marginParagraphs, forwardFrom: NSMaxRange(visible), in: text)

        isApplying = true
        storage.beginEditing()
        let result = styleParagraphs(
            from: start, upTo: end, maxParagraphs: .max, deadline: nil, text: text, storage: storage)
        // The look of the blocks above the window too, before anything is laid out (see `styleBlocks`), and of the
        // attachment lines above it (see `styleAttachmentLines`).
        let blocksChanged = styleBlocks(startingBefore: end, text: text, storage: storage)
        let attachmentsChanged = styleAttachmentLines(startingBefore: start, text: text, storage: storage)
        storage.endEditing()
        isApplying = false
        if let changed = Self.union(Self.union(result.changed, blocksChanged), attachmentsChanged) {
            invalidate(changed)
        }
        // The blocks in what was just styled are coloured first: on the queue, and in the next turns.
        requestBlocks(intersecting: [NSRange(location: start, length: end - start)], in: storage)

        // After what is on screen: the text below it, then the text above it.
        pending = [
            NSRange(location: end, length: length - end), NSRange(location: 0, length: start),
        ].filter { $0.length > 0 }
        isFullyStyled = pending.isEmpty
        scheduleChunk()
    }

    // MARK: Asking

    /// True when `location` is in a fenced block, from the start of its opening fence line to the end of its closing
    /// one. Nothing in a block is a list or inline markup, so the editing rules do not apply there.
    func isInCodeBlock(_ location: Int) -> Bool {
        codeBlocks.contains(location)
    }

    /// True when `range` has a character in common with a fenced block (the fence lines included). A command that edits
    /// whole paragraphs, such as ⇧⌘L, asks it for the paragraphs it is about to change: the lines of a block are code and
    /// never get a marker, also when the selection starts and ends outside the block and holds it.
    func intersectsCodeBlock(_ range: NSRange) -> Bool {
        codeBlocks.intersects(range)
    }

    /// The block that holds `location`, from the start of its opening fence line to the end of its closing one, or nil.
    func codeBlock(containing location: Int) -> CodeBlockIndex.Block? {
        let blocks = codeBlocks.blocks
        let index = Self.firstBlockIndex(endingAtOrAfter: location, in: blocks)
        guard index < blocks.count, blocks[index].range.location <= location else { return nil }
        return blocks[index]
    }

    /// Every block of the note, in order (`CodeBlockStyler` looks for the blocks that a result is for).
    var codeBlockList: [CodeBlockIndex.Block] { codeBlocks.blocks }

    /// The `[?]` of the checkbox that the character at `characterIndex` belongs to, or nil when it is none (the space
    /// after a box and the text of the item are not).
    func checkboxMarker(at characterIndex: Int) -> NSRange? {
        guard let storage, characterIndex >= 0, characterIndex < storage.length else { return nil }
        var run = NSRange(location: 0, length: 0)
        let value = storage.attribute(
            .scratchMarker, at: characterIndex, longestEffectiveRange: &run,
            in: NSRange(location: 0, length: storage.length))
        guard let raw = value as? String, let role = MarkerRole(rawValue: raw),
            role == .checkboxOpen || role == .checkboxChecked
        else { return nil }
        return run
    }

    /// The URL of the link that the character at `characterIndex` is part of, or nil.
    func link(at characterIndex: Int) -> URL? {
        guard let storage, characterIndex >= 0, characterIndex < storage.length else { return nil }
        return storage.attribute(.scratchLink, at: characterIndex, effectiveRange: nil) as? URL
    }

    // MARK: Selection

    /// The caret or selection moved: the markers of the runs it touches are shown, and those of the runs it left are
    /// hidden again. Only the paragraphs of the old and the new selection are looked at, and nothing is written when no
    /// marker changes.
    func selectionDidChange(_ newSelection: NSRange) {
        let old = selection
        guard newSelection != old else { return }
        selection = newSelection
        guard !isLoading, !isApplying, let storage, storage.length > 0 else { return }
        attachmentSelectionDidChange(from: old, to: newSelection, in: storage)
        let text = storage.string as NSString
        var changed: NSRange?
        var looked: [NSRange] = []
        for candidate in [old, newSelection] where candidate.length <= Self.selectionRevealLimit {
            let paragraphs = text.paragraphRange(for: Self.clamp(candidate, toLength: text.length))
            guard !looked.contains(paragraphs) else { continue }
            looked.append(paragraphs)
            changed = Self.union(changed, refreshMarkers(in: paragraphs, text: text, storage: storage))
            changed = Self.union(changed, refreshFenceLines(in: paragraphs, text: text, storage: storage))
        }
        if let changed { invalidate(changed) }
        normalizeTypingAttributes()
    }

    /// True when `range` has a position in common with the selection, the positions at its two ends included.
    private func touchesSelection(_ range: NSRange) -> Bool {
        guard selection.length <= Self.selectionRevealLimit else { return false }
        return selection.location <= NSMaxRange(range) && NSMaxRange(selection) >= range.location
    }

    /// Gives the markers of the bold runs and inline code in `paragraphs` the role the selection asks for, and returns
    /// the range of the markers it changed.
    private func refreshMarkers(in paragraphs: NSRange, text: NSString, storage: NSTextStorage) -> NSRange? {
        let batch = ParagraphBatch(
            in: text, from: paragraphs.location, upTo: NSMaxRange(paragraphs), maxParagraphs: Self.refreshParagraphLimit
        )
        var changes: [(marker: NSRange, role: MarkerRole)] = []
        for index in batch.paragraphs.indices {
            let paragraph = batch.paragraphs[index]
            let line = batch.line(at: index)
            guard !codeBlocks.covers(paragraphStart: paragraph.location), MarkupParser.mayHaveSpans(in: line) else {
                continue
            }
            for span in MarkupParser.parseLine(String(decoding: line, as: UTF16.self), at: paragraph.location) {
                switch span.kind {
                case .bold, .inlineCode:
                    let role: MarkerRole = touchesSelection(span.range) ? .revealed : .hidden
                    for marker in span.markers where currentRole(at: marker.location, in: storage) != role {
                        changes.append((marker, role))
                    }
                case .bullet, .checkbox, .link:
                    continue
                }
            }
        }
        guard !changes.isEmpty else { return nil }

        isApplying = true
        storage.beginEditing()
        var changed: NSRange?
        for change in changes {
            storage.addAttributes(appearance.markerAttributes(change.role), range: change.marker)
            changed = Self.union(changed, change.marker)
        }
        storage.endEditing()
        isApplying = false
        return changed
    }

    /// Shows the fence lines in `paragraphs` that the selection touches and hides the others, and returns the range of the
    /// paragraphs it changed. A hidden fence line is null glyphs in a line of 6 pt; a shown one is in full, in
    /// `tertiaryLabelColor`, in the paragraph style of the lines of code.
    private func refreshFenceLines(in paragraphs: NSRange, text: NSString, storage: NSTextStorage) -> NSRange? {
        let blocks = codeBlocks.blocks
        guard !blocks.isEmpty else { return nil }
        var changes: [(line: NSRange, paragraph: NSRange, role: MarkerRole)] = []
        var index = Self.firstBlockIndex(endingAtOrAfter: paragraphs.location, in: blocks)
        while index < blocks.count, blocks[index].range.location < NSMaxRange(paragraphs) {
            let block = blocks[index]
            let lines = [
                NSRange(location: block.range.location, length: block.openingLineEnd - block.range.location),
                NSRange(location: block.closingLineStart, length: NSMaxRange(block.range) - block.closingLineStart),
            ]
            for line in lines where NSIntersectionRange(line, paragraphs).length > 0 {
                let role: MarkerRole = touchesSelection(line) ? .revealed : .fence
                guard currentRole(at: line.location, in: storage) != role else { continue }
                changes.append((line, text.paragraphRange(for: NSRange(location: line.location, length: 0)), role))
            }
            index += 1
        }
        guard !changes.isEmpty else { return nil }

        isApplying = true
        storage.beginEditing()
        var changed: NSRange?
        for change in changes {
            storage.addAttributes(appearance.markerAttributes(change.role), range: change.line)
            let style = change.role == .revealed ? MarkupAppearance.codeBodyStyle : MarkupAppearance.codeFenceStyle
            storage.addAttribute(.paragraphStyle, value: style, range: change.paragraph)
            changed = Self.union(changed, change.paragraph)
        }
        storage.endEditing()
        isApplying = false
        return changed
    }

    /// What is typed next takes the attributes of the text before the caret, which right after a block are the block's:
    /// the empty line under the closing fence would be 6 pt high. Right after a token line they are a clear colour in a
    /// line as high as a preview. Outside a block the note's own are put back.
    private func normalizeTypingAttributes() {
        guard let textView, selection.length == 0, !textView.hasMarkedText(), !codeBlocks.contains(selection.location)
        else { return }
        let typing = textView.typingAttributes
        guard typing[.scratchCodeBlock] != nil || typing[.scratchAttachment] != nil else { return }
        textView.typingAttributes = appearance.base
    }

    private func currentRole(at location: Int, in storage: NSTextStorage) -> MarkerRole? {
        (storage.attribute(.scratchMarker, at: location, effectiveRange: nil) as? String).flatMap(
            MarkerRole.init(rawValue:))
    }

    // MARK: Edits (NSTextStorageDelegate)

    /// The owner typed, pasted, deleted or undid something. The paragraphs it touched are styled again before AppKit
    /// lays them out. Attribute changes are not edits of the text (`.editedAttributes` only), and are ignored: they are
    /// the styler's own.
    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters), !isLoading, !isApplying else { return }
        storageDidEdit(EditMapping(editedRange: editedRange, changeInLength: delta), in: textStorage)
    }

    private func storageDidEdit(_ edit: EditMapping, in storage: NSTextStorage) {
        codeBlockStyler.textDidEdit(edit)
        // Carry what was known of the old text over the edit.
        let touchesFence = codeBlocks.touchesFenceLine(edit.replaced)
        codeBlocks.apply(edit)
        let blocksBeforeRescan = codeBlocks
        pending = pending.map { edit.mapped($0) }.filter { $0.length > 0 }
        blockProbes = blockProbes.map { edit.mapped($0) }.filter { $0.length > 0 }

        let text = storage.string as NSString
        let editedRange = Self.clamp(
            NSRange(location: edit.replaced.location, length: edit.newLength), toLength: text.length)
        let paragraphs = text.paragraphRange(for: editedRange)

        if edit.newLength > Self.largeEdit {
            // Too much to style inside a keystroke: a chunk does it, after the fences are scanned for.
            needsFenceRescan = true
            isApplying = true
            storage.setAttributes(appearance.base, range: paragraphs)
            isApplying = false
            pending.insert(paragraphs, at: 0)
            blockProbes.append(paragraphs)
            isFullyStyled = false
            scheduleChunk()
            return
        }

        let batch = ParagraphBatch(
            in: text, from: paragraphs.location, upTo: NSMaxRange(paragraphs), maxParagraphs: .max)
        let moved = touchesFence || batch.containsFenceLine() ? rescanCodeBlocks(in: storage) : []
        let composed = composedAttributes(in: editedRange, storage: storage)

        isApplying = true
        storage.beginEditing()
        resetAttributes(of: paragraphs, batch: batch, keepingCodeOf: blocksBeforeRescan, in: storage)
        _ = styleBatch(batch, in: storage)
        restoreComposedAttributes(composed, in: storage)
        // The paragraphs that moved into or out of a block, other than the ones just styled.
        let movedChanged = restyle(moved.filter { !Self.contains(paragraphs, $0) }, text: text, storage: storage)
        refreshFirstCodeLines(near: paragraphs, in: storage)
        storage.endEditing()
        isApplying = false
        invalidationAfterEdit = Self.union(invalidationAfterEdit, movedChanged)
        coloursToClearAfterEdit.append(contentsOf: moved)
        // The blocks that the edit is in, or that it changed, are coloured again for the text they have now.
        requestBlocks(intersecting: [paragraphs] + moved, in: storage)
    }

    // MARK: Composed text

    /// The attributes that mean "this text is being composed" (plan 6 task 5): the underline and the clause segment that
    /// an input method hands over with its text, and the keys of the view's `markedTextAttributes`. Resetting a
    /// paragraph's attributes would take them off text that is still being composed, and the owner would no longer see
    /// which part of it is not entered yet. The keys that the styler sets on every paragraph itself (the font, the
    /// colours, the paragraph style: `stylerOwnedKeys`) are kept only at the value that `markedTextAttributes` gives
    /// them, which is the marked-text highlight (by default, macOS 26.6, a background and a foreground colour). The edit
    /// that puts composed text in also gives it the attributes of the text next to it, so a colour or a font that
    /// differs from `markedTextAttributes` is the neighbour's and not the input method's, and keeping it would paint
    /// composed text next to inline code or a link as that.
    private func keptComposedAttributes(
        _ attributes: [NSAttributedString.Key: Any], marked: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        attributes.filter { entry in
            if Self.stylerOwnedKeys.contains(entry.key) {
                guard let expected = marked[entry.key] as? NSObject, let actual = entry.value as? NSObject else {
                    return false
                }
                return expected.isEqual(actual)
            }
            return Self.composedKeys.contains(entry.key) || marked[entry.key] != nil
        }
    }

    /// What marks composed text whatever the view's `markedTextAttributes` say.
    private static let composedKeys: Set<NSAttributedString.Key> = [
        .underlineStyle, .underlineColor, .markedClauseSegment,
    ]

    /// What the styler sets on every paragraph itself, so that an edit's inherited value is only worth keeping when it
    /// is the value of `markedTextAttributes`.
    private static let stylerOwnedKeys: Set<NSAttributedString.Key> = [
        .font, .foregroundColor, .backgroundColor, .paragraphStyle,
    ]

    /// The attributes of composed text in `range`, which holds what an edit has just put in, to put back after the
    /// paragraph has been styled. Only text that `setMarkedText` is putting in is composed (`isSettingMarkedText`): the
    /// edit of typing, a paste or an input method's final `insertText` keeps none of it, so a link's underline that
    /// typed text took from the text before it is the styler's to settle. Empty when nothing is being composed, and when
    /// the edit carries none of the attributes, which is what AppKit hands the text storage on macOS 26.6: the composed
    /// characters have the typing attributes only at the end of the edit (measured on CI, plan 6 task 5), so this
    /// holds for a version that gives them the input method's attributes in the edit itself.
    private func composedAttributes(
        in range: NSRange, storage: NSTextStorage
    ) -> [(range: NSRange, attributes: [NSAttributedString.Key: Any])] {
        guard let textView, textView.isSettingMarkedText, range.length > 0, NSMaxRange(range) <= storage.length else {
            return []
        }
        // Typed as an optional, whichever way the SDK declares the property.
        let markedAttributes: [NSAttributedString.Key: Any]? = textView.markedTextAttributes
        let marked = markedAttributes ?? [:]
        var runs: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: range, options: []) { attributes, run, _ in
            let kept = keptComposedAttributes(attributes, marked: marked)
            if !kept.isEmpty { runs.append((run, kept)) }
        }
        return runs
    }

    private func restoreComposedAttributes(
        _ runs: [(range: NSRange, attributes: [NSAttributedString.Key: Any])], in storage: NSTextStorage
    ) {
        for run in runs where NSMaxRange(run.range) <= storage.length {
            storage.addAttributes(run.attributes, range: run.range)
        }
    }

    /// Called when the edit that `storageDidEdit` styled is over (`NoteTextView.didChangeText`), which is when the layout
    /// manager knows about it and can be told to generate the glyphs of what moved into or out of a block again: the
    /// role of a fence line decides whether it has glyphs, and the line did not change.
    func editDidFinish() {
        if !coloursToClearAfterEdit.isEmpty {
            // Paragraphs that left a block lose the colours of its code (the layout manager's, not the text's).
            codeBlockStyler.clearColours(in: coloursToClearAfterEdit)
            coloursToClearAfterEdit = []
        }
        guard let range = invalidationAfterEdit else { return }
        invalidationAfterEdit = nil
        invalidate(range)
    }

    /// Gives the paragraphs that an edit touched the base attributes again, so that what the styler adds comes out as if
    /// the paragraph had never been styled. The lines of a block that was a block before the edit and still is one keep
    /// the mark of the opening fence line, which holds a label that was detected (`openingMark`), and are left alone
    /// otherwise: the colours of their code are the layout manager's and stay until `CodeBlockStyler` has the new ones.
    private func resetAttributes(
        of paragraphs: NSRange, batch: ParagraphBatch, keepingCodeOf before: CodeBlockIndex, in storage: NSTextStorage
    ) {
        guard paragraphs.length > 0 else { return }
        var keep: [NSRange] = []
        if !before.blocks.isEmpty, !codeBlocks.blocks.isEmpty {
            for paragraph in batch.paragraphs
            where before.covers(paragraphStart: paragraph.location)
                && codeBlocks.covers(paragraphStart: paragraph.location)
            {
                if let last = keep.last, NSMaxRange(last) == paragraph.location {
                    keep[keep.count - 1] = NSRange(location: last.location, length: last.length + paragraph.length)
                } else {
                    keep.append(paragraph)
                }
            }
        }
        var cursor = paragraphs.location
        for run in keep {
            if run.location > cursor {
                storage.setAttributes(appearance.base, range: NSRange(location: cursor, length: run.location - cursor))
            }
            for key in [
                NSAttributedString.Key.scratchMarker, .scratchLink, .underlineStyle, .strikethroughStyle,
                .backgroundColor,
            ] {
                storage.removeAttribute(key, range: run)
            }
            storage.addAttribute(.font, value: appearance.regularFont, range: run)
            cursor = NSMaxRange(run)
        }
        if cursor < NSMaxRange(paragraphs) {
            storage.setAttributes(
                appearance.base, range: NSRange(location: cursor, length: NSMaxRange(paragraphs) - cursor))
        }
    }

    // MARK: Code blocks

    private func scanCodeBlocks(in storage: NSTextStorage) -> CodeBlockIndex {
        let text = storage.string as NSString
        // Most notes have no fence at all, and a search for one is much faster than the scan.
        guard text.range(of: "```").location != NSNotFound else { return CodeBlockIndex() }
        var units = [UInt16](repeating: 0, count: text.length)
        units.withUnsafeMutableBufferPointer { pointer in
            text.getCharacters(pointer.baseAddress!, range: NSRange(location: 0, length: pointer.count))
        }
        return CodeBlockIndex(units: units)
    }

    /// Scans the note for fenced blocks again, and returns the ranges whose paragraphs moved into or out of one.
    private func rescanCodeBlocks(in storage: NSTextStorage) -> [NSRange] {
        let old = codeBlocks
        codeBlocks = scanCodeBlocks(in: storage)
        needsFenceRescan = false
        // A paragraph that is in a block before and after can still have been another line of it (the closing fence of one
        // block is the opening fence of the next when a fence in between goes): a block that is not as it was is styled
        // again whole.
        return codeBlocks.changedRanges(comparedTo: old) + Self.ranges(of: codeBlocks.blocks, notIn: old.blocks)
    }

    /// The ranges of the blocks of `new` that are not in `old` exactly (both are sorted and do not overlap).
    private static func ranges(of new: [CodeBlockIndex.Block], notIn old: [CodeBlockIndex.Block]) -> [NSRange] {
        var result: [NSRange] = []
        var index = 0
        for block in new {
            while index < old.count, old[index].range.location < block.range.location { index += 1 }
            if index < old.count, old[index] == block { continue }
            result.append(block.range)
        }
        return result
    }

    // MARK: Asking CodeBlockStyler

    /// The index of the first of the sorted `blocks` that ends at or after `location`, or `blocks.count`.
    private static func firstBlockIndex(endingAtOrAfter location: Int, in blocks: [CodeBlockIndex.Block]) -> Int {
        var low = 0
        var high = blocks.count
        while low < high {
            let middle = (low + high) / 2
            if NSMaxRange(blocks[middle].range) < location { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// Asks `CodeBlockStyler` to colour the blocks that share a character with one of `ranges`.
    private func requestBlocks(intersecting ranges: [NSRange], in storage: NSTextStorage) {
        let blocks = codeBlocks.blocks
        guard !blocks.isEmpty else { return }
        var found: [NSRange] = []
        for range in ranges {
            let end = max(NSMaxRange(range), range.location + 1)
            var index = Self.firstBlockIndex(endingAtOrAfter: range.location, in: blocks)
            while index < blocks.count, blocks[index].range.location < end {
                let block = blocks[index].range
                if NSMaxRange(block) > range.location, !found.contains(block) { found.append(block) }
                index += 1
            }
        }
        if !found.isEmpty { codeBlockStyler.blocksDidChange(found, in: storage) }
    }

    /// Asks `CodeBlockStyler` to colour the blocks that start in one of `ranges` (the paragraphs that a chunk styled).
    private func requestBlocks(startingIn ranges: [NSRange], in storage: NSTextStorage) {
        let blocks = codeBlocks.blocks
        guard !blocks.isEmpty else { return }
        var found: [NSRange] = []
        for range in ranges {
            var index = Self.firstBlockIndex(endingAtOrAfter: range.location, in: blocks)
            while index < blocks.count, blocks[index].range.location < NSMaxRange(range) {
                if blocks[index].range.location >= range.location { found.append(blocks[index].range) }
                index += 1
            }
        }
        if !found.isEmpty { codeBlockStyler.blocksDidChange(found, in: storage) }
    }

    // MARK: Styling paragraphs

    /// What `styleParagraphs` did: how many paragraphs it went through, where it stopped, and what it changed.
    private struct StyleResult {
        var count = 0
        var end = 0
        var changed: NSRange?
    }

    /// Styles the paragraphs that start in `start..<end`, at most `maxParagraphs` of them and until `deadline`. They
    /// have the base attributes already. Call it inside `beginEditing()` and `endEditing()`.
    private func styleParagraphs(
        from start: Int, upTo end: Int, maxParagraphs: Int, deadline: ContinuousClock.Instant?, text: NSString,
        storage: NSTextStorage
    ) -> StyleResult {
        let batch = ParagraphBatch(
            in: text, from: start, upTo: end, maxParagraphs: maxParagraphs, deadline: deadline)
        var result = styleBatch(batch, in: storage)
        result.count = batch.paragraphs.count
        result.end = NSMaxRange(batch.range)
        return result
    }

    private func styleBatch(_ batch: ParagraphBatch, in storage: NSTextStorage) -> StyleResult {
        var result = StyleResult()
        // The lines of code of a block that follow one another are given their attributes in one call.
        var codeRun: NSRange?
        var didPrefetchAttachments = false
        func flushCodeRun() {
            guard let run = codeRun else { return }
            // Not in `result.changed`: nothing about the glyphs of a line of code changes, and the attributes' own edit
            // lays the paragraphs out again.
            styleCodeBody(run, in: storage)
            codeRun = nil
        }
        for index in batch.paragraphs.indices {
            let paragraph = batch.paragraphs[index]
            let line = batch.line(at: index)
            if let block = block(coveringParagraphStart: paragraph.location) {
                let part = Self.part(ofParagraphAt: paragraph.location, in: block)
                if part == .body {
                    if isFirstCodeLine(at: paragraph.location, of: block, in: storage) {
                        // The label reaches into this line, so it alone has room kept for it (`firstCodeLineStyle`).
                        flushCodeRun()
                        styleCodeBody(
                            paragraph, style: firstCodeLineStyle(of: block, in: storage), in: storage)
                    } else if let run = codeRun, NSMaxRange(run) == paragraph.location {
                        codeRun = NSRange(location: run.location, length: run.length + paragraph.length)
                    } else {
                        flushCodeRun()
                        codeRun = paragraph
                    }
                } else {
                    flushCodeRun()
                    let info =
                        part == .opening ? CodeBlockParts.info(ofFenceLine: String(decoding: line, as: UTF16.self)) : ""
                    if styleFenceLine(of: paragraph, part: part, contentLength: line.count, info: info, in: storage) {
                        result.changed = Self.union(result.changed, paragraph)
                    }
                }
                continue
            }
            flushCodeRun()
            // A line of exactly the length of a token that starts with its bracket is looked at closely: the rest are not.
            if line.count == AttachmentToken.lineLength, line.first == 0x5B,
                let id = AttachmentToken.id(inLine: String(decoding: line, as: UTF16.self))
            {
                if !didPrefetchAttachments {
                    didPrefetchAttachments = true
                    prefetchAttachments(in: batch, from: index)
                }
                if styleAttachmentLine(of: paragraph, id: id, in: storage) {
                    result.changed = Self.union(result.changed, paragraph)
                }
                continue
            }
            guard MarkupParser.mayHaveSpans(in: line) else { continue }
            let spans = MarkupParser.parseLine(String(decoding: line, as: UTF16.self), at: paragraph.location)
            guard !spans.isEmpty else { continue }
            apply(spans, toParagraph: paragraph, in: storage)
            result.changed = Self.union(result.changed, paragraph)
        }
        flushCodeRun()
        return result
    }

    // MARK: Styling code blocks

    /// The block that the paragraph starting at `location` is in, or nil: the same as `CodeBlockIndex.covers`.
    private func block(coveringParagraphStart location: Int) -> CodeBlockIndex.Block? {
        let blocks = codeBlocks.blocks
        let index = Self.firstBlockIndex(endingAtOrAfter: location + 1, in: blocks)
        guard index < blocks.count, blocks[index].range.location <= location else { return nil }
        return blocks[index]
    }

    /// Which line of `block` the paragraph that starts at `location` is.
    private static func part(ofParagraphAt location: Int, in block: CodeBlockIndex.Block) -> CodeBlockPart {
        if location == block.range.location { return .opening }
        if location == block.closingLineStart { return .closing }
        return .body
    }

    /// Gives every block that starts before `limit` its look at once: its fence lines and the lines of code. A line's
    /// height depends on it (a fence line is 6 pt high, a line of code is indented and wraps sooner), and where a note is
    /// scrolled to is worked out from the layout of what is above that: a block that was styled after the scroll was set
    /// moved the note under the reader (the line at the top of a note shown again was three lines off, on the CI). The
    /// styling by paragraph (`styleBatch`) does not wait for the chunks above the window; this does one pass for each
    /// block, whatever its size, and what it did is not done again. Returns what it changed.
    private func styleBlocks(startingBefore limit: Int, text: NSString, storage: NSTextStorage) -> NSRange? {
        var changed: NSRange?
        for block in codeBlocks.blocks {
            guard block.range.location < limit else { break }
            let opening = text.paragraphRange(for: NSRange(location: block.range.location, length: 0))
            let closing = text.paragraphRange(for: NSRange(location: block.closingLineStart, length: 0))
            let openingLength = block.openingLineEnd - block.range.location
            let info = CodeBlockParts.info(
                ofFenceLine: text.substring(with: NSRange(location: block.range.location, length: openingLength)))
            if styleFenceLine(of: opening, part: .opening, contentLength: openingLength, info: info, in: storage) {
                changed = Self.union(changed, opening)
            }
            // The first line of code has room kept for the label, the others do not.
            let bodyEnd = closing.location
            if bodyEnd > NSMaxRange(opening) {
                let first = NSIntersectionRange(
                    text.paragraphRange(for: NSRange(location: NSMaxRange(opening), length: 0)),
                    NSRange(location: NSMaxRange(opening), length: bodyEnd - NSMaxRange(opening)))
                styleCodeBody(first, style: firstCodeLineStyle(of: block, in: storage), in: storage)
                styleCodeBody(NSRange(location: NSMaxRange(first), length: bodyEnd - NSMaxRange(first)), in: storage)
            }
            let closingLength = NSMaxRange(block.range) - block.closingLineStart
            if styleFenceLine(of: closing, part: .closing, contentLength: closingLength, info: "", in: storage) {
                changed = Self.union(changed, closing)
            }
        }
        return changed
    }

    /// Gives the lines of code in `range` (whole paragraphs, between two fence lines) their indent, `style`, and their mark,
    /// unless the first of them has both. Returns true when it wrote them. `style` is the style of a line of code, and for
    /// the first line of a block with a label the one that keeps the line clear of the label (`firstCodeLineStyle`).
    @discardableResult
    private func styleCodeBody(
        _ range: NSRange, style: NSParagraphStyle = MarkupAppearance.codeBodyStyle, in storage: NSTextStorage
    ) -> Bool {
        guard range.length > 0 else { return false }
        let current = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let mark = storage.attribute(.scratchCodeBlock, at: range.location, effectiveRange: nil) as? CodeBlockMark
        if current == style, mark == CodeBlockMark.body { return false }
        storage.addAttributes([.paragraphStyle: style, .scratchCodeBlock: CodeBlockMark.body], range: range)
        return true
    }

    // MARK: The first line of code

    /// True when the paragraph that starts at `location`, a line of code of `block`, is the first of them: the one right
    /// after the opening fence line. Only a paragraph that starts within a line break of the end of that line is looked at.
    private func isFirstCodeLine(at location: Int, of block: CodeBlockIndex.Block, in storage: NSTextStorage) -> Bool {
        guard location > block.openingLineEnd, location - block.openingLineEnd <= 2 else { return false }
        let text = storage.string as NSString
        return NSMaxRange(text.paragraphRange(for: NSRange(location: block.range.location, length: 0))) == location
    }

    /// What the label of `block` says: the name on its opening fence line's mark, which is what `CodeBlockStyler` and
    /// `styleFenceLine` write, or, for a fence line that is not styled yet (a long note is styled in chunks), what its fence
    /// names. Empty for a block with no label.
    private func labelName(of block: CodeBlockIndex.Block, in storage: NSTextStorage) -> String {
        if let mark = storage.attribute(.scratchCodeBlock, at: block.range.location, effectiveRange: nil)
            as? CodeBlockMark, mark.part == .opening
        {
            return mark.name
        }
        let text = storage.string as NSString
        let info = CodeBlockParts.info(
            ofFenceLine: text.substring(
                with: NSRange(location: block.range.location, length: block.openingLineEnd - block.range.location)))
        return CodeLanguage.fromFence(info)?.label ?? info
    }

    /// The paragraph style of the first line of code of `block`: the room that its label takes from the right is kept clear
    /// (`MarkupAppearance.firstCodeLineStyle`), so that the label never covers code and a click on the code never opens its
    /// menu (plan 5 task 7, a 0.4.0 follow-up).
    private func firstCodeLineStyle(of block: CodeBlockIndex.Block, in storage: NSTextStorage) -> NSParagraphStyle {
        appearance.firstCodeLineStyle(labelName: labelName(of: block, in: storage))
    }

    /// Gives the first line of code of `block` the style it must have, and the lines after it that the edit can have moved
    /// the first line's style onto the style of any other line of code. The second line is always looked at: the line that
    /// was the first can have become the second (a line was split or inserted above it). With a `window` (the range of the
    /// paragraphs that an edit changed and the two after them), every line of code in it is looked at too, one by one: an
    /// edit that inserts several lines, or splits the first line in two, leaves the old first line's style on a line that
    /// is the third, the fourth, or further down. Nothing is written for a line that is as it should be.
    private func refreshFirstCodeLines(
        of block: CodeBlockIndex.Block, restyling window: NSRange? = nil, in storage: NSTextStorage
    ) {
        let text = storage.string as NSString
        let opening = text.paragraphRange(for: NSRange(location: block.range.location, length: 0))
        let bodyStart = NSMaxRange(opening)
        guard bodyStart < block.closingLineStart else { return }
        let first = text.paragraphRange(for: NSRange(location: bodyStart, length: 0))
        styleCodeBody(first, style: firstCodeLineStyle(of: block, in: storage), in: storage)
        guard NSMaxRange(first) < block.closingLineStart else { return }
        let second = text.paragraphRange(for: NSRange(location: NSMaxRange(first), length: 0))
        styleCodeBody(second, in: storage)
        guard let window else { return }
        // The lines before the window were not touched, so they are as they were: only one line ever has the first line's style.
        var location = max(NSMaxRange(second), window.location)
        let limit = min(NSMaxRange(window), block.closingLineStart)
        while location < limit {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            styleCodeBody(paragraph, in: storage)
            location = NSMaxRange(paragraph)
        }
    }

    /// Does `refreshFirstCodeLines(of:restyling:in:)` for the blocks that `range`, and a character on each side of it,
    /// touches, with a window of `range` and the two paragraphs after it. Called inside `beginEditing()` and `endEditing()`,
    /// after an edit has been styled, with the paragraphs the edit changed: an edit that splits the first line of code or
    /// takes it away leaves its style on a paragraph that is no longer the first, which `range` does not always include. What
    /// is left of the old first line sits right after the text that came in: in the paragraph that starts at the end of
    /// `range` or, when the edit was in the opening fence line (whose tail is a paragraph of its own), in the one after that.
    private func refreshFirstCodeLines(near range: NSRange, in storage: NSTextStorage) {
        let blocks = codeBlocks.blocks
        guard !blocks.isEmpty else { return }
        let text = storage.string as NSString
        var end = NSMaxRange(range)
        for _ in 0..<2 {
            guard end < text.length else { break }
            end = NSMaxRange(text.paragraphRange(for: NSRange(location: end, length: 0)))
        }
        let window = NSRange(location: range.location, length: end - range.location)
        let limit = NSMaxRange(range) + 1
        var index = Self.firstBlockIndex(endingAtOrAfter: max(range.location - 1, 0), in: blocks)
        while index < blocks.count, blocks[index].range.location <= limit {
            refreshFirstCodeLines(of: blocks[index], restyling: window, in: storage)
            index += 1
        }
    }

    /// `CodeBlockStyler` wrote the label of the block that opens at `location` (a language that was detected, or none any
    /// more): the first line of code is given the room for it, or loses it. Call it inside `beginEditing()` and
    /// `endEditing()`, after the label is written.
    func labelDidChange(inBlockAt location: Int, in storage: NSTextStorage) {
        guard let block = codeBlock(containing: location), block.range.location == location else { return }
        refreshFirstCodeLines(of: block, in: storage)
    }

    /// Styles a fence line of a block: its characters are hidden, or shown while the selection touches them, and its
    /// paragraph is 6 pt high when they are hidden. The opening one carries the label of the block, and `info` is the name
    /// on its fence. Returns false, and writes nothing, when the line is as it should be already.
    @discardableResult
    private func styleFenceLine(
        of paragraph: NSRange, part: CodeBlockPart, contentLength: Int, info: String, in storage: NSTextStorage
    ) -> Bool {
        let content = NSRange(location: paragraph.location, length: contentLength)
        let isShown = touchesSelection(content)
        let role: MarkerRole = isShown ? .revealed : .fence
        let style = isShown ? MarkupAppearance.codeBodyStyle : MarkupAppearance.codeFenceStyle
        let mark = part == .opening ? openingMark(info: info, at: paragraph, in: storage) : CodeBlockMark.closing
        if currentRole(at: paragraph.location, in: storage) == role,
            storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
                == style,
            storage.attribute(.scratchCodeBlock, at: paragraph.location, effectiveRange: nil) as? CodeBlockMark == mark
        {
            return false
        }
        storage.addAttributes(appearance.markerAttributes(role), range: content)
        storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
        storage.addAttribute(.scratchCodeBlock, value: mark, range: paragraph)
        return true
    }

    /// The mark of an opening fence line. A fence that names its language says it at once. One that does not has the
    /// language that was detected last, until a new detection says otherwise, so that the label does not go away while a
    /// result is on its way; before the first one it has no label.
    private func openingMark(info: String, at paragraph: NSRange, in storage: NSTextStorage) -> CodeBlockMark {
        if !info.isEmpty {
            let language = CodeLanguage.fromFence(info)
            return CodeBlockMark(part: .opening, language: language, isDetected: false, name: language?.label ?? info)
        }
        if let previous = storage.attribute(.scratchCodeBlock, at: paragraph.location, effectiveRange: nil)
            as? CodeBlockMark, previous.part == .opening, previous.isDetected
        {
            return previous
        }
        return CodeBlockMark(part: .opening, language: nil, isDetected: true, name: "")
    }

    /// Gives the paragraphs of `ranges` the base attributes and styles them: now when they are few, in chunks when
    /// they are many. Returns what it changed now.
    private func restyle(_ ranges: [NSRange], text: NSString, storage: NSTextStorage) -> NSRange? {
        var changed: NSRange?
        for range in ranges {
            let clamped = Self.clamp(range, toLength: text.length)
            guard clamped.length > 0 else { continue }
            let paragraphs = text.paragraphRange(for: clamped)
            storage.setAttributes(appearance.base, range: paragraphs)
            changed = Self.union(changed, paragraphs)
            if paragraphs.length <= Self.synchronousRestyleLimit {
                let result = styleParagraphs(
                    from: paragraphs.location, upTo: NSMaxRange(paragraphs), maxParagraphs: .max, deadline: nil,
                    text: text, storage: storage)
                changed = Self.union(changed, result.changed)
            } else {
                pending.insert(paragraphs, at: 0)
                isFullyStyled = false
            }
        }
        if !pending.isEmpty { scheduleChunk() }
        return changed
    }

    /// Adds what `spans`, the spans of the paragraph at `paragraph`, ask for. The list span, if any, comes first.
    private func apply(_ spans: [MarkupSpan], toParagraph paragraph: NSRange, in storage: NSTextStorage) {
        for span in spans {
            switch span.kind {
            case .bullet:
                storage.addAttributes(appearance.markerAttributes(.bullet), range: span.markers[0])
                indent(paragraph, to: span, in: storage)
            case .checkbox(let checked, _):
                storage.addAttributes(
                    appearance.markerAttributes(checked ? .checkboxChecked : .checkboxOpen), range: span.markers[0])
                indent(paragraph, to: span, in: storage)
                if checked, span.content.length > 0 {
                    storage.addAttributes(MarkupAppearance.tickedTextAttributes, range: span.content)
                }
            case .bold:
                storage.addAttribute(.font, value: appearance.boldFont, range: span.content)
                setRunMarkers(of: span, in: storage)
            case .inlineCode:
                storage.addAttributes(MarkupAppearance.inlineCodeAttributes, range: span.content)
                setRunMarkers(of: span, in: storage)
            case .link(let url):
                storage.addAttributes(MarkupAppearance.linkAttributes(for: url), range: span.range)
            }
        }
    }

    /// The hanging indent of a list line: its wrapped lines start where the text of the item starts.
    private func indent(_ paragraph: NSRange, to span: MarkupSpan, in storage: NSTextStorage) {
        let characters = span.content.location - paragraph.location
        storage.addAttribute(.paragraphStyle, value: appearance.indentStyle(characters: characters), range: paragraph)
    }

    /// The markers of a bold run or inline code are hidden, or shown while the selection touches the run.
    private func setRunMarkers(of span: MarkupSpan, in storage: NSTextStorage) {
        let role: MarkerRole = touchesSelection(span.range) ? .revealed : .hidden
        for marker in span.markers { storage.addAttributes(appearance.markerAttributes(role), range: marker) }
    }

    // MARK: Attachments

    /// The text width that an attachment line is sized for: the text container's less its padding on each side, or
    /// `AttachmentMetrics.unknownWidth` before the text view has a width (a note shown at launch is styled first).
    private func currentAttachmentWidth() -> CGFloat {
        guard let container = textView?.textContainer else { return AttachmentMetrics.unknownWidth }
        let width = container.size.width - 2 * container.lineFragmentPadding
        return width > 1 ? width : AttachmentMetrics.unknownWidth
    }

    /// Reads the attachments of the token lines of `batch`, from the paragraph at `start` on, with one query, so that
    /// styling them does not make one read each.
    private func prefetchAttachments(in batch: ParagraphBatch, from start: Int) {
        guard let catalog else { return }
        var ids: [AttachmentID] = []
        for index in start..<batch.paragraphs.count {
            let line = batch.line(at: index)
            guard line.count == AttachmentToken.lineLength, line.first == 0x5B,
                let id = AttachmentToken.id(inLine: String(decoding: line, as: UTF16.self))
            else { continue }
            ids.append(id)
        }
        catalog.preload(ids)
    }

    /// What the attachment line of `id` is drawn as and how big: a missing attachment for an id with no row, a file that is
    /// not there or an image that cannot be decoded, "Copying…" while the copy runs, a preview scaled into the text width
    /// for an image, and a chip for any other file.
    private func makeAttachmentMark(for id: AttachmentID) -> AttachmentMark {
        let available = currentAttachmentWidth()
        let chip = AttachmentMetrics.chipSize(availableWidth: available)
        guard let catalog, let attachment = catalog.attachment(id), let url = catalog.fileURL(id) else {
            return AttachmentMark(id: id, kind: .missing, displaySize: chip, fileName: "", byteSize: nil)
        }
        if catalog.isCopying(id) {
            return AttachmentMark(
                id: id, kind: .copying, displaySize: chip, fileName: attachment.fileName, byteSize: attachment.byteSize,
                icon: catalog.icon(for: attachment, fileURL: nil))
        }
        guard FileManager.default.fileExists(atPath: url.path), !catalog.isUndecodable(id) else {
            return AttachmentMark(
                id: id, kind: .missing, displaySize: chip, fileName: attachment.fileName, byteSize: attachment.byteSize)
        }
        if attachment.isImage, let width = attachment.pixelWidth, let height = attachment.pixelHeight, width > 0,
            height > 0
        {
            let size = AttachmentMetrics.imageSize(pixelWidth: width, pixelHeight: height, availableWidth: available)
            let scale = textView?.window?.backingScaleFactor ?? 2
            return AttachmentMark(
                id: id, kind: .image, displaySize: size, fileName: attachment.fileName, byteSize: attachment.byteSize,
                fileURL: url, previewPixelSize: AttachmentMetrics.previewPixelSize(for: size, scale: scale))
        }
        return AttachmentMark(
            id: id, kind: .file, displaySize: chip, fileName: attachment.fileName, byteSize: attachment.byteSize,
            icon: catalog.icon(for: attachment, fileURL: url))
    }

    /// Gives the token line at `paragraph` (the line and its line break) its look: the role `attachment` on every character
    /// but the first, a clear first character, a paragraph style as high as what is drawn on it, and the mark that the
    /// layout manager draws from. An image's preview is asked for, so that it is on its way before the line is drawn.
    /// Returns false, and writes nothing, when the line looks as it should already, so that a change of the width that
    /// leaves the size of every preview alone styles nothing. Call it inside `beginEditing()` and `endEditing()`.
    @discardableResult
    private func styleAttachmentLine(of paragraph: NSRange, id: AttachmentID, in storage: NSTextStorage) -> Bool {
        let mark = makeAttachmentMark(for: id)
        if let current = storage.attribute(.scratchAttachment, at: paragraph.location, effectiveRange: nil)
            as? AttachmentMark, current.hasSameLook(as: mark)
        {
            return false
        }
        let lineHeight = AttachmentMetrics.lineHeight(forDisplayHeight: mark.displaySize.height)
        storage.addAttributes(
            [
                .scratchAttachment: mark,
                .paragraphStyle: MarkupAppearance.attachmentStyle(lineHeight: lineHeight),
            ], range: paragraph)
        // The first character keeps its glyph, clear, which makes the line a fragment of its own (null glyphs have none).
        storage.addAttribute(
            .foregroundColor, value: NSColor.clear, range: NSRange(location: paragraph.location, length: 1))
        storage.addAttributes(
            appearance.markerAttributes(.attachment),
            range: NSRange(location: paragraph.location + 1, length: AttachmentToken.lineLength - 1))
        if !hasAttachmentLines { hasAttachmentLines = true }
        if mark.kind == .image, let url = mark.fileURL {
            previews.request(for: url, id: id, maxPixelSize: mark.previewPixelSize)
        }
        return true
    }

    /// Gives every attachment line that starts before `limit`, which is where the paragraphs styled at load begin, its look
    /// at once, with the one read of the catalog that they need. A line's height depends on it (a preview is up to 252 pt
    /// high, a line of text 17), and where a note is scrolled to is worked out from the layout of what is above it: a token
    /// line that a chunk styled after the scroll was set, and the chunks style the text above the window last, moved the
    /// note under the reader, and nothing applied the anchor again. The same remedy as for the blocks (`styleBlocks`), and
    /// the same cheapness: a note with no token is one search of its text, and what this did is not done again by the
    /// chunks (`styleAttachmentLine` writes nothing for a line that looks as it should). Call it inside `beginEditing()` and
    /// `endEditing()`. Returns what it changed.
    private func styleAttachmentLines(startingBefore limit: Int, text: NSString, storage: NSTextStorage) -> NSRange? {
        guard limit > 0 else { return nil }
        var lines: [(paragraph: NSRange, id: AttachmentID)] = []
        var searchStart = 0
        while searchStart < limit {
            let found = text.range(
                of: Self.attachmentOpening, options: [],
                range: NSRange(location: searchStart, length: limit - searchStart))
            guard found.location != NSNotFound else { break }
            searchStart = NSMaxRange(found)
            // A token is a whole line: it starts its paragraph, nothing follows it but the line break, and it is not in a
            // block (the same tests as `styleBatch` makes).
            var paragraphStart = 0
            var paragraphEnd = 0
            var contentsEnd = 0
            text.getParagraphStart(
                &paragraphStart, end: &paragraphEnd, contentsEnd: &contentsEnd,
                for: NSRange(location: found.location, length: 0))
            guard paragraphStart == found.location, contentsEnd - paragraphStart == AttachmentToken.lineLength,
                block(coveringParagraphStart: paragraphStart) == nil,
                let id = AttachmentToken.id(
                    inLine: text.substring(with: NSRange(location: paragraphStart, length: AttachmentToken.lineLength)))
            else { continue }
            lines.append((NSRange(location: paragraphStart, length: paragraphEnd - paragraphStart), id))
        }
        guard !lines.isEmpty else { return nil }
        catalog?.preload(lines.map { $0.id })
        var changed: NSRange?
        for line in lines {
            if styleAttachmentLine(of: line.paragraph, id: line.id, in: storage) {
                changed = Self.union(changed, line.paragraph)
            }
        }
        return changed
    }

    /// Styles the attachment lines again (those of `id`, or all of them), for a change of what they show or of the text
    /// width. Only a line that would look different is written, and that is a change of its paragraph style, which the text
    /// storage lays out again by itself.
    private func restyleAttachmentLines(matching id: AttachmentID?) {
        guard hasAttachmentLines, !isLoading, !isApplying, let storage, storage.length > 0 else { return }
        let text = storage.string as NSString
        var lines: [(paragraph: NSRange, id: AttachmentID)] = []
        storage.enumerateAttribute(
            .scratchAttachment, in: NSRange(location: 0, length: storage.length), options: []
        ) { value, run, _ in
            guard let mark = value as? AttachmentMark, id == nil || mark.id == id else { return }
            lines.append((text.paragraphRange(for: NSRange(location: run.location, length: 0)), mark.id))
        }
        guard !lines.isEmpty else { return }
        isApplying = true
        storage.beginEditing()
        for line in lines { styleAttachmentLine(of: line.paragraph, id: line.id, in: storage) }
        storage.endEditing()
        isApplying = false
    }

    /// The catalog says that `id` changed (its copy started or ended, or its image cannot be decoded): its lines are styled
    /// again, and what was decoded for it before is forgotten, unless it is the decoding that failed.
    private func attachmentDidChange(_ id: AttachmentID) {
        if catalog?.isUndecodable(id) != true { previews.discard(id) }
        restyleAttachmentLines(matching: id)
    }

    /// A request to `previews` is done. A preview that arrived invalidates the display of the lines of its image, which
    /// lays nothing out again. One that could not be decoded makes the image a missing attachment (`AttachmentCatalog`),
    /// which styles its lines again at the height of a chip.
    private func previewDidFinish(_ id: AttachmentID, decoded: Bool) {
        guard decoded else {
            catalog?.markUndecodable(id)
            return
        }
        guard hasAttachmentLines, let storage, storage.length > 0, let layoutManager = textView?.layoutManager else {
            return
        }
        storage.enumerateAttribute(
            .scratchAttachment, in: NSRange(location: 0, length: storage.length), options: []
        ) { value, run, _ in
            if let mark = value as? AttachmentMark, mark.id == id {
                layoutManager.invalidateDisplay(forCharacterRange: run)
            }
        }
    }

    /// The text view has a width that it did not have when the attachment lines were last sized: they are styled again,
    /// because the height of a preview depends on it. `EditorViewController` calls it from `viewDidLayout`, before it
    /// applies the scroll anchor, which depends on the height of everything above it. Does nothing when the width is the
    /// one the lines were sized for, and for a note without attachment lines.
    func refreshAttachmentLayout() {
        guard hasAttachmentLines, !isLoading, !isApplying else { return }
        let width = currentAttachmentWidth()
        guard abs(width - attachmentLayoutWidth) > 0.5 else { return }
        attachmentLayoutWidth = width
        restyleAttachmentLines(matching: nil)
    }

    /// `refreshAttachmentLayout()` once the call stack, which is AppKit resizing the text view, has unwound. A width that
    /// changes without a layout of the editor's view (a scroller that appears) is found this way.
    func scheduleAttachmentLayoutRefresh() {
        guard hasAttachmentLines, !isAttachmentRefreshScheduled else { return }
        isAttachmentRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAttachmentRefreshScheduled = false
                self.refreshAttachmentLayout()
            }
        }
    }

    /// The selection moved: the outline of the attachments that it touched or touches is drawn or taken away. The layout
    /// manager is told the selection (it is not on the main actor and cannot ask the text view), and the display of the
    /// attachment lines in the paragraphs of the old and the new selection is invalidated, which lays nothing out.
    private func attachmentSelectionDidChange(from old: NSRange, to new: NSRange, in storage: NSTextStorage) {
        guard let layoutManager = textView?.layoutManager as? MarkupLayoutManager else { return }
        layoutManager.attachmentSelection = new
        guard hasAttachmentLines else { return }
        let text = storage.string as NSString
        for range in [old, new] where range.length > 0 {
            let paragraphs = text.paragraphRange(for: Self.clamp(range, toLength: text.length))
            storage.enumerateAttribute(.scratchAttachment, in: paragraphs, options: []) { value, run, _ in
                if value is AttachmentMark { layoutManager.invalidateDisplay(forCharacterRange: run) }
            }
        }
    }

    // MARK: The job

    private func cancelJob() {
        pending = []
        blockProbes = []
        jobGeneration += 1
        isChunkScheduled = false
        codeBlockStyler.reset()
    }

    /// Asks for the next chunk when the main run loop is next about to wait, after the observers that end a signpost
    /// interval (`RunLoopIdle.afterMeasurementsOrder`). The loop is woken, because a chunk scheduled from the idle
    /// callback of the one before would otherwise wait for the next event.
    private func scheduleChunk() {
        guard !isChunkScheduled, !pending.isEmpty else { return }
        isChunkScheduled = true
        let generation = jobGeneration
        RunLoopIdle.onNext(order: RunLoopIdle.afterMeasurementsOrder) { [weak self] in
            guard let self, generation == self.jobGeneration else { return }
            self.isChunkScheduled = false
            self.runChunk()
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    /// Styles the next `chunkParagraphs` paragraphs of what is pending, or fewer when `chunkTimeBudget` runs out.
    private func runChunk() {
        guard let storage else {
            pending = []
            isFullyStyled = true
            return
        }
        let deadline = ContinuousClock.now + Self.chunkTimeBudget
        var text = storage.string as NSString
        var changed: NSRange?
        var moved: [NSRange] = []

        if needsFenceRescan {
            // After a big paste: which paragraphs moved into or out of a block is known only now.
            moved = rescanCodeBlocks(in: storage)
            isApplying = true
            storage.beginEditing()
            changed = restyle(moved, text: text, storage: storage)
            storage.endEditing()
            isApplying = false
            text = storage.string as NSString
        }

        var budget = Self.chunkParagraphs
        var styled: [NSRange] = []
        isApplying = true
        storage.beginEditing()
        while budget > 0, ContinuousClock.now < deadline, let work = pending.first {
            let end = min(NSMaxRange(work), text.length)
            guard work.location < end else {
                pending.removeFirst()
                continue
            }
            let result = styleParagraphs(
                from: work.location, upTo: end, maxParagraphs: budget, deadline: deadline, text: text, storage: storage)
            changed = Self.union(changed, result.changed)
            if result.end > work.location {
                styled.append(NSRange(location: work.location, length: result.end - work.location))
            }
            budget -= max(result.count, 1)
            if result.end >= end || result.end <= work.location {
                pending.removeFirst()
            } else {
                pending[0] = NSRange(location: result.end, length: NSMaxRange(work) - result.end)
            }
        }
        storage.endEditing()
        isApplying = false

        if let changed { invalidate(changed) }
        codeBlockStyler.clearColours(in: moved)
        // The blocks that this chunk styled are coloured, and so are those that a big paste changed.
        requestBlocks(startingIn: styled, in: storage)
        if !blockProbes.isEmpty || !moved.isEmpty {
            requestBlocks(intersecting: blockProbes + moved, in: storage)
            blockProbes = []
        }
        isFullyStyled = pending.isEmpty
        scheduleChunk()
        // Whoever waits for the colours of a big paste waits for the last chunk too.
        if isFullyStyled { codeBlockStyler.runHighlightedHandlersIfQuiet() }
    }

    // MARK: Font size

    /// The text takes the new font size, with its bold runs and indents. What is visible is styled first.
    private func restyleAfterFontChange() {
        guard let storage, storage.length > 0 else { return }
        let visible = visibleCharacterRange()
        isApplying = true
        storage.setAttributes(appearance.base, range: NSRange(location: 0, length: storage.length))
        isApplying = false
        noteDidLoad(visibleRange: visible)
    }

    /// The characters on screen, or an empty range at the start when nothing is laid out yet.
    private func visibleCharacterRange() -> NSRange {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            return NSRange(location: 0, length: 0)
        }
        var rect = textView.visibleRect
        guard rect.width > 0, rect.height > 0 else { return NSRange(location: 0, length: 0) }
        rect.origin.x -= textView.textContainerOrigin.x
        rect.origin.y -= textView.textContainerOrigin.y
        let glyphs = layoutManager.glyphRange(forBoundingRect: rect, in: container)
        return layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
    }

    // MARK: Layout

    /// Makes the layout manager generate the glyphs of `range` again and lay it out and draw it again, because what
    /// the delegate makes of its characters (null glyphs, `MarkupLayoutManager`) changed with their roles. Not for use
    /// inside `didProcessEditing`, where the layout manager may not know the edit yet.
    private func invalidate(_ range: NSRange) {
        guard let layoutManager = textView?.layoutManager, let length = textView?.textStorage?.length else { return }
        let clamped = Self.clamp(range, toLength: length)
        guard clamped.length > 0 else { return }
        layoutManager.invalidateGlyphs(forCharacterRange: clamped, changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: clamped, actualCharacterRange: nil)
        layoutManager.invalidateDisplay(forCharacterRange: clamped)
    }

    // MARK: Ranges

    private static func clamp(_ range: NSRange, toLength length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), length - location))
    }

    private static func union(_ first: NSRange?, _ second: NSRange?) -> NSRange? {
        guard let first else { return second }
        guard let second else { return first }
        return NSUnionRange(first, second)
    }

    /// True when `outer` holds all of `inner`.
    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    /// The start of the paragraph `count` paragraphs before the one that starts at `location`.
    private static func paragraphStart(stepping count: Int, backFrom location: Int, in text: NSString) -> Int {
        var start = location
        var remaining = count
        while remaining > 0, start > 0 {
            start = text.paragraphRange(for: NSRange(location: start - 1, length: 0)).location
            remaining -= 1
        }
        return start
    }

    /// The end of the paragraph `count` paragraphs after the one that ends at `location`.
    private static func paragraphEnd(stepping count: Int, forwardFrom location: Int, in text: NSString) -> Int {
        var end = location
        var remaining = count
        while remaining > 0, end < text.length {
            end = NSMaxRange(text.paragraphRange(for: NSRange(location: end, length: 0)))
            remaining -= 1
        }
        return end
    }
}
