import Foundation
import Testing

@testable import ScratchCore

// Plan 5, Task 1 (spec §6.4): an attachment is one line of plain text, `[[attachment:<lowercase UUID>]]`, and nothing
// else is on the line. The stored note stays plain text, as it does for every other marker.

private let first = AttachmentID(rawValue: "6f9619ff-8b86-4d11-b42d-00c04fc964ff")
private let second = AttachmentID(rawValue: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d")

private func token(_ id: AttachmentID) -> String { "[[attachment:\(id.rawValue)]]" }

@Test func tokenRoundTrips() {
    let line = AttachmentToken.line(for: first)
    #expect(line == "[[attachment:6f9619ff-8b86-4d11-b42d-00c04fc964ff]]")
    #expect(AttachmentToken.id(inLine: line) == first)
    #expect(AttachmentToken.id(inLine: Substring(line)) == first)
    let made = AttachmentID.make()
    #expect(AttachmentToken.id(inLine: AttachmentToken.line(for: made)) == made)
}

@Test func tokenMustBeTheWholeLine() {
    let line = token(first)
    #expect(AttachmentToken.id(inLine: " " + line) == nil)
    #expect(AttachmentToken.id(inLine: line + " ") == nil)
    #expect(AttachmentToken.id(inLine: "\t" + line) == nil)
    #expect(AttachmentToken.id(inLine: line + "\r") == nil)
    #expect(AttachmentToken.id(inLine: "see " + line) == nil)
    #expect(AttachmentToken.id(inLine: line + " done") == nil)
    #expect(AttachmentToken.id(inLine: line + line) == nil)
    #expect(AttachmentToken.id(inLine: "") == nil)
    #expect(AttachmentToken.id(inLine: "- " + line) == nil)
}

@Test func uppercaseIDIsNotAToken() {
    #expect(AttachmentToken.id(inLine: "[[attachment:6F9619FF-8B86-4D11-B42D-00C04FC964FF]]") == nil)
    #expect(AttachmentToken.id(inLine: "[[attachment:6f9619ff-8b86-4d11-b42d-00c04fc964fF]]") == nil)
}

@Test func onlyAUUIDIsAnID() {
    #expect(AttachmentToken.id(inLine: "[[attachment:]]") == nil)
    #expect(AttachmentToken.id(inLine: "[[attachment:abc]]") == nil)
    // No dashes, wrong dash positions, a character that is not hexadecimal, one character too many or too few.
    #expect(AttachmentToken.id(inLine: "[[attachment:6f9619ff8b864d11b42d00c04fc964ff]]") == nil)
    #expect(AttachmentToken.id(inLine: "[[attachment:6f9619ff-8b86-4d11-b42d00c0-4fc964ff]]") == nil)
    #expect(AttachmentToken.id(inLine: "[[attachment:6f9619fg-8b86-4d11-b42d-00c04fc964ff]]") == nil)
    #expect(AttachmentToken.id(inLine: "[[attachment:6f9619ff-8b86-4d11-b42d-00c04fc964ff0]]") == nil)
    #expect(AttachmentToken.id(inLine: "[[attachment:6f9619ff-8b86-4d11-b42d-00c04fc964f]]") == nil)
    // A character outside ASCII whose UTF-8 has the right length is no digit either.
    #expect(AttachmentToken.id(inLine: "[[attachment:6f9619ff-8b86-4d11-b42d-00c04fc9é4f]]") == nil)
}

@Test func theMarkerItselfMustBeExact() {
    let id = first.rawValue
    #expect(AttachmentToken.id(inLine: "[attachment:\(id)]") == nil)
    #expect(AttachmentToken.id(inLine: "[[attachment:\(id)]") == nil)
    #expect(AttachmentToken.id(inLine: "[[Attachment:\(id)]]") == nil)
    #expect(AttachmentToken.id(inLine: "[[attachments:\(id)]]") == nil)
    #expect(AttachmentToken.id(inLine: "[[attachment \(id)]]") == nil)
    #expect(AttachmentToken.id(inLine: "((attachment:\(id)))") == nil)
}

// MARK: ids(in:)

@Test func idsInText() {
    let text = "intro\n\(token(first))\nmiddle\n\(token(second))\n\(token(first))\nend"
    #expect(AttachmentToken.ids(in: text) == [first, second, first])
}

@Test func idsInTextKeepsDuplicatesAndOrder() {
    let text = [token(second), token(second), token(first), token(second)].joined(separator: "\n")
    #expect(AttachmentToken.ids(in: text) == [second, second, first, second])
}

@Test func idsInTextHandlesEveryLineEnding() {
    #expect(AttachmentToken.ids(in: "a\r\n\(token(first))\r\nb\r\n\(token(second))") == [first, second])
    #expect(AttachmentToken.ids(in: "a\r\(token(first))\rb\r\(token(second))\r") == [first, second])
    #expect(AttachmentToken.ids(in: token(first)) == [first])
    #expect(AttachmentToken.ids(in: token(first) + "\n") == [first])
    #expect(AttachmentToken.ids(in: "\n\n" + token(first)) == [first])
}

@Test func idsInTextIgnoresALineThatHoldsMore() {
    let text = "see \(token(first))\n\(token(second)) done\n \(token(first))\n\(token(first)) \n[x] \(token(second))"
    #expect(AttachmentToken.ids(in: text).isEmpty)
    #expect(AttachmentToken.ids(in: "").isEmpty)
    #expect(AttachmentToken.ids(in: "no tokens here\njust text").isEmpty)
}

/// A token in a fenced block is still a reference. Counting it only ever keeps a file, which is the safe side.
@Test func idsInTextCountsATokenInsideAFence() {
    let text = "```\n\(token(first))\n```"
    #expect(AttachmentToken.ids(in: text) == [first])
}

@Test func idsInTextOfALargeNoteWithoutTokens() {
    let text = String(repeating: "a line of ordinary text, 50 characters long......\n", count: 20_000)
    #expect(AttachmentToken.ids(in: text).isEmpty)
    #expect(AttachmentToken.ids(in: text + token(second)) == [second])
}

// MARK: referencedIDs(in:)

/// What keeps a stored file is a body that holds the token's text anywhere, not only a line that is a token: the wider
/// reading can only ever keep a file (Plan 5, "Never lose an attachment").
@Test func referencedIDsCountsATokenWhereverItIs() {
    let text = "see \(token(first))\n\(token(second)) done\n \(token(first))\n[x] \(token(second))\nplain"
    #expect(AttachmentToken.referencedIDs(in: text) == [first, second])
    #expect(AttachmentToken.referencedIDs(in: token(first)) == [first])
    #expect(AttachmentToken.referencedIDs(in: "a\n\(token(second))\n\(token(second))") == [second])
}

@Test func referencedIDsIncludesEveryWholeLineToken() {
    let text = "intro\n\(token(first))\nmiddle\n\(token(second))\n```\n\(token(first))\n```"
    #expect(AttachmentToken.referencedIDs(in: text) == Set(AttachmentToken.ids(in: text)))
}

@Test func referencedIDsIgnoresWhatIsNotAToken() {
    let id = first.rawValue
    #expect(AttachmentToken.referencedIDs(in: "").isEmpty)
    #expect(AttachmentToken.referencedIDs(in: "no tokens here").isEmpty)
    #expect(AttachmentToken.referencedIDs(in: "[[attachment:\(id.uppercased())]]").isEmpty)
    #expect(AttachmentToken.referencedIDs(in: "[[attachment:\(id)]").isEmpty)
    #expect(AttachmentToken.referencedIDs(in: "[attachment:\(id)]]").isEmpty)
    #expect(AttachmentToken.referencedIDs(in: "[[attachment:\(id.dropLast())]]").isEmpty)
    #expect(AttachmentToken.referencedIDs(in: "[[attachment:").isEmpty)
    #expect(AttachmentToken.referencedIDs(in: "[[attachment:\(id)").isEmpty)
}

@Test func referencedIDsFindsATokenNextToBracketsAndMultibyteText() {
    #expect(AttachmentToken.referencedIDs(in: "[[[attachment:\(first.rawValue)]]]") == [first])
    #expect(AttachmentToken.referencedIDs(in: "é日本 \(token(second)) 🙂") == [second])
    #expect(AttachmentToken.referencedIDs(in: "[[attachment:[[attachment:\(first.rawValue)]]") == [first])
    #expect(AttachmentToken.referencedIDs(in: token(first) + token(second)) == [first, second])
}

@Test func referencedIDsOfALargeNote() {
    let text = String(repeating: "a line of ordinary text, 50 characters long......\n", count: 20_000)
    #expect(AttachmentToken.referencedIDs(in: text).isEmpty)
    #expect(AttachmentToken.referencedIDs(in: text + "x" + token(second) + "y") == [second])
}

// MARK: lineRanges(in:within:)

private func ranges(_ text: String, within range: NSRange? = nil) -> [NSRange] {
    let string = NSString(string: text)
    let all = NSRange(location: 0, length: string.length)
    return AttachmentToken.lineRanges(in: string, within: range ?? all).map { $0.0 }
}

private func tokenLength() -> Int { token(first).utf16.count }

@Test func lineRangesAreUTF16WithoutTheLineBreak() {
    // The emoji is two UTF-16 units and four UTF-8 bytes, so a byte count would put the ranges in the wrong place.
    let text = "😀 hi\n\(token(first))\nx\n\(token(second))"
    let string = NSString(string: text)
    let found = AttachmentToken.lineRanges(in: string, within: NSRange(location: 0, length: string.length))
    let length = tokenLength()
    #expect(
        found.map { $0.0 } == [
            NSRange(location: 6, length: length), NSRange(location: 6 + length + 1 + 2, length: length),
        ])
    #expect(found.map { $0.1 } == [first, second])
    for (range, _) in found {
        #expect(string.substring(with: range).hasPrefix("[[attachment:"))
        #expect(string.substring(with: range).hasSuffix("]]"))
    }
}

