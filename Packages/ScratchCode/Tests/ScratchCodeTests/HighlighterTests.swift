import Foundation
import Testing

@testable import ScratchCode

// Plan 4, "Code highlighting" (spec §6.4, §7): tokens and the error rate, on all seventeen grammars. The first tests
// use Swift and Python, the grammars the package started with. docs/features/code.md.

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

/// The sample of a language: `Tests/ScratchCodeTests/Samples/<fence name>.txt`, 15 to 40 lines of ordinary code.
private func sample(_ language: CodeLanguage) -> String {
    guard
        let url = Bundle.module.url(forResource: language.fenceName, withExtension: "txt", subdirectory: "Samples"),
        let text = try? String(contentsOf: url, encoding: .utf8)
    else {
        Issue.record("no sample for \(language.fenceName)")
        return ""
    }
    return text
}

private func kinds(of text: String, _ language: CodeLanguage) -> Set<HighlightKind> {
    Set((Highlighter.shared.tokens(in: text, language: language) ?? []).map(\.kind))
}

/// Whether some token of `kind` covers exactly `covered`.
private func has(_ tokens: [HighlightToken], _ text: String, _ covered: String, _ kind: HighlightKind) -> Bool {
    tokens.contains { slice(text, $0) == covered && $0.kind == kind }
}

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
        // The others: one that inherits a query (TypeScript, C++), and one of each of the rest of the grammars.
        ("interface A { b: string }\nconst s = \"x\" // y\n", .typescript), ("#include <x>\nclass A {};\n", .cpp),
        ("SELECT a, 1 FROM t WHERE b = 'c';", .sql), ("a { color: #fff }\n@media x { }\n", .css),
        ("a: [1, true]\nb: \"c\"\n", .yaml), ("<p class=\"a\">x</p>\n", .html), ("{\"a\": [1, null]}", .json),
        ("if true; then echo \"$((1 + 2))\"; fi\n", .bash), ("fn main() { let a = 1; }\n", .rust),
        ("public class A { int f() { return 1; } }\n", .csharp), ("func main() { x := 1 }\n", .go),
        ("public class A { }\n", .java), ("function F { return 1 }\n", .powershell),
        ("const a = <b c=\"d\"/>;\n", .javascript),
        ("int main(void) { return 0; }\n", .c),
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

// MARK: All seventeen languages (Plan 4, task 3)

@Test(arguments: CodeLanguage.allCases)
func everyLanguageHighlightsItsSample(language: CodeLanguage) {
    let text = sample(language)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count - 1
    #expect((15...40).contains(lines), "the sample has \(lines) lines")
    let found = kinds(of: text, language)
    switch language {
    case .json:
        #expect(found.contains(.string))
    case .yaml:
        #expect(found.contains(.string) || found.contains(.keyword))
    default:
        #expect(found.contains(.keyword), "no keyword in the \(language.fenceName) sample")
        #expect(found.contains(.string) || found.contains(.comment), "no string or comment")
    }
}

@Test(arguments: CodeLanguage.allCases)
func everySampleParsesWithoutErrors(language: CodeLanguage) {
    // A grammar wired to the wrong language, or a sample that is not valid code, shows here.
    #expect(Highlighter.shared.errorRate(of: sample(language), language: language) < 0.05)
}

/// What a reader expects to see coloured in each sample: the kinds that the sample has and the grammar's query gives.
private let expectedKinds: [CodeLanguage: Set<HighlightKind>] = [
    .swift: [.keyword, .string, .comment, .number, .type, .function, .attribute],
    .python: [.keyword, .string, .comment, .number, .type, .function, .attribute],
    .javascript: [.keyword, .string, .comment, .number, .type, .function],
    .typescript: [.keyword, .string, .comment, .number, .type, .function],
    .json: [.string, .number, .keyword],
    .bash: [.keyword, .string, .comment, .function],
    .sql: [.keyword, .string, .comment, .number, .type],
    .yaml: [.string, .comment, .number, .keyword, .type],
    .html: [.keyword, .string, .comment, .attribute],
    .css: [.keyword, .string, .comment, .number, .attribute, .function],
    .csharp: [.keyword, .string, .comment, .number, .type, .function],
    .go: [.keyword, .string, .comment, .number, .type, .function],
    .rust: [.keyword, .string, .comment, .number, .type, .function, .attribute],
    .c: [.keyword, .string, .comment, .number, .type, .function, .preprocessor],
    .cpp: [.keyword, .string, .comment, .number, .type, .function, .preprocessor],
    .java: [.keyword, .string, .comment, .number, .type, .function, .attribute],
    .powershell: [.keyword, .string, .comment, .number, .type, .function],
]

