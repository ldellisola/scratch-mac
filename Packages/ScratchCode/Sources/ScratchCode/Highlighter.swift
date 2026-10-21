import Foundation
import SwiftTreeSitter

/// Colours code: a text and its language in, the ranges to colour out (Plan 4, spec §6.4 and §7).
///
/// It parses with tree-sitter and runs the language's highlight query over the tree. It is pure (no AppKit, no state
/// but the compiled queries) and thread-safe, so the app calls it from a background queue.
///
/// - Parsers are made for each call: a tree-sitter parser is not thread-safe, and making one is cheap.
/// - A language's query is compiled once, behind a lock, on first use.
/// - A parse that takes more than `parseTimeout` seconds is given up: the text stays uncoloured.
public final class Highlighter: Sendable {
    public static let shared = Highlighter()

    /// A text of more lines than this, or more UTF-16 units than `maximumLength`, is not coloured (spec §7).
    public static let maximumLines = 5_000
    public static let maximumLength = 300_000

    /// How long one parse may take, in seconds, before it is abandoned.
    static let parseTimeout: TimeInterval = 2

    private let queries = QueryCache()

    public init() {}

    /// The ranges of `text` to colour, or nil when the text is over the cap (`maximumLines`, `maximumLength`), which
    /// the caller shows tinted and uncoloured. Ranges are UTF-16, relative to `text`, sorted by position and never
    /// overlapping.
    ///
    /// Where captures overlap, the innermost (narrowest) one wins, and of two of the same width the later one in the
    /// query. Captures with no kind (`@variable`, `@punctuation`) never compete: the text under them keeps the colour
    /// of whatever wraps it. Tokens of one kind that touch are one token. A language with no grammar yet, a parse that
    /// timed out and an empty text give no tokens.
    public func tokens(in text: String, language: CodeLanguage) -> [HighlightToken]? {
        let units = Array(text.utf16)
        guard units.count <= Self.maximumLength, Self.lineCount(of: units) <= Self.maximumLines else { return nil }
        guard !units.isEmpty,
            let grammar = Grammar.grammar(for: language),
            let compiled = queries.compiledQuery(for: language, grammar: grammar),
            let tree = Self.parse(text, with: grammar)
        else { return [] }

        let context = Predicate.Context(textProvider: { range, _ in
            guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= units.count else { return nil }
            return String(decoding: units[range.location..<NSMaxRange(range)], as: UTF16.self)
        })

        var captures: [Capture] = []
        let cursor = compiled.query.execute(in: tree)
        while let match = cursor.next() {
            guard match.allowed(in: context) else { continue }
            for capture in match.captures {
                guard capture.index < compiled.kinds.count, let kind = compiled.kinds[capture.index] else { continue }
                let range = capture.range
                guard range.length > 0, NSMaxRange(range) <= units.count else { continue }
                captures.append(
                    Capture(
                        start: range.location, end: NSMaxRange(range), kind: kind,
                        priority: Priority(pattern: match.patternIndex, sequence: captures.count)))
            }
        }
        return Self.resolve(captures)
    }

    /// The share of the syntax tree that tree-sitter could not make sense of, 0 to 1: the UTF-16 units under ERROR
    /// nodes (the outermost of each), plus one for each MISSING node, over the length of the text. It is 0 for text
    /// that parses cleanly and near 1 for text that is not in the language at all, which is what `CodeDetector` uses
    /// it for. A text of more lines or units than the cap is judged by its first lines within the cap, so that the
    /// cost stays bounded. A language with no grammar yet, and a parse that timed out, give 1. An empty text gives 0.
    public func errorRate(of text: String, language: CodeLanguage) -> Double {
        guard let grammar = Grammar.grammar(for: language) else { return 1 }
        let text = Self.withinCap(text)
        let length = text.utf16.count
        guard length > 0 else { return 0 }
        guard let tree = Self.parse(text, with: grammar), let root = tree.rootNode else { return 1 }
        guard root.hasError else { return 0 }

        var errorUnits = 0
        var missing = 0
        var pending = [root]
        while let node = pending.popLast() {
            if node.nodeType == "ERROR" {
                errorUnits += node.range.length
            } else if node.isMissing {
                missing += 1
            } else {
                for index in 0..<node.childCount {
                    if let child = node.child(at: index), child.hasError {
                        pending.append(child)
                    }
                }
            }
        }
        return min(1, Double(errorUnits + missing) / Double(length))
    }

