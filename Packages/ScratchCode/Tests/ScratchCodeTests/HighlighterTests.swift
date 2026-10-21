import Foundation
import Testing

@testable import ScratchCode

// Plan 4, "Code highlighting" (spec §6.4, §7): tokens and the error rate, on both grammars of the first release of the
// package (Swift and Python). docs/features/code.md.

private func r(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

/// The text a token covers.
private func slice(_ text: String, _ token: HighlightToken) -> String {
    (text as NSString).substring(with: token.range)
}

private func token(_ location: Int, _ length: Int, _ kind: HighlightKind) -> HighlightToken {
    HighlightToken(range: r(location, length), kind: kind)
}

private let swiftSample = """
    import Foundation

    /// A note.
    struct Note: Identifiable {
        let id: Int
        var title: String = "Untitled"

        @MainActor
        func shout(times: Int = 3) -> String {
            // repeat the title
            var result = ""
            for _ in 0..<times {
                result += title.uppercased() + "!"
            }
            return result
        }
    }
    """

private let pythonSample = """
    import os
    from dataclasses import dataclass

    @dataclass
    class Point:
        x: int = 0
        y: int = 0

        def length(self) -> float:
            # the distance to the origin
            return (self.x ** 2 + self.y ** 2) ** 0.5

    def main():
        p = Point(3, 4)
        print(f"length is {p.length()}")
        if p.x > 2 and p.y > 3:
            return None
    """

private let prose = """
    Thanks for getting back to me so quickly. I have looked at the numbers again and I think we should move the
    meeting to Thursday, because the team will be travelling on Wednesday. Could you let me know if that works for you?
    """

// MARK: Tokens

@Test func swiftKeywordsStringsComments() {
    let text = #"let s = "hi" // note"#
    let tokens = Highlighter.shared.tokens(in: text, language: .swift)
    #expect(tokens == [token(0, 3, .keyword), token(8, 4, .string), token(13, 7, .comment)])
}

@Test func pythonDecoratorIsAttribute() {
    let text = "@app.route(\"/\")\ndef index():\n    return 1\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .python) ?? []
    // `@app.route` reads as one attribute, the argument stays a string, and `def` and `return` are keywords.
    #expect(tokens.contains(token(0, 10, .attribute)))
    #expect(tokens.contains(token(11, 3, .string)))
    #expect(tokens.contains(token(16, 3, .keyword)))
    #expect(tokens.contains { slice(text, $0) == "return" && $0.kind == .keyword })
    // A plain name as a decorator.
    let plain = "@staticmethod\ndef f():\n    pass\n"
    let plainTokens = Highlighter.shared.tokens(in: plain, language: .python) ?? []
    #expect(plainTokens.first == token(0, 13, .attribute))
}

@Test func swiftAttributeTypeAndNumber() {
    let text = "@MainActor final class Box { var count: Int = 42 }"
    let tokens = Highlighter.shared.tokens(in: text, language: .swift) ?? []
    #expect(tokens.contains { slice(text, $0) == "@MainActor" && $0.kind == .attribute })
    #expect(tokens.contains { slice(text, $0) == "Int" && $0.kind == .type })
    #expect(tokens.contains { slice(text, $0) == "42" && $0.kind == .number })
    #expect(tokens.contains { slice(text, $0) == "class" && $0.kind == .keyword })
}

@Test func pythonFunctionsTypesAndNumbers() {
    let text = "class Point:\n    def length(self):\n        return len([1, 2.5])\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .python) ?? []
    #expect(tokens.contains { slice(text, $0) == "Point" && $0.kind == .type })
    #expect(tokens.contains { slice(text, $0) == "length" && $0.kind == .function })
    #expect(tokens.contains { slice(text, $0) == "len" && $0.kind == .function })
    #expect(tokens.contains { slice(text, $0) == "1" && $0.kind == .number })
    #expect(tokens.contains { slice(text, $0) == "2.5" && $0.kind == .number })
}

@Test func anEscapeStaysPartOfItsString() {
    // `\n` has its own capture in Python's query but no colour of its own, so the string is one token.
    let text = #"x = "a\nb""#
    #expect(Highlighter.shared.tokens(in: text, language: .python) == [token(4, 6, .string)])
}

@Test func utf16RangesAfterEmoji() {
    // Each emoji is two UTF-16 units and one Character.
    let text = "// 😀😀 hi\nlet x = \"é😀\"\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .swift) ?? []
    let ns = text as NSString
    #expect(tokens.count == 3)
    #expect(tokens.contains { ns.substring(with: $0.range) == "// 😀😀 hi" && $0.kind == .comment })
    #expect(tokens.contains { ns.substring(with: $0.range) == "let" && $0.kind == .keyword })
    #expect(tokens.contains { ns.substring(with: $0.range) == "\"é😀\"" && $0.kind == .string })
    #expect(tokens.first == token(0, 10, .comment))
    #expect(tokens.last == token(19, 5, .string))
}

@Test func tokensAreSortedAndDoNotOverlap() {
    for (text, language) in [(swiftSample, CodeLanguage.swift), (pythonSample, .python)] {
        let tokens = Highlighter.shared.tokens(in: text, language: language) ?? []
        #expect(tokens.count > 10)
        var end = 0
        for token in tokens {
            #expect(token.range.location >= end, "\(token) starts before \(end)")
            #expect(token.range.length > 0)
            end = NSMaxRange(token.range)
        }
        #expect(end <= (text as NSString).length)
    }
}

@Test func theSamplesAreColouredTheWayAReaderExpects() {
    let swiftTokens = Highlighter.shared.tokens(in: swiftSample, language: .swift) ?? []
    let kinds = Set(swiftTokens.map(\.kind))
    for kind in [HighlightKind.keyword, .string, .comment, .type, .function, .attribute] {
        #expect(kinds.contains(kind), "swift sample has no \(kind)")
    }
    let pythonTokens = Highlighter.shared.tokens(in: pythonSample, language: .python) ?? []
    let pythonKinds = Set(pythonTokens.map(\.kind))
    for kind in [HighlightKind.keyword, .string, .comment, .type, .function, .attribute, .number] {
        #expect(pythonKinds.contains(kind), "python sample has no \(kind)")
    }
}

@Test func emptyTextHasNoTokens() {
    #expect(Highlighter.shared.tokens(in: "", language: .swift) == [])
    #expect(Highlighter.shared.tokens(in: "", language: .python) == [])
}

@Test func textWithNoCodeHasFewTokens() {
    // Nothing here is a keyword, a string, a number or a comment, whatever the grammar makes of it.
    let tokens = Highlighter.shared.tokens(in: "hello world", language: .swift) ?? []
    #expect(tokens.allSatisfy { $0.kind != .string && $0.kind != .comment && $0.kind != .number })
}

// MARK: The cap

@Test func overCapReturnsNil() {
    let lines = (0..<5_001).map { "let x\($0) = \($0)" }.joined(separator: "\n")
    #expect(Highlighter.shared.tokens(in: lines, language: .swift) == nil)
    let long = String(repeating: "a", count: Highlighter.maximumLength + 1)
    #expect(Highlighter.shared.tokens(in: long, language: .python) == nil)
}

@Test func theCapItselfIsStillColoured() {
    let lines = (0..<5_000).map { "let x\($0) = \($0)" }.joined(separator: "\n")
    #expect(Highlighter.shared.tokens(in: lines, language: .swift) != nil)
    // A last line break does not start a line.
    let withBreak = (0..<5_000).map { "x = \($0)" }.joined(separator: "\n") + "\n"
    #expect(Highlighter.shared.tokens(in: withBreak, language: .python) != nil)
    let exactLength = String(repeating: "a", count: Highlighter.maximumLength)
    #expect(Highlighter.shared.tokens(in: exactLength, language: .python) != nil)
}

@Test func linesAreCountedLikeAnEditorDoes() {
    func lines(_ text: String) -> Int { Highlighter.lineCount(of: Array(text.utf16)) }
    #expect(lines("") == 0)
    #expect(lines("a") == 1)
    #expect(lines("a\n") == 1)
    #expect(lines("a\nb") == 2)
    #expect(lines("a\r\nb\r\n") == 2)
    #expect(lines("a\rb") == 2)
    #expect(lines("\n\n") == 2)
}

@Test func aTextOverTheCapIsCutAtALineForTheErrorRate() {
    let lines = (0..<6_000).map { "let x\($0) = \($0)" }.joined(separator: "\n")
    let cut = Highlighter.withinCap(lines)
    #expect(Highlighter.lineCount(of: Array(cut.utf16)) == Highlighter.maximumLines)
    #expect(lines.hasPrefix(cut))
    let long = String(repeating: "é", count: Highlighter.maximumLength + 10)
    #expect(Highlighter.withinCap(long).utf16.count == Highlighter.maximumLength)
    #expect(Highlighter.withinCap("let a = 1\n") == "let a = 1\n")
}

// MARK: Overlaps

private func capture(_ start: Int, _ end: Int, _ kind: HighlightKind, pattern: Int = 0, sequence: Int = 0)
    -> Highlighter.Capture
{
    Highlighter.Capture(
        start: start, end: end, kind: kind, priority: Highlighter.Priority(pattern: pattern, sequence: sequence))
}

@Test func theInnermostCaptureWins() {
    let tokens = Highlighter.resolve([capture(0, 20, .string), capture(5, 8, .keyword)])
    #expect(tokens == [token(0, 5, .string), token(5, 3, .keyword), token(8, 12, .string)])
}

@Test func ofTheSameWidthTheLaterCaptureWins() {
    let later = Highlighter.resolve([capture(0, 5, .function, pattern: 7), capture(0, 5, .type, pattern: 2)])
    #expect(later == [token(0, 5, .function)])
    let sameWidthSamePattern = Highlighter.resolve([
        capture(0, 5, .function, pattern: 3, sequence: 1), capture(0, 5, .type, pattern: 3, sequence: 4),
    ])
    #expect(sameWidthSamePattern == [token(0, 5, .type)])
}

@Test func touchingTokensOfOneKindAreOne() {
    let tokens = Highlighter.resolve([
        capture(0, 1, .string), capture(1, 3, .string), capture(3, 4, .string), capture(4, 6, .keyword),
        capture(6, 8, .keyword),
    ])
    #expect(tokens == [token(0, 4, .string), token(4, 4, .keyword)])
}

@Test func tokensWithAGapBetweenThemStayTwo() {
    #expect(
        Highlighter.resolve([capture(0, 2, .keyword), capture(3, 5, .keyword)])
            == [token(0, 2, .keyword), token(3, 2, .keyword)])
}