@Test(arguments: CodeLanguage.allCases)
func eachSampleShowsTheKindsAReaderExpects(language: CodeLanguage) {
    let found = kinds(of: sample(language), language)
    let expected = expectedKinds[language] ?? []
    #expect(!expected.isEmpty)
    let missing = expected.subtracting(found).map(\.rawValue).sorted()
    #expect(missing.isEmpty, "the \(language.fenceName) sample has no \(missing)")
}

@Test func cppInheritsC() {
    // `#include` and `const` come from C's query, `namespace`, `class` and `public` from C++'s own.
    let text = "#include <x>\nnamespace a { class B { public: int f() const; }; }\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .cpp) ?? []
    #expect(has(tokens, text, "#include", .preprocessor))
    #expect(has(tokens, text, "const", .keyword))
    #expect(has(tokens, text, "namespace", .keyword))
    #expect(has(tokens, text, "class", .keyword))
    #expect(has(tokens, text, "public", .keyword))
    #expect(has(tokens, text, "int", .type))
    // And C itself.
    let c = "#include <stdio.h>\n#define N 3\nint main(void) { return N; }\n"
    let cTokens = Highlighter.shared.tokens(in: c, language: .c) ?? []
    #expect(has(cTokens, c, "#include", .preprocessor))
    #expect(has(cTokens, c, "#define", .preprocessor))
    #expect(has(cTokens, c, "return", .keyword))
}

@Test func typescriptInheritsJavaScript() {
    // Strings, comments, `const` and calls are JavaScript's query, the annotation and `interface` TypeScript's.
    let text = "interface A { n: string }\nconst s: string = \"hi\" // note\nconsole.log(s.length)\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .typescript) ?? []
    #expect(has(tokens, text, "interface", .keyword))
    #expect(has(tokens, text, "const", .keyword))
    #expect(has(tokens, text, "string", .type))
    #expect(has(tokens, text, "\"hi\"", .string))
    #expect(has(tokens, text, "// note", .comment))
    #expect(has(tokens, text, "log", .function))
    // JavaScript alone knows nothing of annotations, and TypeScript's `interface` is not one of its keywords.
    let javascript = "const s = \"hi\" // note\n"
    let javascriptTokens = Highlighter.shared.tokens(in: javascript, language: .javascript) ?? []
    #expect(has(javascriptTokens, javascript, "const", .keyword))
    #expect(has(javascriptTokens, javascript, "\"hi\"", .string))
}

@Test func htmlTagsAreKeywords() {
    let text = "<div class=\"a\" id=b>hi</div>\n<!-- note -->\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .html) ?? []
    #expect(tokens.filter { slice(text, $0) == "div" && $0.kind == .keyword }.count == 2)
    #expect(has(tokens, text, "class", .attribute))
    #expect(has(tokens, text, "<!-- note -->", .comment))
    // The quotes belong to the value.
    #expect(has(tokens, text, "\"a\"", .string))
}

@Test func bashVariableExpansionIsNotAnError() {
    let text = """
        name="world"
        echo "hello ${name}, today is $(date +%F)"
        count=$((1 + 2))
        files=("a" "b" "c")
        echo "${files[@]} ${#files[@]} ${name:-nobody} ${name%.txt} $1 $@ $?"
        for f in "${files[@]}"; do
          echo "$f"
        done
        """
    #expect(Highlighter.shared.errorRate(of: text, language: .bash) < 0.05)
    let tokens = Highlighter.shared.tokens(in: text, language: .bash) ?? []
    #expect(has(tokens, text, "for", .keyword))
    #expect(tokens.contains { $0.kind == .string })
}

