import Foundation
import Testing

@testable import ScratchCore

// Spec §6.4 (the marker table and the marker rules): the parser finds what the editor renders, as UTF-16 ranges.

private func r(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

private func url(_ string: String) -> URL {
    URL(string: string)!
}

/// The body of the `formatting` fixture: the note the parser is checked against.
private func formattingBody() throws -> String {
    try #require(FixtureContent.make(.formatting, now: Date(timeIntervalSinceReferenceDate: 800_000_000)).notes.first)
        .body
}

// MARK: Bullets and checkboxes

@Test func bulletAtLineStart() {
    #expect(
        MarkupParser.parseLine("- a", at: 0) == [
            MarkupSpan(kind: .bullet(level: 0), range: r(0, 3), markers: [r(0, 1)], content: r(2, 1))
        ])
}

@Test func nestedBulletLevel() {
    #expect(
        MarkupParser.parseLine("    - a", at: 0) == [
            MarkupSpan(kind: .bullet(level: 2), range: r(0, 7), markers: [r(4, 1)], content: r(6, 1))
        ])
}

@Test func anOddIndentRoundsTheLevelDown() {
    #expect(
        MarkupParser.parseLine("   - a", at: 0) == [
            MarkupSpan(kind: .bullet(level: 1), range: r(0, 6), markers: [r(3, 1)], content: r(5, 1))
        ])
}

@Test func dashWithoutSpaceIsNotABullet() {
    #expect(MarkupParser.parseLine("-a", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("-", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("--- a", at: 0).isEmpty)
}

@Test func aTabBeforeTheDashIsNotAnIndent() {
    #expect(MarkupParser.parseLine("\t- a", at: 0).isEmpty)
}

@Test func emptyBulletIsABullet() {
    #expect(
        MarkupParser.parseLine("- ", at: 0) == [
            MarkupSpan(kind: .bullet(level: 0), range: r(0, 2), markers: [r(0, 1)], content: r(2, 0))
        ])
}

@Test func checkboxUncheckedAndChecked() {
    #expect(
        MarkupParser.parseLine("[ ] a", at: 0) == [
            MarkupSpan(kind: .checkbox(checked: false, level: 0), range: r(0, 5), markers: [r(0, 3)], content: r(4, 1))
        ])
    #expect(
        MarkupParser.parseLine("[x] a", at: 0) == [
            MarkupSpan(kind: .checkbox(checked: true, level: 0), range: r(0, 5), markers: [r(0, 3)], content: r(4, 1))
        ])
    #expect(
        MarkupParser.parseLine("[X] a", at: 0) == [
            MarkupSpan(kind: .checkbox(checked: true, level: 0), range: r(0, 5), markers: [r(0, 3)], content: r(4, 1))
        ])
}

@Test func nestedCheckboxLevel() {
    #expect(
        MarkupParser.parseLine("  [x] a", at: 0) == [
            MarkupSpan(kind: .checkbox(checked: true, level: 1), range: r(0, 7), markers: [r(2, 3)], content: r(6, 1))
        ])
}

@Test func emptyCheckboxIsACheckbox() {
    #expect(
        MarkupParser.parseLine("[ ] ", at: 0) == [
            MarkupSpan(kind: .checkbox(checked: false, level: 0), range: r(0, 4), markers: [r(0, 3)], content: r(4, 0))
        ])
}

@Test func aCheckboxNeedsItsSpaceAndItsLetter() {
    #expect(MarkupParser.parseLine("[ ]a", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("[ ]", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("[y] a", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("[] a", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("a [ ] b", at: 0).isEmpty)
}

@Test func bulletBeforeCheckboxIsABullet() {
    #expect(
        MarkupParser.parseLine("- [ ] a", at: 0) == [
            MarkupSpan(kind: .bullet(level: 0), range: r(0, 7), markers: [r(0, 1)], content: r(2, 5))
        ])
}