@Test func nestedCapturesOfSeveralLevels() {
    let tokens = Highlighter.resolve([
        capture(0, 30, .comment), capture(2, 20, .string), capture(5, 10, .number), capture(12, 14, .keyword),
    ])
    #expect(
        tokens == [
            token(0, 2, .comment), token(2, 3, .string), token(5, 5, .number), token(10, 2, .string),
            token(12, 2, .keyword), token(14, 6, .string), token(20, 10, .comment),
        ])
}

// MARK: Error rate

@Test func errorRateOfProseIsHigh() {
    #expect(Highlighter.shared.errorRate(of: prose, language: .python) > 0.3)
    #expect(Highlighter.shared.errorRate(of: prose, language: .swift) > 0.3)
}

@Test func errorRateOfValidCodeIsLow() {
    #expect(Highlighter.shared.errorRate(of: swiftSample, language: .swift) < 0.05)
    #expect(Highlighter.shared.errorRate(of: pythonSample, language: .python) < 0.05)
}

@Test func errorRateSeparatesTheLanguages() {
    let swiftAsPython = Highlighter.shared.errorRate(of: swiftSample, language: .python)
    let pythonAsSwift = Highlighter.shared.errorRate(of: pythonSample, language: .swift)
    #expect(swiftAsPython > Highlighter.shared.errorRate(of: swiftSample, language: .swift))
    #expect(pythonAsSwift > Highlighter.shared.errorRate(of: pythonSample, language: .python))
}

