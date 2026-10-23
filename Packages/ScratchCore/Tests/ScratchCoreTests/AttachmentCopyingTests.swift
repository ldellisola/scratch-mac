import Foundation
import Testing

@testable import ScratchCore

// Plan 5, Task 6 (spec §6.5), docs/features/attachments.md ("Copying"): Copy and Cut put plain text on the pasteboard in
// which each token line is the name of its file, and a selection that is exactly one token line is the one that also puts
// the file itself there.

private let idA = AttachmentID(rawValue: "6f9619ff-8b86-4d11-b42d-00c04fc964ff")
private let idB = AttachmentID(rawValue: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d")
private let tokenA = AttachmentToken.line(for: idA)
private let tokenB = AttachmentToken.line(for: idB)
private let size = AttachmentToken.lineLength

/// The names of the two attachments of these tests, and what an id with no row is called.
private func name(of id: AttachmentID) -> String {
    switch id {
    case idA: return "rollback-plan.txt"
    case idB: return "Image 2026-10-22 at 10.42.13.png"
    default: return "Missing attachment"
    }
}

private func copied(_ text: String, _ range: NSRange? = nil, literal: (NSRange) -> Bool = { _ in false }) -> String {
    let whole = NSRange(location: 0, length: text.utf16.count)
    return AttachmentCopying.text(of: range ?? whole, in: text as NSString, name: name(of:), ignoring: literal)
}

// MARK: The text that is copied

@Test func aTokenLineIsCopiedAsTheNameOfItsFile() {
    #expect(copied(tokenA) == "rollback-plan.txt")
    #expect(copied("abc\n" + tokenA + "\ndef") == "abc\nrollback-plan.txt\ndef", "the line breaks are the text's")
}

@Test func everyTokenOfTheSelectionIsItsName() {
    let text = "first\n" + tokenA + "\n" + tokenB + "\nlast"
    #expect(copied(text) == "first\nrollback-plan.txt\nImage 2026-10-22 at 10.42.13.png\nlast")
}

@Test func anIdWithNoRowIsCopiedAsMissingAttachment() {
    let unknown = AttachmentToken.line(for: AttachmentID(rawValue: "11111111-2222-4333-8444-555555555555"))
    #expect(copied("x\n" + unknown) == "x\nMissing attachment")
}

@Test func textWithoutATokenIsCopiedExactlyAsItIsStored() {
    let text = "- [ ] one **bold** `code`\n```swift\nlet a = 1\n```\r\nend"
    #expect(copied(text) == text)
    #expect(copied("") == "")
}

@Test func onlyTheSelectedPartOfTheTextIsCopied() {
    let text = "abc\n" + tokenA + "\ndef"
    #expect(copied(text, NSRange(location: 1, length: 2)) == "bc")
    #expect(
        copied(text, NSRange(location: 2, length: 4 + size - 2)) == "c\nrollback-plan.txt", "ending at the token's end")
    #expect(copied(text, NSRange(location: 4, length: size + 1)) == "rollback-plan.txt\n", "starting at the token")
    #expect(copied(text, NSRange(location: 4, length: size)) == "rollback-plan.txt", "exactly the token")
}

@Test func aSelectionThatCutsATokenCopiesTheWholeNameAndNoPieceOfTheToken() {
    // The editor never makes such a selection (it grows to the whole token), but the rule must not copy half a token.
    let text = "abc\n" + tokenA + "\ndef"
    #expect(copied(text, NSRange(location: 10, length: 5)) == "rollback-plan.txt")
    #expect(copied(text, NSRange(location: 0, length: 12)) == "abc\nrollback-plan.txt")
    #expect(copied(text, NSRange(location: 30, length: 4 + size + 2 - 30)) == "rollback-plan.txt\nd")
}

@Test func lineBreaksOfEveryKindSurviveAndTokensBetweenThemAreNames() {
    let text = "a\r\n" + tokenA + "\r\nb\r" + tokenB + "\rc"
    #expect(copied(text) == "a\r\nrollback-plan.txt\r\nb\rImage 2026-10-22 at 10.42.13.png\rc")
}

@Test func aTokenThatIsTextBecauseItIsInACodeBlockIsCopiedAsStored() {
    let text = "```\n" + tokenA + "\n```\n" + tokenB
    let block = NSRange(location: 0, length: 4 + size + 4)
    let result = copied(text, literal: { NSIntersectionRange($0, block).length > 0 })
    #expect(result == "```\n" + tokenA + "\n```\nImage 2026-10-22 at 10.42.13.png")
}

@Test func aLineThatHoldsMoreThanTheTokenIsText() {
    let text = "see " + tokenA + "\n " + tokenB
    #expect(copied(text) == text)
}

@Test func aRangeThatReachesPastTheTextIsCutToTheText() {
    let text = "abc\n" + tokenA
    #expect(copied(text, NSRange(location: 2, length: 1_000)) == "c\nrollback-plan.txt")
    #expect(copied(text, NSRange(location: 1_000, length: 5)) == "")
    #expect(copied(text, NSRange(location: NSNotFound, length: 0)) == "")
    #expect(copied(text, NSRange(location: 4, length: 0)) == "", "a caret copies nothing")
}

// MARK: The one attachment that is copied whole