@Test func jsxIsPartOfJavaScript() {
    let text = "const a = <div className=\"x\">{y}</div>;\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .javascript) ?? []
    #expect(tokens.filter { slice(text, $0) == "div" && $0.kind == .keyword }.count == 2)
    #expect(has(tokens, text, "className", .attribute))
    #expect(has(tokens, text, "\"x\"", .string))
}

@Test func jsonKeysAndValues() {
    let text = "{\"a\": [1, -2.5e3, true, null, \"x\\ny\"]}\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .json) ?? []
    #expect(has(tokens, text, "\"a\"", .string))
    #expect(has(tokens, text, "1", .number))
    #expect(has(tokens, text, "-2.5e3", .number))
    #expect(has(tokens, text, "true", .keyword))
    #expect(has(tokens, text, "null", .keyword))
    #expect(has(tokens, text, "\"x\\ny\"", .string))
}

@Test func yamlKeysAreNotValues() {
    let text = "name: ci # the workflow\nretries: 3\ndebug: false\nitems:\n  - \"a\"\n  - plain text\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .yaml) ?? []
    #expect(has(tokens, text, "name", .type))
    #expect(has(tokens, text, "ci", .string))
    #expect(has(tokens, text, "# the workflow", .comment))
    #expect(has(tokens, text, "3", .number))
    #expect(has(tokens, text, "false", .keyword))
    #expect(has(tokens, text, "\"a\"", .string))
    #expect(has(tokens, text, "plain text", .string))
}

@Test func sqlKeywordsInAnyCaseAndNumbers() {
    let text = "select name from users where id = 42 and ratio > 0.5 and note = 'x';\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .sql) ?? []
    for word in ["select", "from", "where", "and"] {
        #expect(has(tokens, text, word, .keyword), "\(word)")
    }
    #expect(has(tokens, text, "42", .number))
    #expect(has(tokens, text, "0.5", .number))
    #expect(has(tokens, text, "'x'", .string))
    let upper = "SELECT name FROM users;\n"
    #expect(has(Highlighter.shared.tokens(in: upper, language: .sql) ?? [], upper, "SELECT", .keyword))
}

@Test func rustNumbersAreNumbersAndLiteralsAreKeywords() {
    let text = "fn main() { let n = 42; let f = 2.5; let b = true; }\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .rust) ?? []
    #expect(has(tokens, text, "42", .number))
    #expect(has(tokens, text, "2.5", .number))
    #expect(has(tokens, text, "true", .keyword))
    #expect(has(tokens, text, "fn", .keyword))
}

@Test func cCharacterLiteralsAreStrings() {
    let text = "char c = 'x';\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .c) ?? []
    #expect(has(tokens, text, "'x'", .string))
    #expect(has(tokens, text, "char", .type))
}

@Test func goLiteralsAndBuiltins() {
    let text = "func f() { x := make([]int, 3); s := \"a\"; ok := true; _ = nil }\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .go) ?? []
    #expect(has(tokens, text, "func", .keyword))
    #expect(has(tokens, text, "make", .function))
    #expect(has(tokens, text, "3", .number))
    #expect(has(tokens, text, "\"a\"", .string))
    #expect(has(tokens, text, "true", .keyword))
    #expect(has(tokens, text, "nil", .keyword))
}

@Test func powershellKeywordsInAnyCase() {
    let text = "Function Get-Thing {\n  param($a)\n  If ($a -eq 1) { Write-Host \"hi\" }\n}\n"
    let tokens = Highlighter.shared.tokens(in: text, language: .powershell) ?? []
    #expect(has(tokens, text, "Function", .keyword))
    #expect(has(tokens, text, "param", .keyword))
    #expect(has(tokens, text, "If", .keyword))
    #expect(has(tokens, text, "\"hi\"", .string))
    #expect(has(tokens, text, "Write-Host", .function))
    #expect(has(tokens, text, "Get-Thing", .function))
}