    // MARK: Parsing

    private static func parse(_ text: String, with grammar: Grammar) -> MutableTree? {
        let parser = Parser()
        parser.timeout = parseTimeout
        do {
            try parser.setLanguage(grammar.language)
        } catch {
            return nil
        }
        return parser.parse(text)
    }

    // MARK: The cap

    /// The number of lines of a text: one for each line break (CR LF is one), and one for a last line that has no
    /// break after it. A final line break does not start another line.
    static func lineCount(of units: [UInt16]) -> Int {
        let lineFeed: UInt16 = 0x0A
        let carriageReturn: UInt16 = 0x0D
        var lines = 0
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == lineFeed || unit == carriageReturn {
                if unit == carriageReturn, index + 1 < units.count, units[index + 1] == lineFeed {
                    index += 1
                }
                lines += 1
            }
            index += 1
        }
        if let last = units.last, last != lineFeed, last != carriageReturn {
            lines += 1
        }
        return lines
    }

    /// `text`, or when it is over the cap, its first whole lines within the cap.
    static func withinCap(_ text: String) -> String {
        let units = Array(text.utf16)
        guard units.count > maximumLength || lineCount(of: units) > maximumLines else { return text }
        var end = 0
        var lines = 0
        var index = 0
        let limit = min(units.count, maximumLength)
        while index < limit, lines < maximumLines {
            let unit = units[index]
            index += 1
            if unit == 0x0A || unit == 0x0D {
                if unit == 0x0D, index < limit, units[index] == 0x0A {
                    index += 1
                }
                lines += 1
                end = index
            }
        }
        // A first line that is longer than the cap alone: cut it there, but never between a surrogate pair.
        if end == 0 {
            end = limit
            if end > 0, UTF16.isLeadSurrogate(units[end - 1]) {
                end -= 1
            }
        }
        return String(decoding: units[..<end], as: UTF16.self)
    }

    // MARK: Overlaps

    /// Where a capture comes in the query: its pattern, then the order it was found in.
    struct Priority: Comparable {
        let pattern: Int
        let sequence: Int

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            (lhs.pattern, lhs.sequence) < (rhs.pattern, rhs.sequence)
        }
    }

    struct Capture {
        let start: Int
        let end: Int
        let kind: HighlightKind
        let priority: Priority
    }

    /// Cuts the captures into sorted, non-overlapping tokens. Sorting puts an outer capture before the ones inside
    /// it, and of equal ranges the winner (the later capture) last, so a stack of the captures that are open at a
    /// position has the winner on top.
    static func resolve(_ captures: [Capture]) -> [HighlightToken] {
        let sorted = captures.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end > rhs.end }
            return lhs.priority < rhs.priority
        }
        var tokens: [HighlightToken] = []
        var open: [Capture] = []
        var painted = 0

        // Colours [painted, position) with the capture on top of the stack.
        func paint(upTo position: Int) {
            if let top = open.last, position > painted {
                if let last = tokens.last, last.kind == top.kind, NSMaxRange(last.range) == painted {
                    tokens[tokens.count - 1] = HighlightToken(
                        range: NSRange(location: last.range.location, length: position - last.range.location),
                        kind: top.kind)
                } else {
                    tokens.append(
                        HighlightToken(range: NSRange(location: painted, length: position - painted), kind: top.kind))
                }
            }
            painted = max(painted, position)
        }

        for capture in sorted {
            while let top = open.last, top.end <= capture.start {
                paint(upTo: top.end)
                open.removeLast()
            }
            paint(upTo: capture.start)
            open.append(capture)
        }
        while let top = open.last {
            paint(upTo: top.end)
            open.removeLast()
        }
        return tokens
    }
}