@Test func aSelectionThatIsExactlyOneTokenIsThatAttachment() {
    let text = "abc\n" + tokenA + "\ndef"
    let found = AttachmentCopying.soleAttachment(
        in: NSRange(location: 4, length: size), of: text as NSString)
    #expect(found == idA)
    #expect(
        AttachmentCopying.soleAttachment(in: NSRange(location: 0, length: size), of: tokenB as NSString) == idB,
        "the only line of the text")
}

@Test func aSelectionThatIsMoreOrLessThanOneTokenLineIsNoAttachment() {
    let text = "abc\n" + tokenA + "\n" + tokenB + "\ndef"
    let start = 4
    let notExact: [NSRange] = [
        NSRange(location: start, length: size + 1),  // the line break with it
        NSRange(location: start - 1, length: size + 1),  // and the one before it
        NSRange(location: start, length: size - 1),  // a piece of it
        NSRange(location: start + 1, length: size),  // shifted, which is not a token line
        NSRange(location: start, length: 2 * size + 1),  // two tokens
        NSRange(location: 0, length: text.utf16.count),  // everything
        NSRange(location: start, length: 0),  // a caret
    ]
    for range in notExact {
        #expect(AttachmentCopying.soleAttachment(in: range, of: text as NSString) == nil, "\(range)")
    }
}

@Test func aTokenThatIsTextIsNoAttachment() {
    let text = "```\n" + tokenA + "\n```"
    let range = NSRange(location: 4, length: size)
    #expect(AttachmentCopying.soleAttachment(in: range, of: text as NSString) == idA)
    #expect(AttachmentCopying.soleAttachment(in: range, of: text as NSString, ignoring: { _ in true }) == nil)
    #expect(
        AttachmentCopying.soleAttachment(
            in: NSRange(location: 0, length: size), of: ("see " + tokenA) as NSString) == nil, "a longer line")
}

@Test func aSelectionOutsideTheTextIsNoAttachment() {
    #expect(
        AttachmentCopying.soleAttachment(in: NSRange(location: 1, length: size), of: tokenA as NSString) == nil)
    #expect(
        AttachmentCopying.soleAttachment(in: NSRange(location: NSNotFound, length: size), of: tokenA as NSString)
            == nil)
    #expect(AttachmentCopying.soleAttachment(in: NSRange(location: -1, length: size), of: tokenA as NSString) == nil)
}

// MARK: Whether a selection holds an attachment (plan 6, Task 6)
//
// Copy and Cut also write the selection exactly as stored, on a private type, when it holds a token line, so that a paste or a
// drop into Scratch keeps the attachment (docs/features/attachments.md, "Copying").

private func holds(_ text: String, _ range: NSRange? = nil, literal: (NSRange) -> Bool = { _ in false }) -> Bool {
    let whole = NSRange(location: 0, length: text.utf16.count)
    return AttachmentCopying.holdsAttachment(in: range ?? whole, of: text as NSString, ignoring: literal)
}

@Test func aSelectionThatHoldsATokenLineHoldsAnAttachment() {
    let text = "abc\n" + tokenA + "\ndef"
    #expect(holds(text))
    #expect(holds(text, NSRange(location: 4, length: size)), "exactly the token")
    #expect(holds(text, NSRange(location: 2, length: 4 + size - 2)), "ending at the token's end")
    #expect(holds(text, NSRange(location: 4, length: size + 4)), "starting at the token")
    #expect(holds(tokenA + "\n" + tokenB))
}

@Test func aSelectionAwayFromEveryTokenLineHoldsNoAttachment() {
    let text = "abc\n" + tokenA + "\ndef"
    #expect(!holds(text, NSRange(location: 0, length: 3)))
    #expect(!holds(text, NSRange(location: 0, length: 4)), "up to the start of the token line, its line break included")
    #expect(!holds(text, NSRange(location: 4 + size, length: 4)), "from the end of the token line")
    #expect(!holds(text, NSRange(location: 4 + size + 1, length: 3)))
    #expect(!holds("just text, - [ ] a **box**\n`code`"))
    #expect(!holds(""))
    #expect(!holds(text, NSRange(location: 5, length: 0)), "an empty selection holds nothing")
}

@Test func aLineThatHoldsMoreThanTheTokenIsNoAttachment() {
    #expect(!holds("see " + tokenA))
    #expect(!holds(tokenA + " "))
}

@Test func aTokenInACodeBlockIsTextAndSoNoAttachment() {
    let text = "```\n" + tokenA + "\n```"
    #expect(!holds(text, literal: { _ in true }))
    #expect(holds(text, literal: { _ in false }))
    #expect(holds("x\n" + tokenA + "\n" + tokenB, literal: { $0.location == 2 }), "the second one is not in the block")
}

@Test func aSelectionPastTheEndOfTheTextIsCutToIt() {
    let text = "abc\n" + tokenA
    #expect(holds(text, NSRange(location: 2, length: 1000)))
    #expect(!holds(text, NSRange(location: 1000, length: 5)))
    #expect(!holds(text, NSRange(location: NSNotFound, length: 0)))
}

@Test func aHugeSelectionWithNoTokenIsLookedAtQuickly() {
    let text = String(repeating: "abcdefghij\n", count: 500_000)
    let start = Date()
    #expect(!holds(text))
    #expect(Date().timeIntervalSince(start) < 1)
}
