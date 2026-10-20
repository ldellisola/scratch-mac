import AppKit
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

    /// True when every paragraph of the text has been styled. False while a note is still being styled in chunks.
    private(set) var isFullyStyled = true

    init(textView: NoteTextView) {
        self.textView = textView
        appearance = MarkupAppearance(fontSize: FontSize.standard)
        super.init()
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
        needsFenceRescan = false
        guard let storage else { return }
        let length = storage.length
        codeBlocks = length > 0 ? scanCodeBlocks(in: storage) : CodeBlockIndex()
        isFullyStyled = length == 0
        if length > 0 {
            isApplying = true
            storage.setAttributes(appearance.base, range: NSRange(location: 0, length: length))
            isApplying = false
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
        storage.endEditing()
        isApplying = false
        if let changed = result.changed { invalidate(changed) }

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
        let text = storage.string as NSString
        var changed: NSRange?
        var looked: [NSRange] = []
        for candidate in [old, newSelection] where candidate.length <= Self.selectionRevealLimit {
            let paragraphs = text.paragraphRange(for: Self.clamp(candidate, toLength: text.length))
            guard !looked.contains(paragraphs) else { continue }
            looked.append(paragraphs)
            changed = Self.union(changed, refreshMarkers(in: paragraphs, text: text, storage: storage))
        }
        if let changed { invalidate(changed) }
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
        // Carry what was known of the old text over the edit.
        let touchesFence = codeBlocks.touchesFenceLine(edit.replaced)
        codeBlocks.apply(edit)
        pending = pending.map { edit.mapped($0) }.filter { $0.length > 0 }

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
            isFullyStyled = false
            scheduleChunk()
            return
        }

        let batch = ParagraphBatch(
            in: text, from: paragraphs.location, upTo: NSMaxRange(paragraphs), maxParagraphs: .max)
        let moved = touchesFence || batch.containsFenceLine() ? rescanCodeBlocks(in: storage) : []

        isApplying = true
        storage.beginEditing()
        if paragraphs.length > 0 { storage.setAttributes(appearance.base, range: paragraphs) }
        _ = styleBatch(batch, in: storage)
        // The paragraphs that moved into or out of a block, other than the ones just styled.
        _ = restyle(moved.filter { !Self.contains(paragraphs, $0) }, text: text, storage: storage)
        storage.endEditing()
        isApplying = false
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
        return codeBlocks.changedRanges(comparedTo: old)
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
        for index in batch.paragraphs.indices {
            let paragraph = batch.paragraphs[index]
            let line = batch.line(at: index)
            guard !codeBlocks.covers(paragraphStart: paragraph.location), MarkupParser.mayHaveSpans(in: line) else {
                continue
            }
            let spans = MarkupParser.parseLine(String(decoding: line, as: UTF16.self), at: paragraph.location)
            guard !spans.isEmpty else { continue }
            apply(spans, toParagraph: paragraph, in: storage)
            result.changed = Self.union(result.changed, paragraph)
        }
        return result
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

    // MARK: The job

    private func cancelJob() {
        pending = []
        jobGeneration += 1
        isChunkScheduled = false
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

        if needsFenceRescan {
            // After a big paste: which paragraphs moved into or out of a block is known only now.
            let moved = rescanCodeBlocks(in: storage)
            isApplying = true
            storage.beginEditing()
            changed = restyle(moved, text: text, storage: storage)
            storage.endEditing()
            isApplying = false
            text = storage.string as NSString
        }

        var budget = Self.chunkParagraphs
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
        isFullyStyled = pending.isEmpty
        scheduleChunk()
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
