import Foundation
import Testing

@testable import ScratchCore

// Spec §6.4 (marker rules): inside a block fenced by lines of three backticks every character is literal. A fence
// with no partner is plain text, so typing three backticks never un-renders the rest of the note.

private func r(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

@Test func aFenceLineIsSpacesThenThreeBackticks() {
    #expect(FenceScanner.isFenceLine("```"))
    #expect(FenceScanner.isFenceLine("```swift"))
    #expect(FenceScanner.isFenceLine("  ```"))
    #expect(FenceScanner.isFenceLine("````"))
    #expect(FenceScanner.isFenceLine("``` text after it"))
}

@Test func otherLinesAreNotFences() {
    #expect(!FenceScanner.isFenceLine(""))
    #expect(!FenceScanner.isFenceLine("``"))
    #expect(!FenceScanner.isFenceLine("`` `"))
    #expect(!FenceScanner.isFenceLine("a ```"))
    #expect(!FenceScanner.isFenceLine("\t```"))
    #expect(!FenceScanner.isFenceLine("- ```"))
}

@Test func pairOfFencesIsABlock() {
    // The block runs from the start of the opening fence line to the end of the closing one, without its line break.
    #expect(FenceScanner.codeBlocks(in: "a\n```\nb\n```\nc") == [r(2, 9)])
}

@Test func theBlockEndsAtTheEndOfTheClosingLine() {
    #expect(FenceScanner.codeBlocks(in: "```\nx\n```\ny") == [r(0, 9)])
    #expect(FenceScanner.codeBlocks(in: "```\nx\n```") == [r(0, 9)])
    #expect(FenceScanner.codeBlocks(in: "```\nx\n```\n") == [r(0, 9)])
}

@Test func unclosedFenceIsNotABlock() {
    #expect(FenceScanner.codeBlocks(in: "```\na").isEmpty)
    #expect(FenceScanner.codeBlocks(in: "a\n```swift\nb\nc").isEmpty)
    #expect(FenceScanner.codeBlocks(in: "```").isEmpty)
}

@Test func indentedFenceCounts() {
    #expect(FenceScanner.codeBlocks(in: "  ```\nx\n  ```") == [r(0, 13)])
}

@Test func fourBackticksCount() {
    #expect(FenceScanner.codeBlocks(in: "````\nx\n````") == [r(0, 11)])
}

@Test func theOpeningFenceMayNameALanguage() {
    #expect(FenceScanner.codeBlocks(in: "```sh\nx\n```") == [r(0, 11)])
}

@Test func twoBlocks() {
    #expect(FenceScanner.codeBlocks(in: "```\na\n```\nb\n```\nc\n```") == [r(0, 9), r(12, 9)])
}

@Test func aThirdFenceStaysUnclosed() {
    #expect(FenceScanner.codeBlocks(in: "```\na\n```\nb\n```\nc") == [r(0, 9)])
}

@Test func emptyLinesInsideABlockBelongToIt() {
    #expect(FenceScanner.codeBlocks(in: "```\n\n```") == [r(0, 8)])
}

@Test func crlfLines() {
    #expect(FenceScanner.codeBlocks(in: "```\r\na\r\n```") == [r(0, 11)])
    #expect(FenceScanner.codeBlocks(in: "a\r\n```\r\nb\r\n```\r\nc") == [r(3, 11)])
}

@Test func loneCarriageReturnLines() {
    #expect(FenceScanner.codeBlocks(in: "```\ra\r```") == [r(0, 9)])
}

@Test func blockOffsetsAreUTF16AfterAnEmoji() {
    #expect(FenceScanner.codeBlocks(in: "😀\n```\nx\n```") == [r(3, 9)])
}

@Test func textWithoutFencesHasNoBlocks() {
    #expect(FenceScanner.codeBlocks(in: "").isEmpty)
    #expect(FenceScanner.codeBlocks(in: "plain\ntext").isEmpty)
    #expect(FenceScanner.codeBlocks(in: "a `b` c\n``\n`").isEmpty)
}

@Test func hugeNoteBlocksAreTheFencedSwiftBlocks() throws {
    let huge = try #require(
        FixtureContent.make(.hugeNote, now: Date(timeIntervalSinceReferenceDate: 800_000_000)).notes.first {
            $0.title == "Huge"
        })
    let blocks = FenceScanner.codeBlocks(in: huge.body)
    #expect(blocks.count == 100)
    let text = NSString(string: huge.body)
    for block in blocks {
        let lines = text.substring(with: block).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 50 && lines.first == "```swift" && lines.last == "```")
    }
}