@Test func theContentOfAListLineGetsInlineSpans() {
    #expect(
        MarkupParser.parseLine("- **a**", at: 0) == [
            MarkupSpan(kind: .bullet(level: 0), range: r(0, 7), markers: [r(0, 1)], content: r(2, 5)),
            MarkupSpan(kind: .bold, range: r(2, 5), markers: [r(2, 2), r(5, 2)], content: r(4, 1)),
        ])
    #expect(
        MarkupParser.parseLine("[x] `c`", at: 0) == [
            MarkupSpan(kind: .checkbox(checked: true, level: 0), range: r(0, 7), markers: [r(0, 3)], content: r(4, 3)),
            MarkupSpan(kind: .inlineCode, range: r(4, 3), markers: [r(4, 1), r(6, 1)], content: r(5, 1)),
        ])
}

// MARK: Bold

@Test func boldRun() {
    #expect(
        MarkupParser.parseLine("a **b** c", at: 0) == [
            MarkupSpan(kind: .bold, range: r(2, 5), markers: [r(2, 2), r(5, 2)], content: r(4, 1))
        ])
}

@Test func boldNeedsNonSpaceEdges() {
    #expect(MarkupParser.parseLine("** a **", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("**a **", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("** a**", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("**\u{A0}a**", at: 0).isEmpty)
}

@Test func boldNeedsAtLeastOneCharacter() {
    #expect(MarkupParser.parseLine("****", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("a **** b", at: 0).isEmpty)
}

@Test func unclosedBoldIsPlain() {
    #expect(MarkupParser.parseLine("**a", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("a ** b", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("*a*", at: 0).isEmpty)
}

@Test func twoBoldRunsOnOneLine() {
    #expect(
        MarkupParser.parseLine("**a** and **b**", at: 0) == [
            MarkupSpan(kind: .bold, range: r(0, 5), markers: [r(0, 2), r(3, 2)], content: r(2, 1)),
            MarkupSpan(kind: .bold, range: r(10, 5), markers: [r(10, 2), r(13, 2)], content: r(12, 1)),
        ])
}

@Test func anUnclosedStarPairBeforeABoldRunStaysPlain() {
    #expect(
        MarkupParser.parseLine("**a **b**", at: 0) == [
            MarkupSpan(kind: .bold, range: r(4, 5), markers: [r(4, 2), r(7, 2)], content: r(6, 1))
        ])
}

// Bold needs word boundaries (docs/decisions/0006): an opening `**` follows the line start or a character that is not a
// letter or a digit, a closing one is followed by the line end or such a character, and stars with punctuation on both
// sides are a glob or an operator, never a marker.

@Test func intrawordStarsAreNotBold() {
    #expect(MarkupParser.parseLine("x**2 + y**2", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("2**10 and 3**4", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("area = w**2*h", at: 0).isEmpty)
}

@Test func globsAreNotBold() {
    #expect(MarkupParser.parseLine("src/**/*.ts and lib/**/*.js", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("**/*.ts and **/*.js", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("\"**/*.ts\",\"**/*.js\"", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("git add src/**/*.swift", at: 0).isEmpty)
}

@Test func boldAfterPunctuationStillWorks() {
    #expect(
        MarkupParser.parseLine("(**a**)", at: 0) == [
            MarkupSpan(kind: .bold, range: r(1, 5), markers: [r(1, 2), r(4, 2)], content: r(3, 1))
        ])
    #expect(
        MarkupParser.parseLine("\"**a**\", **b**; (**c** d)", at: 0).map(\.range) == [r(1, 5), r(9, 5), r(17, 5)])
}

@Test func boldAtLineEdgesStillWorks() {
    #expect(
        MarkupParser.parseLine("**a**", at: 0) == [
            MarkupSpan(kind: .bold, range: r(0, 5), markers: [r(0, 2), r(3, 2)], content: r(2, 1))
        ])
    #expect(MarkupParser.parseLine("**a** x", at: 0).map(\.range) == [r(0, 5)])
    #expect(MarkupParser.parseLine("x **a**", at: 0).map(\.range) == [r(2, 5)])
}

