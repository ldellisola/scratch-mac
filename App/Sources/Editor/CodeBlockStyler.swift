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
/// - **A block is coloured from scratch:** the code gets the text colour, then each token its colour. A block with no
///   language (a fence name that is not one of the 17, a fence with no name whose code is not code, an empty block) is
///   left with the text colour only, and so is a block that is too long to colour (`Highlighter.maximumLines` and
///   `maximumLength`), which stays a tinted block.
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

    /// How many results were dropped because no block held their text any more. The tests read it.
    private(set) var droppedResults = 0

    init(textView: NoteTextView, queue: DispatchQueue) {
        self.textView = textView
        self.queue = queue
        var table: [HighlightKind: NSColor] = [:]
        for kind in HighlightKind.allCases {
            table[kind] = NSColor(named: NSColor.Name(Self.assetName(of: kind))) ?? NSColor.textColor
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
            signature: signature, info: parts.info, text: code, length: parts.content.length, declared: declared)
        if running == nil, todo.isEmpty {
            // Nothing is ahead of it, and the block was just looked at: no need to find it again.
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
            guard !matchingBlocks(info: next.info, length: next.length, code: next.text).isEmpty else { continue }
            submit(next)
            return
        }
    }

    private func submit(_ request: HighlightRequest) {
        running = request
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
        enqueue(highlight)
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

    /// Writes the next tokens of `work` into its block, until `deadline`: the first time also the text colour of the code
    /// and the label. Returns true when the block is done, or is not the block that the result was made for any more.
    private func advance(_ work: inout Work, until deadline: ContinuousClock.Instant, in storage: NSTextStorage) -> Bool
    {
        let text = storage.string as NSString
        let highlight = work.highlight
        guard let parts = CodeBlockParts(block: work.block, in: text), parts.info == highlight.info,
            highlight.text == nil
                ? parts.content.length > Highlighter.maximumLength : parts.content.length == highlight.contentLength
        else { return true }

        storage.beginEditing()
        if !work.didStart {
            work.didStart = true
            if parts.content.length > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: parts.content)
            }
            let mark = CodeBlockMark(
                part: .opening, language: highlight.language, isDetected: highlight.isDetected, name: highlight.label)
            storage.addAttribute(.scratchCodeBlock, value: mark, range: parts.openingParagraph)
        }
        var written = 0
        while work.next < highlight.tokens.count {
            let token = highlight.tokens[work.next]
            work.next += 1
            let range = NSRange(location: parts.content.location + token.range.location, length: token.range.length)
            guard let color = colors[token.kind], token.range.location >= 0,
                NSMaxRange(range) <= NSMaxRange(parts.content)
            else { continue }
            storage.addAttribute(.foregroundColor, value: color, range: range)
            written += 1
            if written % 64 == 0, ContinuousClock.now >= deadline { break }
        }
        storage.endEditing()
        // The label reaches into the first line of code, so the whole block is drawn again.
        textView?.layoutManager?.invalidateDisplay(forCharacterRange: work.block)
        return work.next >= highlight.tokens.count
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