@Test func lineRangesWorkWithCRLFAndCR() {
    let length = tokenLength()
    #expect(ranges("a\r\n\(token(first))\r\nb") == [NSRange(location: 3, length: length)])
    #expect(ranges("a\r\(token(first))\rb") == [NSRange(location: 2, length: length)])
}

@Test func lineRangesKeepEachRepeatedToken() {
    let text = "\(token(first))\n\(token(first))"
    let string = NSString(string: text)
    let found = AttachmentToken.lineRanges(in: string, within: NSRange(location: 0, length: string.length))
    #expect(found.map { $0.1 } == [first, first])
    #expect(found.map { $0.0.location } == [0, tokenLength() + 1])
}

@Test func lineRangesSkipLinesThatHoldMore() {
    #expect(ranges(" \(token(first))\n\(token(first)) \nx \(token(second))").isEmpty)
    #expect(ranges("").isEmpty)
}

@Test func lineRangesReturnOnlyTheLinesOfTheRange() {
    let length = tokenLength()
    let text = "\(token(first))\nmiddle\n\(token(second))"
    let secondStart = length + 1 + 6 + 1
    // The range names the middle line only.
    #expect(ranges(text, within: NSRange(location: length + 1, length: 6)).isEmpty)
    // Part of the first token is enough, and so is part of the second.
    #expect(ranges(text, within: NSRange(location: 3, length: 4)) == [NSRange(location: 0, length: length)])
    #expect(
        ranges(text, within: NSRange(location: secondStart + 5, length: 3))
            == [NSRange(location: secondStart, length: length)])
    // A range across everything finds both.
    #expect(ranges(text, within: NSRange(location: 5, length: text.utf16.count - 5)).count == 2)
}

