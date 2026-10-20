import Testing

@testable import ScratchCore

// Review focus 4: a restored cursor offset (UTF-16, as NSTextView counts) that falls inside an emoji, or beyond the
// end of a shorter text, never crashes and lands on a valid boundary.

@Test func clampsNegativeToZero() { #expect(TextOffset.clamp(-5, in: "abc") == 0) }

@Test func clampsBeyondEndToLength() { #expect(TextOffset.clamp(10, in: "abc") == 3) }

@Test func snapsOutOfASurrogatePair() { #expect(TextOffset.clamp(2, in: "a😀b") == 1) }

@Test func snapsToStartOfZWJSequence() { #expect(TextOffset.clamp(3, in: "👨‍👩‍👧x") == 0) }

@Test func keepsBoundaryOffsets() { #expect(TextOffset.clamp(3, in: "a😀b") == 3) }

@Test func keepsZeroAndEndOffsets() {
    #expect(TextOffset.clamp(0, in: "a😀b") == 0)
    #expect(TextOffset.clamp(4, in: "a😀b") == 4)
}

@Test func emptyTextAlwaysClampsToZero() {
    #expect(TextOffset.clamp(0, in: "") == 0)
    #expect(TextOffset.clamp(7, in: "") == 0)
    #expect(TextOffset.clamp(-1, in: "") == 0)
}

@Test func snapsToStartOfCRLF() {
    // "\r\n" is a single Character but two UTF-16 units, so offset 2 sits between them.
    #expect(TextOffset.clamp(2, in: "a\r\nb") == 1)
    #expect(TextOffset.clamp(3, in: "a\r\nb") == 3)
}

@Test func snapsToStartOfCombiningSequence() {
    // "e" + combining acute accent: one Character, two UTF-16 units.
    #expect(TextOffset.clamp(1, in: "e\u{301}x") == 0)
    #expect(TextOffset.clamp(2, in: "e\u{301}x") == 2)
}

/// The slow definition: the start of the `Character` that contains the offset, found by walking every `Character`.
private func referenceClamp(_ offset: Int, in text: String) -> Int {
    guard offset > 0 else { return 0 }
    var start = 0
    for index in text.indices {
        let at = index.utf16Offset(in: text)
        if at > offset { break }
        start = at
    }
    return offset >= text.utf16.count ? text.utf16.count : start
}

@Test func everyOffsetOfAnEmojiHeavyTextLandsOnABoundary() {
    let text = "a😀b👨‍👩‍👧c🇳🇴d"
    let boundaries = Set(text.indices.map { $0.utf16Offset(in: text) } + [text.utf16.count])
    for offset in -2...(text.utf16.count + 2) {
        let clamped = TextOffset.clamp(offset, in: text)
        #expect(boundaries.contains(clamped), "offset \(offset) clamped to \(clamped)")
        #expect(clamped <= max(offset, 0))
        #expect(clamped == referenceClamp(offset, in: text), "offset \(offset)")
    }
}

@Test func matchesTheReferenceWalkOnEveryCombinationOfAwkwardCharacters() {
    let pieces = ["a", "é", "e\u{301}", "😀", "👨‍👩‍👧", "🇳🇴", "\r\n", "\n", "한", "ᄒ\u{1161}\u{11AB}", "x\u{308}\u{308}", "👍🏽"]
    var checked = 0
    for first in pieces {
        for second in pieces {
            for third in pieces {
                let text = first + second + third
                for offset in -1...(text.utf16.count + 1) {
                    let clamped = TextOffset.clamp(offset, in: text)
                    if clamped != referenceClamp(offset, in: text) {
                        Issue.record("offset \(offset) in \(text.debugDescription): got \(clamped)")
                        return
                    }
                    checked += 1
                }
            }
        }
    }
    #expect(checked > 10_000)
}

@Test func clampingInAMultiMegabyteNoteIsFast() {
    // 50,000 lines of 48 accented letters, an emoji and a newline: about 5 MB, ending in "😀\n".
    let text = String(repeating: String(repeating: "é", count: 48) + "😀\n", count: 50_000)
    let offset = text.utf16.count - 2  // between the two halves of the last emoji
    var clamped = 0
    let elapsed = ContinuousClock().measure { clamped = TextOffset.clamp(offset, in: text) }
    #expect(clamped == offset - 1)
    #expect(elapsed < .milliseconds(20), "took \(elapsed)")
}