@Test func wordGluedBoldIsPlain() {
    #expect(MarkupParser.parseLine("a**b**c", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("a**b** c", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("a **b**c", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("**a**b", at: 0).isEmpty)
}

@Test func aGluedRunDoesNotHideALaterBoldRun() {
    // The first run is glued to a word on its right, so it is plain. The second is bold.
    #expect(
        MarkupParser.parseLine("**a**b and **c**", at: 0) == [
            MarkupSpan(kind: .bold, range: r(11, 5), markers: [r(11, 2), r(14, 2)], content: r(13, 1))
        ])
    #expect(MarkupParser.parseLine("a**b** **c**", at: 0).map(\.range) == [r(7, 5)])
}

@Test func theBoundaryIsALetterOrDigitOfAnyScript() {
    #expect(MarkupParser.parseLine("é**a**", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("e\u{301}**a**", at: 0).isEmpty, "a letter with a combining accent is a letter")
    #expect(MarkupParser.parseLine("日本**語**", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("**a**é", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("**a**٣", at: 0).isEmpty, "an Arabic-Indic digit is a digit")
}

@Test func anEmojiIsNotALetter() {
    // The emoji is two UTF-16 units: the stars start at 2.
    #expect(
        MarkupParser.parseLine("😀**a**😀", at: 0) == [
            MarkupSpan(kind: .bold, range: r(2, 5), markers: [r(2, 2), r(5, 2)], content: r(4, 1))
        ])
}

@Test func starsBetweenPunctuationAreNotBold() {
    // `)**(` is a power or a glob, even though the content would not start or end with white space.
    #expect(MarkupParser.parseLine("(a+b)**(n)", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("f(x)**(2) + g(y)**(3)", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("[a]**[b]", at: 0).isEmpty)
}

@Test func punctuationOnOneSideIsEnough() {
    #expect(MarkupParser.parseLine("(**Note**) x", at: 0).map(\.range) == [r(1, 8)])
    #expect(MarkupParser.parseLine("**Note:** x", at: 0).map(\.range) == [r(0, 9)])
    #expect(MarkupParser.parseLine("a **\"q\"** b", at: 0).map(\.range) == [r(2, 7)])
}

@Test func starsBetweenPunctuationAreTheTradeOffOfThatRule() {
    // Content that starts or ends with punctuation, right inside punctuation, is plain too: the stars stay visible.
    #expect(MarkupParser.parseLine("(**Note:**)", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("(**\"q\"**)", at: 0).isEmpty)
}

@Test func inlineCodeNextToStarsIsAPunctuationBoundary() {
    // The backticks are what stands next to the stars, not the letters inside the code.
    #expect(MarkupParser.parseLine("a **`b`** c", at: 0).map(\.kind) == [.bold, .inlineCode])
    #expect(MarkupParser.parseLine("`ab`**c**", at: 0).map(\.kind) == [.inlineCode, .bold])
}

// MARK: Inline code

@Test func inlineCodeRun() {
    #expect(
        MarkupParser.parseLine("a `b` c", at: 0) == [
            MarkupSpan(kind: .inlineCode, range: r(2, 3), markers: [r(2, 1), r(4, 1)], content: r(3, 1))
        ])
}

@Test func inlineCodeBeatsBold() {
    #expect(
        MarkupParser.parseLine("`**x**`", at: 0) == [
            MarkupSpan(kind: .inlineCode, range: r(0, 7), markers: [r(0, 1), r(6, 1)], content: r(1, 5))
        ])
}

@Test func inlineCodeNeedsContentAndACloser() {
    #expect(MarkupParser.parseLine("``", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("`a", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("a ` b", at: 0).isEmpty)
}

@Test func twoInlineCodeRunsOnOneLine() {
    #expect(
        MarkupParser.parseLine("`a` `b`", at: 0) == [
            MarkupSpan(kind: .inlineCode, range: r(0, 3), markers: [r(0, 1), r(2, 1)], content: r(1, 1)),
            MarkupSpan(kind: .inlineCode, range: r(4, 3), markers: [r(4, 1), r(6, 1)], content: r(5, 1)),
        ])
}

