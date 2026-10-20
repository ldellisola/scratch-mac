import Foundation
import Testing

@testable import ScratchCore

// Plan 3, task 3 (spec §6.4): the editor keeps the fenced blocks of a note up to date from one edit to the next. Inside
// a block nothing is formatting (docs/features/formatting.md).

private func r(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

/// The text `a`, a block of `sh` code holding `b`, and the text `c`. The paragraphs start at 0, 2 (the opening fence), 8,
/// 10 (the closing fence) and 14. The block is 2..<13: from the start of the opening fence line to the end of the
/// closing one, which is where its line break is.
private let sample = "a\n```sh\nb\n```\nc"

@Test func theIndexKnowsTheFenceLinesOfEachBlock() {
    let index = CodeBlockIndex(text: sample)
    #expect(index.blocks == [CodeBlockIndex.Block(range: r(2, 11), openingLineEnd: 7, closingLineStart: 10)])
}

@Test func anIndexOfUnitsIsTheSameAsOneOfText() {
    #expect(CodeBlockIndex(units: Array(sample.utf16)) == CodeBlockIndex(text: sample))
}

@Test func aFenceWithoutAPartnerIsNoBlock() {
    #expect(CodeBlockIndex(text: "a\n```\nb").blocks.isEmpty)
    #expect(CodeBlockIndex(text: "").blocks.isEmpty)
}

@Test func twoBlocksAreBothIndexed() {
    let text = "```\na\n```\nx\n```\nb\n```"
    let index = CodeBlockIndex(text: text)
    #expect(index.blocks.map(\.range) == FenceScanner.codeBlocks(in: text))
    #expect(index.blocks.count == 2)
}

@Test func crlfLinesAreIndexed() {
    let text = "a\r\n```\r\nb\r\n```\r\nc"
    let index = CodeBlockIndex(text: text)
    #expect(index.blocks.map(\.range) == FenceScanner.codeBlocks(in: text))
    #expect(index.blocks[0].openingLineEnd == 6)
    #expect(index.blocks[0].closingLineStart == 11)
}

@Test func containsCountsBothEndsOfTheBlock() {
    let index = CodeBlockIndex(text: sample)
    #expect(!index.contains(0))
    #expect(!index.contains(1))
    #expect(index.contains(2))
    #expect(index.contains(8))
    #expect(index.contains(13))
    #expect(!index.contains(14))
    #expect(!index.contains(15))
}

@Test func intersectsCountsEveryCharacterOfTheBlockAndItsFenceLines() {
    let index = CodeBlockIndex(text: sample)
    #expect(!index.intersects(r(0, 2)), "the paragraph before the block, with its line break")
    #expect(index.intersects(r(0, 3)), "the line break and the first backtick")
    #expect(index.intersects(r(2, 6)), "the opening fence line, with its line break")
    #expect(index.intersects(r(8, 2)), "the line inside the block")
    #expect(index.intersects(r(10, 4)), "the closing fence line, with its line break")
    #expect(index.intersects(r(13, 1)), "the end of the closing fence line")
    #expect(!index.intersects(r(14, 1)), "the paragraph after the block")
    #expect(index.intersects(r(0, 15)), "a selection that holds the whole block")
    #expect(index.intersects(r(4, 1)), "a selection inside it")
}

@Test func anEmptyRangeIntersectsAsAPosition() {
    let index = CodeBlockIndex(text: sample)
    #expect(!index.intersects(r(1, 0)))
    #expect(index.intersects(r(2, 0)))
    #expect(index.intersects(r(9, 0)))
    #expect(index.intersects(r(13, 0)))
    #expect(!index.intersects(r(14, 0)))
}

@Test func intersectsLooksPastTheBlocksBeforeTheRange() {
    let text = "```\na\n```\nx\n```\nb\n```\ny"
    let index = CodeBlockIndex(text: text)
    #expect(index.blocks.count == 2)
    #expect(!index.intersects(r(10, 2)), "x and its line break lie between the blocks")
    #expect(index.intersects(r(10, 3)), "up to the first backtick of the second block")
    #expect(!index.intersects(r(22, 1)), "y after the last block")
    #expect(!CodeBlockIndex().intersects(r(0, 5)))
}

@Test func coversFollowsTheParagraphRuleOfTheParser() {
    let index = CodeBlockIndex(text: sample)
    #expect(!index.covers(paragraphStart: 0))
    #expect(index.covers(paragraphStart: 2))
    #expect(index.covers(paragraphStart: 8))
    #expect(index.covers(paragraphStart: 10))
    #expect(!index.covers(paragraphStart: 14))
}

@Test func coversAgreesWithParseOnEveryLine() {
    // The third fence has no partner, so "- e" after it is a bullet again.
    let text = "- a\n```\n- b\n**c**\n```\n- d\n```\n- e"
    let index = CodeBlockIndex(text: text)
    let spans = MarkupParser.parse(text)
    var start = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let hasSpan = spans.contains { NSIntersectionRange($0.range, r(start, line.utf16.count)).length > 0 }
        let isFence = FenceScanner.isFenceLine(String(line))
        if index.covers(paragraphStart: start) {
            #expect(!hasSpan, "\(line) is in a block and has a span")
        } else if !isFence {
            #expect(hasSpan, "\(line) is outside the blocks and has none")
        }
        start += line.utf16.count + 1
    }
}

