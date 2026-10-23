import AppKit
import ScratchCode
import ScratchCore

/// Colours the code of the fenced blocks of the editor, and keeps the language that the label of each block says (spec
/// §6.4 "Code highlighting", §7; plan 4, task 5).
///
/// `MarkupStyler` styles what a block looks like (the hidden fence lines, the indent, the tint and the label are drawn
/// from attributes it sets), and asks this class to colour the code of the blocks it styled or that an edit changed
/// (`blocksDidChange`). The colours come from `ScratchCode`'s tree-sitter highlighter:
///
/// - **Highlighting never runs on the main thread.** A block's code goes to a private serial queue, one request at a
///   time, in the order it was asked for (so the blocks on screen come first). The queue finds the language of a fence
///   with no name (`CodeDetector`) and the tokens (`Highlighter`), and sends the outcome back.
/// - **A result is for a text, not for a place.** It is applied to every block that holds exactly the text it was made
///   from (the same fence name and the same code, compared as a hash first and then as text), wherever the block is by
///   then. A block that was edited since no longer matches, so a result for older text is dropped and never lands on
///   newer text (`droppedResults`): the edit asked for the block again, and its own result is the one that is applied.
///   Because of this a block that only moved, or a note that is shown again, is coloured from a cache of results.
/// - **The main thread only writes colours,** at the moment the run loop is next about to wait, after the observers that
///   end a signpost interval (`RunLoopIdle.afterMeasurementsOrder`), and for at most `applyBudget` at a time: a block with
///   thousands of tokens is written in slices over several turns. A block that is edited while it is being written is
///   dropped from the work, and is asked for again.
/// - **The colours are temporary attributes of the layout manager, not attributes of the text.** They are for display
///   only, so writing them lays nothing out again and adds no attribute run to the text storage. As attributes of the
///   text they made a note of 10,000 lines with 100 blocks several times slower to scroll and to type in: every colour
///   was an edit that invalidated the layout of its block, and the layout manager laid the whole note out again in the
///   background, a slice of tens of milliseconds at a time on the main thread (the macOS CI, Plan 4 task 5).
/// - **A block is coloured from scratch:** the colours of its code are cleared, then each token gets its colour. A block
///   with no language (a fence name that is not one of the 17, a fence with no name whose code is not code, an empty
///   block) is left with the text colour only, and so is a block that is too long to colour (`Highlighter.maximumLines`
///   and `maximumLength`), which stays a tinted block.
///
/// The label of a block is the mark on its opening fence line (`CodeBlockMark`): a result sets it (it names the detected
/// language of a fence with no name), and `MarkupStyler` sets it for a fence that names its language.
@MainActor
final class CodeBlockStyler {
    // MARK: Tuning

    /// How long one run of the application of results may take, so that it does not hold up a key or a frame.
    static let applyBudget: Duration = .milliseconds(8)
    /// How many results are kept, and how many UTF-16 units of code they stand for at most.
    static let cacheEntries = 256
    static let cacheUnits = 1_000_000

    // MARK: State

    private weak var textView: NoteTextView?
    private let queue: DispatchQueue
    private let colors: [HighlightKind: NSColor]
    /// The requests that wait for the queue, first in first out. A text that is in the list is not asked for twice.
    private var todo: [HighlightRequest] = []
    /// The request the queue is working on. There is one at a time, so a request that an edit made out of date can be
    /// dropped (`pump` looks for its block first) before it costs anything.
    private var running: HighlightRequest?
    /// The results that wait to be written, first in first out.
    private var ready: [Highlight] = []
    /// The blocks that a result is being written into, a few tokens at a time.
    private var works: [Work] = []
    private var cache = HighlightCache()
    private var isApplyScheduled = false
    /// What waits for the colours (`whenHighlighted`).
    private var highlightedHandlers: [@MainActor () -> Void] = []

    /// How many results were dropped because no block held their text any more. The tests read it.
    private(set) var droppedResults = 0