@Test func errorRateIsBetweenZeroAndOne() {
    for text in ["", "(", "))))", "let", "def", prose, swiftSample, "💥💥💥", String(repeating: "{", count: 400)] {
        for language in [CodeLanguage.swift, .python] {
            let rate = Highlighter.shared.errorRate(of: text, language: language)
            #expect((0...1).contains(rate), "\(rate) for \(text.prefix(20))")
        }
    }
    #expect(Highlighter.shared.errorRate(of: "", language: .swift) == 0)
}

@Test func errorRateOfAHugeTextIsJudgedOnItsFirstLines() {
    let lines = (0..<20_000).map { "let x\($0) = \($0)" }.joined(separator: "\n")
    #expect(Highlighter.shared.errorRate(of: lines, language: .swift) < 0.05)
}

// MARK: Threads

@Test func concurrentCallsAreSafe() {
    let jobs: [(String, CodeLanguage)] = [
        (swiftSample, .swift), (pythonSample, .python), (#"let s = "hi" // note"#, .swift),
        ("@app.route(\"/\")\ndef index():\n    return 1\n", .python), (prose, .python), ("// 😀\nlet a = 1", .swift),
    ]
    // A highlighter of its own, so that the threads also race to compile the queries.
    let highlighter = Highlighter()
    let serial = Highlighter()
    let expected = jobs.map { serial.tokens(in: $0.0, language: $0.1) }
    let expectedRates = jobs.map { serial.errorRate(of: $0.0, language: $0.1) }

    let results = Results()
    let group = DispatchGroup()
    for thread in 0..<8 {
        group.enter()
        Thread.detachNewThread {
            defer { group.leave() }
            for call in 0..<50 {
                let index = (thread + call) % jobs.count
                let tokens = highlighter.tokens(in: jobs[index].0, language: jobs[index].1)
                let rate = highlighter.errorRate(of: jobs[index].0, language: jobs[index].1)
                if tokens != expected[index] || rate != expectedRates[index] {
                    results.addMismatch()
                }
            }
        }
    }
    group.wait()
    #expect(results.mismatches == 0)
}

private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func addMismatch() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var mismatches: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