@Test func anEditInTheMiddleOfABlockDoesNotTouchItsFenceLines() {
    let index = CodeBlockIndex(text: sample)
    #expect(!index.touchesFenceLine(r(8, 0)))
    #expect(!index.touchesFenceLine(r(8, 1)))
    #expect(!index.touchesFenceLine(r(9, 0)))
}

@Test func anEditOnAFenceLineTouchesIt() {
    let index = CodeBlockIndex(text: sample)
    #expect(index.touchesFenceLine(r(2, 0)))
    #expect(index.touchesFenceLine(r(4, 1)))
    #expect(index.touchesFenceLine(r(7, 0)))
    #expect(index.touchesFenceLine(r(7, 1)))
    #expect(index.touchesFenceLine(r(10, 0)))
    #expect(index.touchesFenceLine(r(13, 0)))
}

@Test func joiningALineToAFenceLineTouchesIt() {
    // Deleting the line break after "b" makes the closing fence line "b```", which is no fence.
    let index = CodeBlockIndex(text: sample)
    #expect(index.touchesFenceLine(r(9, 1)))
    // So does deleting the line break after "a".
    #expect(index.touchesFenceLine(r(1, 1)))
}

@Test func anEditOutsideTheBlockDoesNotTouchIt() {
    let index = CodeBlockIndex(text: sample)
    #expect(!index.touchesFenceLine(r(0, 1)))
    #expect(!index.touchesFenceLine(r(14, 1)))
}

@Test func typingInsideABlockMovesItsEnd() {
    var index = CodeBlockIndex(text: sample)
    index.apply(EditMapping(replaced: r(9, 0), newLength: 3))
    #expect(index.blocks == [CodeBlockIndex.Block(range: r(2, 14), openingLineEnd: 7, closingLineStart: 13)])
    #expect(index == CodeBlockIndex(text: "a\n```sh\nbxyz\n```\nc"))
}

@Test func typingBeforeABlockMovesAllOfIt() {
    var index = CodeBlockIndex(text: sample)
    index.apply(EditMapping(replaced: r(1, 0), newLength: 2))
    #expect(index.blocks == [CodeBlockIndex.Block(range: r(4, 11), openingLineEnd: 9, closingLineStart: 12)])
    #expect(index == CodeBlockIndex(text: "axy\n```sh\nb\n```\nc"))
}

@Test func typingAfterABlockLeavesIt() {
    var index = CodeBlockIndex(text: sample)
    index.apply(EditMapping(replaced: r(14, 0), newLength: 5))
    #expect(index == CodeBlockIndex(text: sample))
}

@Test func deletingALineInsideABlockShrinksIt() {
    var index = CodeBlockIndex(text: "```\na\nb\n```")
    // "a\n" is 4..<6.
    index.apply(EditMapping(replaced: r(4, 2), newLength: 0))
    #expect(index == CodeBlockIndex(text: "```\nb\n```"))
}

@Test func deletingABlockWholeRemovesIt() {
    var index = CodeBlockIndex(text: sample)
    index.apply(EditMapping(replaced: r(2, 12), newLength: 0))
    #expect(index.blocks.isEmpty)
}

@Test func addingTheClosingFenceChangesTheParagraphsBetween() {
    let before = CodeBlockIndex(text: "a\n```\nb\nc")
    let after = CodeBlockIndex(text: "a\n```\nb\nc\n```")
    #expect(before.blocks.isEmpty)
    // The block runs from the opening fence at 2 to the end of the text at 13.
    #expect(after.changedRanges(comparedTo: before) == [r(2, 11)])
    #expect(before.changedRanges(comparedTo: after) == [r(2, 11)])
}

@Test func changedRangesOfEqualIndicesAreEmpty() {
    let index = CodeBlockIndex(text: sample)
    #expect(index.changedRanges(comparedTo: index).isEmpty)
    #expect(CodeBlockIndex().changedRanges(comparedTo: CodeBlockIndex()).isEmpty)
}

@Test func movingAFenceLineChangesOnlyTheParagraphsItPassed() {
    // The closing fence moves from after "b" to after "c", so the paragraph "c" joins the block. In the first text
    // the block is 0..<9 and in the second 0..<11: the paragraphs that start in 9..<11 are the ones that changed.
    let before = CodeBlockIndex(text: "```\nb\n```\nc\nd")
    let after = CodeBlockIndex(text: "```\nb\nc\n```\nd")
    #expect(before.blocks.map(\.range) == [r(0, 9)])
    #expect(after.blocks.map(\.range) == [r(0, 11)])
    #expect(after.changedRanges(comparedTo: before) == [r(9, 2)])
    #expect(before.changedRanges(comparedTo: after) == [r(9, 2)])
}

@Test func changedRangesSplitAroundSharedBlocks() {
    let before = CodeBlockIndex(blocks: [
        .init(range: r(0, 10), openingLineEnd: 3, closingLineStart: 7),
        .init(range: r(20, 10), openingLineEnd: 23, closingLineStart: 27),
    ])
    let after = CodeBlockIndex(blocks: [
        .init(range: r(5, 30), openingLineEnd: 8, closingLineStart: 32)
    ])
    // Only before: 0..<5. Only after: 10..<20 and 30..<35. In both: 5..<10 and 20..<30.
    let changed = after.changedRanges(comparedTo: before)
    #expect(Set(changed.map { "\($0.location),\($0.length)" }) == ["0,5", "10,10", "30,5"])
    #expect(changed.count == 3)
}