    /// How many requests were sent to the highlight queue, those made for a block that is not there yet (`prefetch`)
    /// included. The tests read it.
    private(set) var submittedRequests = 0

    /// How many requests to look for the languages of some texts are on the queue (`warmUp`).
    private var warmUpScans = 0
    /// The languages whose queries are to be compiled, first in first out.
    private var warmUpTodo: [CodeLanguage] = []
    /// True while the queue is compiling the query of one language.
    private var isWarmingUp = false
    /// The languages whose queries the warm-up has compiled, or tried to. The tests read it.
    private(set) var warmedLanguages: Set<CodeLanguage> = []

    init(textView: NoteTextView, queue: DispatchQueue) {
        self.textView = textView
        self.queue = queue
        var table: [HighlightKind: NSColor] = [:]
        for kind in HighlightKind.allCases {
            table[kind] = CatalogColour.named(Self.assetName(of: kind), fallback: NSColor.textColor)
        }
        colors = table
    }

    /// The name of the colour asset of a kind: `CodeKeyword`, `CodeString`, `CodeComment` and so on.
    static func assetName(of kind: HighlightKind) -> String {
        "Code" + kind.rawValue.prefix(1).uppercased() + String(kind.rawValue.dropFirst())
    }

    /// The highlights that are still on their way: asked for and not written yet (or dropped). A test waits for zero.
    var pendingHighlights: Int {
        todo.count + (running == nil ? 0 : 1) + ready.count + works.count
    }

    /// Calls `handler` when every highlight that was asked for has been written (or dropped) and the note is styled all the
    /// way (a big paste is styled in chunks), at the next moment the main run loop is about to wait after that: the colours
    /// have been drawn by then, as the display of the run loop turn comes before it (`RunLoopIdle`). When nothing is
    /// pending it is the next such moment. The `paste-code` signpost interval ends there (`NoteTextView`).
    func whenHighlighted(_ handler: @escaping @MainActor () -> Void) {
        highlightedHandlers.append(handler)
        runHighlightedHandlersIfQuiet()
    }