@Test func rangesAreUTF16InEveryGrammar() {
    // A comment with two emoji (each is two UTF-16 units and one Character), then one line of code.
    let cases: [(CodeLanguage, comment: String, code: String)] = [
        (.javascript, "// 😀😀", "const a = 1"), (.typescript, "// 😀😀", "const a = 1"),
        (.go, "// 😀😀", "var a = 1"), (.rust, "// 😀😀", "let a = 1;"), (.c, "// 😀😀", "int a = 1;"),
        (.cpp, "// 😀😀", "int a = 1;"), (.java, "// 😀😀", "int a = 1;"), (.csharp, "// 😀😀", "var a = 1;"),
        (.bash, "# 😀😀", "export A=1"), (.sql, "-- 😀😀", "select 1;"), (.yaml, "# 😀😀", "a: true"),
        (.powershell, "# 😀😀", "if ($a) { }"), (.css, "/* 😀😀 */", "a { color: red }"),
        (.html, "<!-- 😀😀 -->", "<p>x</p>"), (.json, "// 😀😀", "{\"a\": 1}"),
    ]
    for (language, comment, code) in cases {
        let text = comment + "\n" + code + "\n"
        let tokens = Highlighter.shared.tokens(in: text, language: language) ?? []
        // JSON has no comments in its grammar's standard, but tree-sitter-json accepts them.
        #expect(tokens.first == token(0, comment.utf16.count, .comment), "\(language.fenceName): \(tokens)")
        let rest = tokens.dropFirst()
        #expect(!rest.isEmpty, "\(language.fenceName) has nothing after the comment")
        #expect(
            rest.allSatisfy { $0.range.location > comment.utf16.count && NSMaxRange($0.range) <= text.utf16.count },
            "\(language.fenceName): \(tokens)")
    }
}

// MARK: Warm-up

// Plan 5, task 7 (the "late first colours" follow-up of 0.4.0): the app compiles the queries of the languages it expects on
// its highlight queue, before a text needs them. docs/features/code.md, "Late first colours".

@Test func aQueryIsCompiledOnlyWhenAskedFor() {
    let highlighter = Highlighter()
    for language in CodeLanguage.allCases { #expect(!highlighter.isPrepared(language), "\(language.fenceName)") }

    #expect(highlighter.prepare(.go))
    #expect(highlighter.isPrepared(.go))
    #expect(!highlighter.isPrepared(.rust), "preparing one language leaves the others alone")
    #expect(!highlighter.isPrepared(.swift))
}

@Test func preparingTwiceIsHarmless() {
    let highlighter = Highlighter()
    #expect(highlighter.prepare(.python))
    #expect(highlighter.prepare(.python))
    #expect(highlighter.isPrepared(.python))
}

@Test func aLanguageThatInheritsAQueryIsPrepared() {
    // TypeScript's query is JavaScript's and its own (`QueryInheritance`): one compile.
    let highlighter = Highlighter()
    #expect(highlighter.prepare(.typescript))
    #expect(highlighter.isPrepared(.typescript))
}

@Test func tokensAreTheSameWhetherOrNotTheQueryWasPrepared() {
    let prepared = Highlighter()
    let cold = Highlighter()
    #expect(prepared.prepare(.swift))
    #expect(prepared.tokens(in: swiftSample, language: .swift) == cold.tokens(in: swiftSample, language: .swift))
    #expect(cold.isPrepared(.swift), "a text in a language compiles its query, as before")
}

@Test func theSharedHighlighterIsTheOneThatIsPrepared() {
    // `CodeBlockStyler`'s warm-up prepares `Highlighter.shared`, and its requests use it: "the same cache".
    #expect(Highlighter.shared.prepare(.json))
    #expect(Highlighter.shared.isPrepared(.json))
}

@Test func preparingEveryLanguageSucceeds() {
    let highlighter = Highlighter()
    for language in CodeLanguage.allCases {
        #expect(highlighter.prepare(language), "\(language.fenceName)")
        #expect(highlighter.isPrepared(language), "\(language.fenceName)")
    }
}