@Test func boldAroundInlineCodeKeepsBothRuns() {
    #expect(
        MarkupParser.parseLine("**a `b` c**", at: 0) == [
            MarkupSpan(kind: .bold, range: r(0, 11), markers: [r(0, 2), r(9, 2)], content: r(2, 7)),
            MarkupSpan(kind: .inlineCode, range: r(4, 3), markers: [r(4, 1), r(6, 1)], content: r(5, 1)),
        ])
}

@Test func starsInsideInlineCodeNeitherOpenNorCloseBold() {
    // The two stars in the code are not a closing marker: the bold run ends at the stars after it.
    #expect(
        MarkupParser.parseLine("**a `**` b**", at: 0) == [
            MarkupSpan(kind: .bold, range: r(0, 12), markers: [r(0, 2), r(10, 2)], content: r(2, 8)),
            MarkupSpan(kind: .inlineCode, range: r(4, 4), markers: [r(4, 1), r(7, 1)], content: r(5, 2)),
        ])
    #expect(
        MarkupParser.parseLine("`**` a **b", at: 0) == [
            MarkupSpan(kind: .inlineCode, range: r(0, 4), markers: [r(0, 1), r(3, 1)], content: r(1, 2))
        ])
}

@Test func inlineCodeBeatsABoldRunThatItWouldCut() {
    #expect(
        MarkupParser.parseLine("**a `b** c`", at: 0) == [
            MarkupSpan(kind: .inlineCode, range: r(4, 7), markers: [r(4, 1), r(10, 1)], content: r(5, 5))
        ])
}

// MARK: Links and offsets

@Test func aLinkIsASpanWithNoMarkers() {
    #expect(
        MarkupParser.parseLine("see https://x.io now", at: 0) == [
            MarkupSpan(kind: .link(url("https://x.io")), range: r(4, 12), markers: [], content: r(4, 12))
        ])
}

@Test func boldAroundALinkDoesNotSwallowItsMarkers() {
    #expect(
        MarkupParser.parseLine("**https://x.io**", at: 0) == [
            MarkupSpan(kind: .bold, range: r(0, 16), markers: [r(0, 2), r(14, 2)], content: r(2, 12)),
            MarkupSpan(kind: .link(url("https://x.io")), range: r(2, 12), markers: [], content: r(2, 12)),
        ])
}

@Test func aLinkInsideInlineCodeIsLiteral() {
    #expect(
        MarkupParser.parseLine("`https://x.io`", at: 0) == [
            MarkupSpan(kind: .inlineCode, range: r(0, 14), markers: [r(0, 1), r(13, 1)], content: r(1, 12))
        ])
}

@Test func utf16OffsetsAfterEmoji() {
    #expect(
        MarkupParser.parseLine("😀 **b**", at: 0) == [
            MarkupSpan(kind: .bold, range: r(3, 5), markers: [r(3, 2), r(6, 2)], content: r(5, 1))
        ])
}

@Test func parseUsesLineStart() {
    #expect(
        MarkupParser.parseLine("- a", at: 10) == [
            MarkupSpan(kind: .bullet(level: 0), range: r(10, 3), markers: [r(10, 1)], content: r(12, 1))
        ])
    #expect(
        MarkupParser.parseLine("a **b**", at: 10) == [
            MarkupSpan(kind: .bold, range: r(12, 5), markers: [r(12, 2), r(15, 2)], content: r(14, 1))
        ])
}

@Test func spansAreOrderedByLocation() {
    let spans = MarkupParser.parseLine("- `a` **b** https://x.io", at: 0)
    #expect(spans.map(\.range.location) == [0, 2, 6, 12])
    #expect(spans.map(\.range.location) == spans.map(\.range.location).sorted())
}

@Test func aLineWithoutMarkersHasNoSpans() {
    #expect(MarkupParser.parseLine("", at: 0).isEmpty)
    #expect(MarkupParser.parseLine("just some text", at: 0).isEmpty)
}

// MARK: Whole text