    /// Hands the handlers that wait for the colours on to the next idle moment when nothing is pending any more. Called
    /// when colours have been written, and by `MarkupStyler` when it has styled the last chunk.
    func runHighlightedHandlersIfQuiet() {
        guard !highlightedHandlers.isEmpty, pendingHighlights == 0, textView?.styler.isFullyStyled ?? true else {
            return
        }
        let handlers = highlightedHandlers
        highlightedHandlers = []
        for handler in handlers { RunLoopIdle.onNext(handler) }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    // MARK: Warming up (plan 5 task 7)

    /// The warm-up that is still to be done: texts that wait to be read for the names on their fences, and languages whose
    /// queries wait to be compiled, or are being. A test waits for zero.
    var pendingWarmUps: Int {
        warmUpScans + warmUpTodo.count + (isWarmingUp ? 1 : 0)
    }

    /// The languages that the fences of the blocks of `text` name, each once, in the order they are first named. A name that
    /// is not one of the languages (`ruby`), a fence with no name and a fence with no partner give nothing.
    nonisolated static func languages(namedIn text: String) -> [CodeLanguage] {
        guard text.contains("```") else { return [] }
        let nsText = text as NSString
        var found: [CodeLanguage] = []
        for block in FenceScanner.codeBlocks(in: text) {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            nsText.getParagraphStart(
                &lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                for: NSRange(location: block.location, length: 0))
            let line = nsText.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
            if let language = CodeLanguage.fromFence(CodeBlockParts.info(ofFenceLine: line)), !found.contains(language)
            {
                found.append(language)
            }
        }
        return found
    }

    /// The languages that the fences of any of `texts` name, each once, in order.
    nonisolated static func languages(namedInAny texts: [String]) -> [CodeLanguage] {
        var found: [CodeLanguage] = []
        for text in texts {
            for language in languages(namedIn: text) where !found.contains(language) { found.append(language) }
        }
        return found
    }

    /// Compiles, on the highlight queue, the queries of the languages that the fences in `texts` (the notes that are open in
    /// tabs) name, so that the first block in one of them is coloured at once and not after its query is compiled (240 to
    /// 270 ms for Swift, docs/decisions/0007-tree-sitter.md). `highlighter` is `Highlighter.shared` in the app, the cache that
    /// every request reads, so a later request finds the queries compiled. The texts are read on the queue, and the queries
    /// are compiled one language at a time, each as a block of its own on the queue, so that a block that is shown while
    /// this runs waits for one compile at most.
    func warmUp(languagesNamedIn texts: [String], using highlighter: Highlighter = .shared) {
        guard !texts.isEmpty else { return }
        warmUpScans += 1
        queue.async { [weak self] in
            let languages = Self.languages(namedInAny: texts)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.warmUpScanDidFinish(languages, using: highlighter) }
            }
        }
    }

    /// The same, for texts that are not at hand: `readTexts` reads them on `readQueue` (the storage queue: the launch reads the
    /// body of the active note only, and the other tabs' bodies are read here, after the first frame, plan 6 task 3), and the
    /// fences are looked for on the highlight queue. `pendingWarmUps` is above zero from this call until the scan is done.
    func warmUp(
        languagesInTextsFrom readTexts: @escaping @Sendable () -> [String], on readQueue: DispatchQueue,
        using highlighter: Highlighter = .shared
    ) {
        warmUpScans += 1
        let highlightQueue = queue
        readQueue.async { [weak self] in
            let texts = readTexts()
            highlightQueue.async {
                let languages = Self.languages(namedInAny: texts)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.warmUpScanDidFinish(languages, using: highlighter) }
                }
            }
        }
    }

    private func warmUpScanDidFinish(_ languages: [CodeLanguage], using highlighter: Highlighter) {
        warmUpScans -= 1
        for language in languages where !warmedLanguages.contains(language) && !warmUpTodo.contains(language) {
            warmUpTodo.append(language)
        }
        pumpWarmUp(using: highlighter)
    }

    /// Sends the next language to the queue, when it is not compiling one.
    private func pumpWarmUp(using highlighter: Highlighter) {
        guard !isWarmingUp, !warmUpTodo.isEmpty else { return }
        let language = warmUpTodo.removeFirst()
        isWarmingUp = true
        queue.async { [weak self] in
            highlighter.prepare(language)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.warmUpDidFinish(language, using: highlighter) }
            }
        }
    }

    private func warmUpDidFinish(_ language: CodeLanguage, using highlighter: Highlighter) {
        isWarmingUp = false
        warmedLanguages.insert(language)
        pumpWarmUp(using: highlighter)
    }

    // MARK: What MarkupStyler tells it

    /// The blocks at `blocks` (each from the start of its opening fence line to the end of its closing one) are new, were
    /// edited or were styled again: their code is coloured again for the text it is now. `storage` is the editor's text.
    /// Nothing is changed here but what is asked for: the highlighting is on the queue and its result is written later.
    func blocksDidChange(_ blocks: [NSRange], in storage: NSTextStorage) {
        let text = storage.string as NSString
        for range in blocks { request(range, in: text) }
    }

    /// A note is being loaded or styled again: what was waiting for the old text is dropped. The request that is on the
    /// queue is not, and its result is written if a block of the new text holds the same code.
    func reset() {
        todo = []
        ready = []
        works = []
    }

    /// The text was edited. A block that is being written into and that the edit lies in is left as it is (it is asked for
    /// again), and the others are followed to where they are now.
    func textDidEdit(_ edit: EditMapping) {
        guard !works.isEmpty else { return }
        let replaced = edit.replaced
        works = works.compactMap { work in
            let isEdited =
                replaced.location < NSMaxRange(work.block)
                && max(NSMaxRange(replaced), replaced.location + 1) > work.block.location
            guard !isEdited else { return nil }
            var moved = work
            moved.block = edit.mapped(work.block)
            return moved
        }
    }

    // MARK: What tests and commands ask

    /// The language of the block that holds `location`, whether it was detected (the label is in italics) and what its
    /// label says ("" when it has none), or nil when `location` is in no block. A block that has not been styled yet (a
    /// long note is styled in chunks) has no language yet either.
    func language(ofBlockAt location: Int) -> (CodeLanguage?, isDetected: Bool, name: String)? {
        guard let textView, let storage = textView.textStorage,
            let block = textView.styler.codeBlock(containing: location),
            block.range.location < storage.length,
            let mark = storage.attribute(.scratchCodeBlock, at: block.range.location, effectiveRange: nil)
                as? CodeBlockMark,
            mark.part == .opening
        else { return nil }
        return (mark.language, mark.isDetected, mark.name)
    }

    // MARK: Asking for a block

    private func request(_ range: NSRange, in text: NSString) {
        guard let parts = CodeBlockParts(block: range, in: text) else { return }
        let isUnnamed = parts.info.isEmpty
        let declared = CodeLanguage.fromFence(parts.info)

        // Too long to read, let alone to colour: it is uncoloured and keeps its name, and nothing is copied out of the
        // text for it.
        if parts.content.length > Highlighter.maximumLength {
            enqueue(
                Highlight(
                    info: parts.info, text: nil, contentLength: parts.content.length, language: declared,
                    isDetected: isUnnamed, tokens: []))
            return
        }
        let code = parts.content.length == 0 ? "" : text.substring(with: parts.content)

        // Nothing to colour: an empty block, or a fence name that is not one of the languages.
        if parts.content.length == 0 || (!isUnnamed && declared == nil) {
            enqueue(
                Highlight(
                    info: parts.info, text: code, contentLength: parts.content.length, language: nil,
                    isDetected: isUnnamed, tokens: []))
            return
        }

        let signature = Self.signature(info: parts.info, text: code)
        if let cached = cache.highlight(signature: signature, info: parts.info, text: code) {
            enqueue(cached)
            return
        }
        if running?.signature == signature || todo.contains(where: { $0.signature == signature }) { return }
        let request = HighlightRequest(
            signature: signature, info: parts.info, text: code, length: parts.content.length, declared: declared,
            isPrefetch: false)
        if running == nil, todo.isEmpty {
            // Nothing is ahead of it, and the block was just looked at: no need to find it again.
            submit(request)
        } else {
            todo.append(request)
        }
    }

    /// Asks for the colours that a block holding `block` would ask for, before the block exists, so that they are in the cache
    /// by their hash when it appears (a paste that is going to be wrapped in a fence: `NoteTextView.endPaste` calls it with the
    /// edit's replacement, whole fenced block as `PasteClassifier.wrap` writes it, with the line breaks that it may have in
    /// front and behind). The block that the wrap makes is then coloured from the cache, or from the request that is on the
    /// queue (`request` finds it there), and the paste's colours do not wait for the wrap's turn of the run loop.
    ///
    /// A block with no language is not queued: a fence with no name (code of a language that Scratch lacks), a name that is not
    /// one of the languages, an empty block and a block over the highlighter's cap have no colours to get ahead with. The
    /// request carries the mark `isPrefetch`: its result is stored in the cache and written only when a block holds its code
    /// (no block yet is not a dropped result), and `pump` does not drop it for want of a block.
    func prefetch(block: String) {
        let text = block as NSString
        guard let range = FenceScanner.codeBlocks(in: block).first, let parts = CodeBlockParts(block: range, in: text),
            let declared = CodeLanguage.fromFence(parts.info), parts.content.length > 0,
            parts.content.length <= Highlighter.maximumLength
        else { return }
        let code = text.substring(with: parts.content)
        let signature = Self.signature(info: parts.info, text: code)
        if cache.highlight(signature: signature, info: parts.info, text: code) != nil { return }
        if running?.signature == signature || todo.contains(where: { $0.signature == signature }) { return }
        let request = HighlightRequest(
            signature: signature, info: parts.info, text: code, length: parts.content.length, declared: declared,
            isPrefetch: true)
        if running == nil, todo.isEmpty {
            submit(request)
        } else {
            todo.append(request)
        }
    }

    private static func signature(info: String, text: String) -> Int {
        var hasher = Hasher()
        hasher.combine(info)
        hasher.combine(text)
        return hasher.finalize()
    }

    /// Puts a result in the line to be written, unless the same one is in it already.
    private func enqueue(_ highlight: Highlight) {
        if ready.contains(where: { $0.hasSameCode(as: highlight) }) { return }
        ready.append(highlight)
        scheduleApply()
    }

    // MARK: The queue

    /// Sends the next request that is still wanted to the queue, when it has none to work on. A request that waited
    /// is looked at first: the text may have been edited since, and then nothing is spent on it.
    private func pump() {
        guard running == nil else { return }
        while !todo.isEmpty {
            let next = todo.removeFirst()
            // A prefetched request is for a block that is still to come: it is kept (its result is cached).
            guard next.isPrefetch || !matchingBlocks(info: next.info, length: next.length, code: next.text).isEmpty
            else { continue }
            submit(next)
            return
        }
    }

    private func submit(_ request: HighlightRequest) {
        running = request
        submittedRequests += 1
        queue.async { [weak self] in
            let outcome = CodeBlockStyler.highlight(request)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let self { self.receive(request, outcome) }
                }
            }
        }
    }

    /// What the queue does: finds the language of a fence with no name, then the tokens. Called on the queue. A text over
    /// the cap has no tokens and, when its fence names no language, no language either.
    nonisolated private static func highlight(_ request: HighlightRequest) -> HighlightOutcome {
        var language = request.declared
        var isDetected = false
        if request.info.isEmpty {
            language = CodeDetector.detect(request.text)?.language
            isDetected = true
        }
        guard let language else { return HighlightOutcome(language: nil, isDetected: isDetected, tokens: []) }
        guard let tokens = Highlighter.shared.tokens(in: request.text, language: language) else {
            return HighlightOutcome(
                language: request.info.isEmpty ? nil : language, isDetected: isDetected, tokens: [])
        }
        return HighlightOutcome(language: language, isDetected: isDetected, tokens: tokens)
    }

    /// The queue is done with `request`.
    private func receive(_ request: HighlightRequest, _ outcome: HighlightOutcome) {
        running = nil
        let highlight = Highlight(
            info: request.info, text: request.text, contentLength: request.length, language: outcome.language,
            isDetected: outcome.isDetected, tokens: outcome.tokens)
        cache.store(signature: request.signature, highlight)
        // A prefetched result that comes before its block waits in the cache: the block finds it when it appears, and the
        // result is not one that was dropped. When the block is there already (the wrap came first) it is written now.
        let isWaitingForItsBlock =
            request.isPrefetch
            && matchingBlocks(info: request.info, length: request.length, code: request.text).isEmpty
        if !isWaitingForItsBlock { enqueue(highlight) }
        pump()
    }

    // MARK: Writing the colours

    /// Asks for the results to be written when the main run loop is next about to wait, after the observers that end a
    /// signpost interval: what a key press or a switch of notes measures does not include the colours that follow it.
    private func scheduleApply() {
        guard !isApplyScheduled, !(ready.isEmpty && works.isEmpty) else { return }
        isApplyScheduled = true
        RunLoopIdle.onNext(order: RunLoopIdle.afterMeasurementsOrder) { [weak self] in
            self?.applyReady()
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    /// Writes results into the blocks that hold their code, for at most `applyBudget`, then asks for the next turn.
    private func applyReady() {
        isApplyScheduled = false
        defer { runHighlightedHandlersIfQuiet() }
        guard let storage = textView?.textStorage else {
            ready = []
            works = []
            return
        }
        let deadline = ContinuousClock.now + Self.applyBudget
        var isFirst = true
        while isFirst || ContinuousClock.now < deadline {
            isFirst = false
            guard !works.isEmpty else {
                guard !ready.isEmpty else { break }
                let highlight = ready.removeFirst()
                let targets = matchingBlocks(
                    info: highlight.info, length: highlight.contentLength, code: highlight.text)
                if targets.isEmpty { droppedResults += 1 }
                works = targets.map { Work(highlight: highlight, block: $0.range) }
                continue
            }
            var work = works[0]
            if advance(&work, until: deadline, in: storage) {
                works.removeFirst()
            } else {
                works[0] = work
            }
        }
        scheduleApply()
    }

    /// Writes the next tokens of `work` into its block, until `deadline`: the first time also the end of the old colours of
    /// the code and the label. Returns true when the block is done, or is not the block that the result was made for any
    /// more.
    private func advance(_ work: inout Work, until deadline: ContinuousClock.Instant, in storage: NSTextStorage) -> Bool
    {
        guard let layoutManager = textView?.layoutManager else { return true }
        let text = storage.string as NSString
        let highlight = work.highlight
        guard let parts = CodeBlockParts(block: work.block, in: text), parts.info == highlight.info,
            highlight.text == nil
                ? parts.content.length > Highlighter.maximumLength : parts.content.length == highlight.contentLength
        else { return true }

        if !work.didStart {
            work.didStart = true
            if parts.content.length > 0 {
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: parts.content)
            }
            // The label is the one attribute of the text that is written, and only when it is not the one there is.
            let mark = CodeBlockMark(
                part: .opening, language: highlight.language, isDetected: highlight.isDetected, name: highlight.label)
            let current = storage.attribute(.scratchCodeBlock, at: parts.openingParagraph.location, effectiveRange: nil)
            if (current as? CodeBlockMark) != mark {
                storage.beginEditing()
                storage.addAttribute(.scratchCodeBlock, value: mark, range: parts.openingParagraph)
                // The label reaches into the first line of code, which keeps clear of it (or no longer has to).
                textView?.styler.labelDidChange(inBlockAt: work.block.location, in: storage)
                storage.endEditing()
                // The label reaches into the first line of code, so the whole block is drawn again.
                layoutManager.invalidateDisplay(forCharacterRange: work.block)
            }
        }
        var written = 0
        while work.next < highlight.tokens.count {
            let token = highlight.tokens[work.next]
            work.next += 1
            let range = NSRange(location: parts.content.location + token.range.location, length: token.range.length)
            guard let color = colors[token.kind], token.range.location >= 0,
                NSMaxRange(range) <= NSMaxRange(parts.content)
            else { continue }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range)
            written += 1
            if written % 64 == 0, ContinuousClock.now >= deadline { break }
        }
        return work.next >= highlight.tokens.count
    }

    /// The colours of the code of the blocks in `ranges` are cleared: the paragraphs were styled again, or left their
    /// block. (`MarkupStyler` calls it for what an edit moved, once the layout manager knows the edit.)
    func clearColours(in ranges: [NSRange]) {
        guard let layoutManager = textView?.layoutManager, let length = textView?.textStorage?.length else { return }
        for range in ranges {
            let location = min(max(range.location, 0), length)
            let clamped = NSRange(location: location, length: min(max(range.length, 0), length - location))
            if clamped.length > 0 {
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: clamped)
            }
        }
    }

    // MARK: Finding blocks

    /// The blocks of the note whose fence name is `info` and whose code is `code` (nil: any code over the cap, which is
    /// what a result for a block that is too long stands for). `length` is the length of the code in UTF-16 units.
    private func matchingBlocks(info: String, length: Int, code: String?) -> [CodeBlockParts] {
        guard let textView, let storage = textView.textStorage else { return [] }
        let text = storage.string as NSString
        var found: [CodeBlockParts] = []
        for block in textView.styler.codeBlockList {
            guard block.range.length >= (code == nil ? Highlighter.maximumLength : length),
                let parts = CodeBlockParts(block: block.range, in: text), parts.info == info
            else { continue }
            if let code {
                guard parts.content.length == length else { continue }
                guard length == 0 || text.substring(with: parts.content) == code else { continue }
            } else {
                guard parts.content.length > Highlighter.maximumLength else { continue }
            }
            found.append(parts)
        }
        return found
    }
}

