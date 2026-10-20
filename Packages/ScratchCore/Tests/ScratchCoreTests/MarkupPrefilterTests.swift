import Foundation
import Testing

@testable import ScratchCore

// Plan 3, task 3: the editor skips the parse of a line that `mayHaveSpans` rules out, so the prefilter must never say
// no to a line the parser finds a span in (spec §6.4).

private func mayHaveSpans(_ line: String) -> Bool {
    MarkupParser.mayHaveSpans(in: Array(line.utf16)[...])
}

@Test func plainProseHasNoSpans() {
    #expect(!mayHaveSpans(""))
    #expect(!mayHaveSpans("   "))
    #expect(!mayHaveSpans("Paragraph 1, line 1: The scratchpad keeps every line it is given."))
    #expect(!mayHaveSpans("a - b and a [b] and a : b"))
    #expect(!mayHaveSpans("http:/x and https:x"))
}

@Test func everyMarkerKindPassesThePrefilter() {
    #expect(mayHaveSpans("- bullet"))
    #expect(mayHaveSpans("    - nested bullet"))
    #expect(mayHaveSpans("[ ] task"))
    #expect(mayHaveSpans("  [x] done"))
    #expect(mayHaveSpans("some **bold** text"))
    #expect(mayHaveSpans("some `code` text"))
    #expect(mayHaveSpans("see https://example.com now"))
    #expect(mayHaveSpans("see HTTP://EXAMPLE.COM now"))
}

@Test func theSliceIsReadInItsOwnIndices() {
    let units = Array("plain text\n- bullet".utf16)
    #expect(!MarkupParser.mayHaveSpans(in: units[0..<10]))
    #expect(MarkupParser.mayHaveSpans(in: units[11..<units.count]))
    #expect(!MarkupParser.mayHaveSpans(in: units[5..<5]))
}

@Test func theParserNeverFindsASpanInALineThePrefilterRejects() {
    // A deterministic pseudo-random walk over the characters that matter to the parser.
    let alphabet = Array(" -[]x*`:/htps.a()_\u{A0}😀".unicodeScalars)
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    func next() -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int(state >> 33)
    }
    var rejectedWithSpans: [String] = []
    var lines = 0
    for _ in 0..<20_000 {
        var line = String.UnicodeScalarView()
        for _ in 0..<(next() % 16) { line.append(alphabet[next() % alphabet.count]) }
        let text = String(line)
        lines += 1
        if !MarkupParser.parseLine(text, at: 0).isEmpty, !mayHaveSpans(text) { rejectedWithSpans.append(text) }
    }
    #expect(rejectedWithSpans.isEmpty, "\(rejectedWithSpans.prefix(5))")
    #expect(lines == 20_000)
}

@Test func theFormattingFixtureLinesPassTheirOwnPrefilter() {
    let body = FixtureContent.make(.formatting, now: Date(timeIntervalSinceReferenceDate: 0)).notes[0].body
    for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
        let text = String(line)
        if !MarkupParser.parseLine(text, at: 0).isEmpty { #expect(mayHaveSpans(text), "\(text)") }
    }
}