@Test func parseOffsetsSpansByLine() {
    #expect(
        MarkupParser.parse("a\n- b\n**c**") == [
            MarkupSpan(kind: .bullet(level: 0), range: r(2, 3), markers: [r(2, 1)], content: r(4, 1)),
            MarkupSpan(kind: .bold, range: r(6, 5), markers: [r(6, 2), r(9, 2)], content: r(8, 1)),
        ])
}

@Test func parseHandlesEveryLineBreak() {
    let bullets = [
        MarkupSpan(kind: .bullet(level: 0), range: r(0, 3), markers: [r(0, 1)], content: r(2, 1))
    ]
    #expect(MarkupParser.parse("- a\r\n- b").map(\.range) == [r(0, 3), r(5, 3)])
    #expect(MarkupParser.parse("- a\r- b").map(\.range) == [r(0, 3), r(4, 3)])
    #expect(MarkupParser.parse("- a\n- b").map(\.range) == [r(0, 3), r(4, 3)])
    #expect(MarkupParser.parse("- a\r\n") == bullets)
}

@Test func parseOfNothingIsNothing() {
    #expect(MarkupParser.parse("").isEmpty)
    #expect(MarkupParser.parse("\n\n").isEmpty)
}

@Test func markersInsideCodeBlocksAreLiteral() throws {
    let body = try formattingBody()
    let blocks = FenceScanner.codeBlocks(in: body)
    let block = try #require(blocks.first)
    #expect(blocks.count == 1)
    let spans = MarkupParser.parse(body)
    #expect(!spans.isEmpty)
    for span in spans {
        #expect(NSIntersectionRange(span.range, block).length == 0, "\(span.kind) at \(span.range)")
    }
    // The block holds a "- " and a "**not bold**": both are text.
    #expect(body.contains("- not a bullet") && body.contains("**not bold**"))
    #expect(spans.last.map { NSMaxRange($0.range) <= block.location } == true)
}

@Test func theFormattingFixtureHasEveryKindOfSpan() throws {
    let spans = MarkupParser.parse(try formattingBody())
    #expect(
        spans.map(\.kind) == [
            .bullet(level: 0), .bullet(level: 1), .checkbox(checked: false, level: 0),
            .checkbox(checked: true, level: 0), .bold, .inlineCode, .link(url("https://example.com/a_(b)?q=1")),
        ])
}

@Test func theFixtureLineWithBoldCodeAndALink() throws {
    let body = try formattingBody()
    let line = try #require(body.split(separator: "\n").first { $0.hasPrefix("Some ") })
    let start = NSString(string: body).range(of: String(line)).location
    #expect(
        MarkupParser.parseLine(String(line), at: start) == [
            MarkupSpan(
                kind: .bold, range: r(start + 5, 8), markers: [r(start + 5, 2), r(start + 11, 2)],
                content: r(start + 7, 4)),
            MarkupSpan(
                kind: .inlineCode, range: r(start + 20, 17), markers: [r(start + 20, 1), r(start + 36, 1)],
                content: r(start + 21, 15)),
            MarkupSpan(
                kind: .link(url("https://example.com/a_(b)?q=1")), range: r(start + 42, 29), markers: [],
                content: r(start + 42, 29)),
        ])
}

@Test func anUnclosedFenceLeavesTheRestOfTheNoteRendered() {
    #expect(MarkupParser.parse("```\n- a").map(\.range) == [r(4, 3)])
}

@Test func linesAfterAClosedBlockAreRenderedAgain() {
    #expect(MarkupParser.parse("```\n- a\n```\n- b").map(\.range) == [r(12, 3)])
}

@Test func aSecondBlockIsLiteralToo() {
    #expect(MarkupParser.parse("- a\n```\n- b\n```\n- c\n```\n- d\n```").map(\.range) == [r(0, 3), r(16, 3)])
}

// MARK: Invariants

/// A generator that gives the same numbers on every run, so a failing line can be found again.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
    inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
}