// MARK: - Values

/// What the queue is asked to do: highlight `text`, the code of a block, whose fence has the name `info`. It can be sent
/// to the queue and back.
nonisolated private struct HighlightRequest: Sendable {
    let signature: Int
    let info: String
    let text: String
    /// The length of `text` in UTF-16 units.
    let length: Int
    /// The language the fence names, nil when it names none (or one that is not known): it is detected then.
    let declared: CodeLanguage?
    /// True for a request made before its block exists (`CodeBlockStyler.prefetch`).
    let isPrefetch: Bool
}

/// What the queue found: the language that was used (nil for none), whether it was detected, and the tokens (none for a
/// text over the cap).
nonisolated private struct HighlightOutcome: Sendable {
    let language: CodeLanguage?
    let isDetected: Bool
    let tokens: [HighlightToken]
}

/// What highlighting the code of a block came to, for every block that holds that code with that fence name.
private struct Highlight {
    let info: String
    /// The code, or nil for a block too long to read (matched by its length, and uncoloured).
    let text: String?
    /// The length of the code in UTF-16 units.
    let contentLength: Int
    let language: CodeLanguage?
    let isDetected: Bool
    /// The ranges to colour, relative to the start of the code. Empty for no colours.
    let tokens: [HighlightToken]

    /// What the label of the block says: the language's label, or the fence name as written when it is not a language.
    /// Nothing for a fence with no name and no detected language.
    var label: String { language?.label ?? info }

