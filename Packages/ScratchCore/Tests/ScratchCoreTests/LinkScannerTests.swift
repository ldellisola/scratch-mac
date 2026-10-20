import Foundation
import Testing

@testable import ScratchCore

// Spec §6.4 (links): any http(s):// URL gets the link colour, and ⌘-click opens it. Trailing punctuation is not part
// of it, and a link inside inline code is literal.

private func r(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

private func link(_ string: String, _ location: Int, _ length: Int) -> MarkupSpan {
    MarkupSpan(kind: .link(URL(string: string)!), range: r(location, length), markers: [], content: r(location, length))
}

private func links(_ line: String, at lineStart: Int = 0, excluding: [NSRange] = []) -> [MarkupSpan] {
    LinkScanner.links(in: line, at: lineStart, excluding: excluding)
}

@Test func plainURL() {
    #expect(links("see https://example.com/path now") == [link("https://example.com/path", 4, 24)])
    #expect(links("http://x.io") == [link("http://x.io", 0, 11)])
    #expect(links("https://x.io") == [link("https://x.io", 0, 12)])
}

@Test func theURLKeepsItsQueryAndFragment() {
    #expect(links("https://x.io/a?b=1&c=2#top") == [link("https://x.io/a?b=1&c=2#top", 0, 26)])
}

@Test func trailingPeriodExcluded() {
    #expect(links("go to https://x.io.") == [link("https://x.io", 6, 12)])
}

@Test func everyTrailingPunctuationMarkIsExcluded() {
    for mark in [".", ",", ";", ":", "!", "?", "'", "\""] {
        #expect(links("https://x.io/a\(mark)") == [link("https://x.io/a", 0, 14)], "\(mark)")
    }
    #expect(links("https://x.io/a?!.") == [link("https://x.io/a", 0, 14)])
}

@Test func punctuationInTheMiddleStays() {
    #expect(links("https://x.io/a.b,c;d:e!f'g") == [link("https://x.io/a.b,c;d:e!f'g", 0, 26)])
}

@Test func balancedParenKept() {
    #expect(links("https://example.com/a_(b)") == [link("https://example.com/a_(b)", 0, 25)])
    #expect(links("https://example.com/a_(b).") == [link("https://example.com/a_(b)", 0, 25)])
}

@Test func unbalancedParenExcluded() {
    #expect(links("(see https://x.io)") == [link("https://x.io", 5, 12)])
    #expect(links("(see https://x.io).") == [link("https://x.io", 5, 12)])
    #expect(links("(see https://x.io/a_(b))") == [link("https://x.io/a_(b)", 5, 18)])
}

@Test func theURLEndsAtWhitespace() {
    #expect(links("https://a.io\thttps://b.io") == [link("https://a.io", 0, 12), link("https://b.io", 13, 12)])
    #expect(links("https://a.io https://b.io") == [link("https://a.io", 0, 12), link("https://b.io", 13, 12)])
    #expect(links("https://a.io\u{A0}x") == [link("https://a.io", 0, 12)])
}

@Test func linkInsideInlineCodeIgnored() {
    #expect(links("`https://x.io`", excluding: [r(0, 14)]).isEmpty)
    #expect(links("a `see https://x.io` b", excluding: [r(2, 18)]).isEmpty)
}

@Test func aLinkStopsWhereAnExcludedRangeBegins() {
    #expect(links("https://x.io`code`", excluding: [r(12, 6)]) == [link("https://x.io", 0, 12)])
    #expect(links("**https://x.io**", excluding: [r(0, 2), r(14, 2)]) == [link("https://x.io", 2, 12)])
}

@Test func aLinkAfterAnExcludedRangeIsFound() {
    #expect(links("`a` https://x.io", excluding: [r(0, 3)]) == [link("https://x.io", 4, 12)])
}

@Test func excludedRangesAreInDocumentOffsets() {
    #expect(links("`https://x.io`", at: 100, excluding: [r(100, 14)]).isEmpty)
    #expect(links("`a` https://x.io", at: 100, excluding: [r(100, 3)]) == [link("https://x.io", 104, 12)])
}

@Test func ftpIsNotALink() {
    #expect(links("ftp://x.io").isEmpty)
    #expect(links("mailto:a@b.io").isEmpty)
    #expect(links("www.x.io").isEmpty)
}

@Test func aSchemeWithNothingAfterItIsNotALink() {
    #expect(links("https://").isEmpty)
    #expect(links("https://.").isEmpty)
    #expect(links("http:// x").isEmpty)
}

@Test func twoLinksOnOneLine() {
    #expect(links("https://a.io and http://b.io") == [link("https://a.io", 0, 12), link("http://b.io", 17, 11)])
}

@Test func theSchemeIsCaseInsensitive() {
    #expect(links("HTTPS://X.IO") == [link("HTTPS://X.IO", 0, 12)])
}

@Test func linkOffsetsAreUTF16AfterAnEmoji() {
    #expect(links("😀 https://x.io") == [link("https://x.io", 3, 12)])
}

@Test func lineStartIsAddedToEveryRange() {
    #expect(links("see https://x.io", at: 100) == [link("https://x.io", 104, 12)])
}

@Test func aLineWithoutLinksHasNone() {
    #expect(links("").isEmpty)
    #expect(links("just text, no link").isEmpty)
}