@Test func spansOfAnyLineAreWellFormed() {
    let pieces = [
        "-", " ", " ", "*", "**", "`", "[", "]", "x", "a", "b", "http", "https", "://", ".", "(", ")", "😀", "\t",
        "- ", "[ ] ", "https://x.io", "**a**", "`a`",
    ]
    var random = SplitMix64(state: 2026)
    for _ in 0..<5_000 {
        let line = (0..<Int.random(in: 0...14, using: &random)).map { _ in pieces.randomElement(using: &random)! }
            .joined()
        let start = Int.random(in: 0...50, using: &random)
        let text = NSString(string: line)
        let whole = r(start, text.length)
        let spans = MarkupParser.parseLine(line, at: start)
        let context = "\(line.debugDescription) at \(start)"

        #expect(spans.map(\.range.location) == spans.map(\.range.location).sorted(), "\(context)")
        var codeRuns: [NSRange] = []
        var starMarkers: [NSRange] = []
        for span in spans {
            #expect(contains(whole, span.range), "\(context): \(span)")
            #expect(contains(span.range, span.content), "\(context): \(span)")
            for marker in span.markers {
                #expect(contains(span.range, marker), "\(context): \(span)")
            }
            func local(_ range: NSRange) -> String { text.substring(with: r(range.location - start, range.length)) }
            switch span.kind {
            case .bullet, .checkbox:
                #expect(span.range == whole, "\(context)")
            case .inlineCode:
                codeRuns.append(span.range)
                #expect(span.markers.map(local) == ["`", "`"], "\(context)")
                #expect(span.content.length >= 1 && !local(span.content).contains("`"), "\(context)")
            case .bold:
                starMarkers.append(contentsOf: span.markers)
                #expect(span.markers.map(local) == ["**", "**"], "\(context)")
                let content = local(span.content)
                #expect(span.content.length >= 1, "\(context)")
                #expect(
                    !(content.unicodeScalars.first?.properties.isWhitespace ?? true)
                        && !(content.unicodeScalars.last?.properties.isWhitespace ?? true), "\(context)")
            case .link:
                #expect(span.markers.isEmpty && span.content == span.range, "\(context)")
                #expect(local(span.range).lowercased().hasPrefix("http"), "\(context)")
            }
        }
        for span in spans {
            if case .link = span.kind {
                for other in codeRuns + starMarkers {
                    #expect(NSIntersectionRange(span.range, other).length == 0, "\(context): \(span) meets \(other)")
                }
            }
            if case .bold = span.kind {
                for code in codeRuns {
                    let overlap = NSIntersectionRange(span.range, code)
                    #expect(overlap.length == 0 || overlap == code, "\(context): bold cuts code \(code)")
                }
            }
        }
        for (first, second) in zip(codeRuns, codeRuns.dropFirst()) {
            #expect(NSMaxRange(first) <= second.location, "\(context)")
        }
    }
}

@Test func spansOfAnyTextStayOutsideItsCodeBlocks() {
    let pieces = [
        "\n", "\n", "\r\n", "\r", "```", "```sh", "  ```", "- ", "[x] ", "**a**", "`a`", "https://x.io", "a", " ", "😀",
    ]
    var random = SplitMix64(state: 7)
    for _ in 0..<2_000 {
        let text = (0..<Int.random(in: 0...20, using: &random)).map { _ in pieces.randomElement(using: &random)! }
            .joined()
        let length = NSString(string: text).length
        let blocks = FenceScanner.codeBlocks(in: text)
        let context = "\(text.debugDescription)"
        for (first, second) in zip(blocks, blocks.dropFirst()) {
            #expect(NSMaxRange(first) < second.location, "\(context)")
        }
        for block in blocks {
            #expect(contains(r(0, length), block), "\(context): \(block)")
        }
        let spans = MarkupParser.parse(text)
        #expect(spans.map(\.range.location) == spans.map(\.range.location).sorted(), "\(context)")
        for span in spans {
            #expect(contains(r(0, length), span.range), "\(context): \(span)")
            for block in blocks {
                #expect(NSIntersectionRange(span.range, block).length == 0, "\(context): \(span) in \(block)")
            }
        }
    }
}