    func hasSameCode(as other: Highlight) -> Bool {
        info == other.info && text == other.text && (text != nil || contentLength == other.contentLength)
    }
}

/// A block of the note that a result is being written into.
private struct Work {
    let highlight: Highlight
    /// The range of the block now (it follows the edits that are not in it).
    var block: NSRange
    /// The index of the next token to write.
    var next = 0
    /// True once the text colour of the code and the label are written.
    var didStart = false
}

/// The results that were made, by the hash of the fence name and the code: the oldest are dropped when there are too many
/// or too much code in them. A block that moved, a note that is shown again and an edit that is undone are coloured from
/// here, without asking the queue.
private struct HighlightCache {
    private var entries: [Int: Highlight] = [:]
    private var order: [Int] = []
    private var units = 0

    mutating func store(signature: Int, _ highlight: Highlight) {
        remove(signature)
        entries[signature] = highlight
        order.append(signature)
        units += highlight.contentLength
        while let oldest = order.first,
            order.count > CodeBlockStyler.cacheEntries || units > CodeBlockStyler.cacheUnits,
            order.count > 1
        {
            remove(oldest)
        }
    }

    /// The result for this code, if there is one (the hash is checked against the text), and now the newest.
    mutating func highlight(signature: Int, info: String, text: String) -> Highlight? {
        guard let entry = entries[signature], entry.info == info, entry.text == text else { return nil }
        order.removeAll { $0 == signature }
        order.append(signature)
        return entry
    }

    private mutating func remove(_ signature: Int) {
        guard let old = entries.removeValue(forKey: signature) else { return }
        units -= old.contentLength
        order.removeAll { $0 == signature }
    }
}