@Test func lineRangesNeedARealOverlapForARange() {
    let length = tokenLength()
    let text = "above\n\(token(first))\nbelow"
    let start = 6
    let end = start + length
    // Ending where the token begins, or beginning where it ends, covers none of it: only line breaks.
    #expect(ranges(text, within: NSRange(location: 0, length: start)).isEmpty)
    #expect(ranges(text, within: NSRange(location: end, length: 3)).isEmpty)
    // One character on the inside is a cover.
    #expect(ranges(text, within: NSRange(location: 0, length: start + 1)) == [NSRange(location: start, length: length)])
    #expect(ranges(text, within: NSRange(location: end - 1, length: 2)) == [NSRange(location: start, length: length)])
}

@Test func lineRangesOfACaretAreTheLineItIsOn() {
    let length = tokenLength()
    let text = "above\n\(token(first))\nbelow"
    let start = 6
    let end = start + length
    let line = [NSRange(location: start, length: length)]
    // Inside the token, and at both of its edges (before the first character and after the last).
    #expect(ranges(text, within: NSRange(location: start + 4, length: 0)) == line)
    #expect(ranges(text, within: NSRange(location: start, length: 0)) == line)
    #expect(ranges(text, within: NSRange(location: end, length: 0)) == line)
    // On the neighbouring lines, including the end of the line above, which is before the line break.
    #expect(ranges(text, within: NSRange(location: 5, length: 0)).isEmpty)
    #expect(ranges(text, within: NSRange(location: end + 1, length: 0)).isEmpty)
    #expect(ranges(text, within: NSRange(location: 0, length: 0)).isEmpty)
    #expect(ranges(text, within: NSRange(location: text.utf16.count, length: 0)).isEmpty)
}

@Test func lineRangesOfACaretInATokenAtTheEdgesOfTheNote() {
    let length = tokenLength()
    let only = token(first)
    #expect(ranges(only, within: NSRange(location: 0, length: 0)) == [NSRange(location: 0, length: length)])
    #expect(ranges(only, within: NSRange(location: length, length: 0)) == [NSRange(location: 0, length: length)])
}

@Test func lineRangesClampARangeThatIsTooLong() {
    let length = tokenLength()
    let text = "a\n\(token(first))"
    #expect(ranges(text, within: NSRange(location: 0, length: 10_000)) == [NSRange(location: 2, length: length)])
    #expect(ranges(text, within: NSRange(location: 10_000, length: 0)).isEmpty)
    #expect(ranges(text, within: NSRange(location: 10_000, length: 5)).isEmpty)
    #expect(ranges(text, within: NSRange(location: NSNotFound, length: 0)).isEmpty)
}

@Test func lineRangesOfALargeNoteAreFoundFromTheirRange() {
    let line = "a line of ordinary text\n"
    let text = String(repeating: line, count: 5_000) + token(second) + "\n" + String(repeating: line, count: 5_000)
    let tokenStart = 5_000 * line.utf16.count
    #expect(
        ranges(text, within: NSRange(location: tokenStart + 10, length: 0))
            == [NSRange(location: tokenStart, length: tokenLength())])
    #expect(ranges(text, within: NSRange(location: 0, length: tokenStart)).isEmpty)
    #expect(ranges(text).count == 1)
}
