import Foundation
import Testing

@testable import ScratchCore

// Plan 5, Task 5 (spec §6.4), docs/features/attachments.md ("Selecting and deleting a token", "Pasting and dropping"): the
// caret never stops inside a token, a selection that covers part of a token covers all of it, Backspace and Delete next to
// a token select it first and the next press deletes it, and an attachment that is pasted is a line of its own.

private let idA = AttachmentID(rawValue: "6f9619ff-8b86-4d11-b42d-00c04fc964ff")
private let idB = AttachmentID(rawValue: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d")
private let tokenA = AttachmentToken.line(for: idA)
private let tokenB = AttachmentToken.line(for: idB)
private let size = AttachmentToken.lineLength

private func nsString(_ text: String) -> NSString { text as NSString }

/// The range of `needle` in `text`, in UTF-16 units.
private func range(of needle: String, in text: String) -> NSRange {
    (text as NSString).range(of: needle)
}

private func caret(_ location: Int) -> NSRange { NSRange(location: location, length: 0) }

/// The text after `edit`.
private func apply(_ edit: TextEdit, to text: String) -> String {
    (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
}

// MARK: Finding a token

@Test func aTokenIsFoundFromInsideAndFromBothEnds() {
    let text = "abc\n" + tokenA + "\ndef"
    let start = 4
    for location in [start, start + 1, start + 25, start + size - 1, start + size] {
        let found = AttachmentEditing.token(touching: location, in: nsString(text))
        #expect(found?.range == NSRange(location: start, length: size), "from \(location)")
        #expect(found?.id == idA)
    }
}

@Test func aPositionOutsideTheTokenLineFindsNothing() {
    let text = "abc\n" + tokenA + "\ndef"
    #expect(AttachmentEditing.token(touching: 0, in: nsString(text)) == nil)
    #expect(AttachmentEditing.token(touching: 3, in: nsString(text)) == nil, "the end of the line above")
    #expect(AttachmentEditing.token(touching: 4 + size + 1, in: nsString(text)) == nil, "the start of the line below")
    #expect(AttachmentEditing.token(touching: text.utf16.count, in: nsString(text)) == nil)
    #expect(AttachmentEditing.token(touching: -1, in: nsString(text)) == nil)
    #expect(AttachmentEditing.token(touching: text.utf16.count + 1, in: nsString(text)) == nil)
}

@Test func aLineThatHoldsMoreThanTheTokenIsNotOne() {
    for text in [" " + tokenA, tokenA + " ", "see " + tokenA, tokenA + tokenA, "x" + tokenA + "\n"] {
        for location in 0...text.utf16.count {
            #expect(AttachmentEditing.token(touching: location, in: nsString(text)) == nil, "\(text) at \(location)")
        }
    }
}

@Test func aTokenIsFoundInTheFirstAndTheLastLineAndWithEveryKindOfLineBreak() {
    #expect(AttachmentEditing.token(touching: 10, in: nsString(tokenA))?.range == NSRange(location: 0, length: size))
    let last = "x\n" + tokenA
    #expect(
        AttachmentEditing.token(touching: 2 + size, in: nsString(last))?.range == NSRange(location: 2, length: size))
    let crlf = "x\r\n" + tokenA + "\r\ny"
    #expect(AttachmentEditing.token(touching: 3 + 5, in: nsString(crlf))?.range == NSRange(location: 3, length: size))
    let cr = "x\r" + tokenA + "\ry"
    #expect(AttachmentEditing.token(touching: 2 + 5, in: nsString(cr))?.range == NSRange(location: 2, length: size))
}

@Test func aVeryLongLineIsNotScannedThroughTheLongWay() {
    // 200,000 characters on a line: the answer is nil, and it must not take a scan of the whole line to say so.
    let text = String(repeating: "a", count: 200_000)
    let start = Date()
    for location in stride(from: 0, through: 200_000, by: 20_000) {
        #expect(AttachmentEditing.token(touching: location, in: nsString(text)) == nil)
    }
    #expect(Date().timeIntervalSince(start) < 1)
}

// MARK: Snapping a selection

@Test func aCaretInsideATokenStepsOverItInTheDirectionOfTheMove() {
    let text = "abc\n" + tokenA + "\ndef"
    let token = NSRange(location: 4, length: size)
    // Moving on, from the start of the token to the next character: to the end.
    #expect(
        AttachmentEditing.snappedSelection(from: caret(4), to: caret(5), in: nsString(text)) == caret(NSMaxRange(token))
    )
    // Moving back, from the end of the token to the character before: to the start.
    #expect(
        AttachmentEditing.snappedSelection(
            from: caret(NSMaxRange(token)), to: caret(NSMaxRange(token) - 1), in: nsString(text))
            == caret(4))
    // From further on, and further back.
    #expect(
        AttachmentEditing.snappedSelection(from: caret(text.utf16.count), to: caret(20), in: nsString(text)) == caret(4)
    )
    #expect(
        AttachmentEditing.snappedSelection(from: caret(0), to: caret(20), in: nsString(text))
            == caret(NSMaxRange(token)))
}

@Test func aClickInsideATokenGoesToItsEnd() {
    let text = "abc\n" + tokenA + "\ndef"
    let end = 4 + size
    #expect(
        AttachmentEditing.snappedSelection(
            from: caret(text.utf16.count), to: caret(20), in: nsString(text), isClick: true) == caret(end))
}

@Test func aCaretAtTheEdgesOfATokenIsLeftAlone() {
    let text = "abc\n" + tokenA + "\ndef"
    for location in [0, 3, 4, 4 + size, 4 + size + 1, text.utf16.count] {
        #expect(
            AttachmentEditing.snappedSelection(from: caret(0), to: caret(location), in: nsString(text))
                == caret(location))
    }
}

@Test func aRangeThatCoversPartOfATokenGrowsToCoverAllOfIt() {
    let text = "abc\n" + tokenA + "\ndef"
    let token = NSRange(location: 4, length: size)
    func snapped(_ range: NSRange) -> NSRange {
        AttachmentEditing.snappedSelection(from: caret(0), to: range, in: nsString(text))
    }
    // The end is inside: it grows to the token's end.
    #expect(snapped(NSRange(location: 1, length: 10)) == NSRange(location: 1, length: NSMaxRange(token) - 1))
    // The start is inside: it grows back to the token's start.
    #expect(snapped(NSRange(location: 20, length: 38)) == NSRange(location: 4, length: 54))
    // Both ends inside: the token.
    #expect(snapped(NSRange(location: 10, length: 5)) == token)
    // One character of it, at the start.
    #expect(snapped(NSRange(location: 4, length: 1)) == token)
    // Whole, or not touching: as it is.
    #expect(snapped(token) == token)
    #expect(snapped(NSRange(location: 0, length: 3)) == NSRange(location: 0, length: 3))
    #expect(snapped(NSRange(location: 0, length: text.utf16.count)) == NSRange(location: 0, length: text.utf16.count))
}

@Test func aSelectionIsGrownOverTwoTokensAtOnce() {
    let text = tokenA + "\n" + tokenB
    let snapped = AttachmentEditing.snappedSelection(
        from: caret(0), to: NSRange(location: 10, length: size + 1), in: nsString(text))
    #expect(snapped == NSRange(location: 0, length: text.utf16.count))
}

// A selection that is moved with ⇧ and an arrow key keeps one end (the anchor) and moves the other. When the moving end
// goes back over a token that the selection covers, the token leaves the selection whole: the end must not be pulled to the
// token's far side again, or the selection could never be made smaller.

@Test func aSelectionThatEndsAtATokenCanBeShrunkBackOverIt() {
    let text = "abc\n" + tokenA + "\ndef"
    let end = 4 + size
    let covering = NSRange(location: 3, length: end - 3)
    // One unit back puts the end inside the token: the token goes, and the selection ends where it starts.
    #expect(
        AttachmentEditing.snappedSelection(
            from: covering, to: NSRange(location: 3, length: end - 3 - 1), in: nsString(text))
            == NSRange(location: 3, length: 1))
    // A word back, or a line back, is further inside it: the same.
    #expect(
        AttachmentEditing.snappedSelection(from: covering, to: NSRange(location: 3, length: 20), in: nsString(text))
            == NSRange(location: 3, length: 1))
    // The token alone, shrunk from its end, leaves a caret at its start.
    #expect(
        AttachmentEditing.snappedSelection(
            from: NSRange(location: 4, length: size), to: NSRange(location: 4, length: size - 1), in: nsString(text))
            == caret(4))
}

@Test func aSelectionThatStartsAtATokenCanBeShrunkBackOverIt() {
    let text = "abc\n" + tokenA + "\ndef"
    let end = 4 + size
    // The anchor is after the token (at 57) and the start is at the token's start: one unit forward is inside the token.
    let covering = NSRange(location: 4, length: 57 - 4)
    #expect(
        AttachmentEditing.snappedSelection(
            from: covering, to: NSRange(location: 5, length: 57 - 5), in: nsString(text))
            == NSRange(location: end, length: 57 - end))
    // The token alone, shrunk from its start, leaves a caret at its end.
    #expect(
        AttachmentEditing.snappedSelection(
            from: NSRange(location: 4, length: size), to: NSRange(location: 5, length: size - 1), in: nsString(text))
            == caret(end))
}

@Test func extendingOverATokenAndShrinkingBackOneUnitAtATime() {
    let text = "abc\n" + tokenA + "\ndef"
    func snapped(_ old: NSRange, _ new: NSRange) -> NSRange {
        AttachmentEditing.snappedSelection(from: old, to: new, in: nsString(text))
    }

    // ⇧→ from the end of "abc": the line break, then the token as one step, then on.
    var selection = caret(3)
    var grown: [Int] = []
    for _ in 0..<4 {
        selection = snapped(selection, NSRange(location: 3, length: selection.length + 1))
        grown.append(selection.length)
    }
    #expect(grown == [1, size + 1, size + 2, size + 3])

    // ⇧← all the way back: the token goes in one step and the caret is back where it began.
    var shrunk: [Int] = []
    for _ in 0..<(size + 5) where selection.length > 0 {
        selection = snapped(selection, NSRange(location: 3, length: selection.length - 1))
        shrunk.append(selection.length)
    }
    #expect(shrunk == [size + 2, size + 1, 1, 0])
}

@Test func extendingBackwardOverATokenAndShrinkingBackOneUnitAtATime() {
    let text = "abc\n" + tokenA + "\ndef"
    let anchor = 4 + size + 2  // the "e" of "def"
    func snapped(_ old: NSRange, _ new: NSRange) -> NSRange {
        AttachmentEditing.snappedSelection(from: old, to: new, in: nsString(text))
    }

    // ⇧← from the "e": the "d", the line break, then the token as one step, then on.
    var selection = caret(anchor)
    var starts: [Int] = []
    for _ in 0..<4 {
        selection = snapped(selection, NSRange(location: selection.location - 1, length: selection.length + 1))
        starts.append(selection.location)
    }
    #expect(starts == [anchor - 1, anchor - 2, 4, 3])

    // ⇧→ all the way back: the token goes in one step and the caret is back at the anchor.
    var shrunk: [Int] = []
    for _ in 0..<(size + 5) where selection.length > 0 {
        selection = snapped(selection, NSRange(location: selection.location + 1, length: selection.length - 1))
        shrunk.append(selection.location)
    }
    #expect(shrunk == [4, 4 + size, anchor - 1, anchor])
}

@Test func aSelectionThatIsMovedAsAWholeIsNotShrunk() {
    // Both ends changed: it is a new selection and not an end moving back, so a part of a token is the whole of it.
    let text = "abc\n" + tokenA + "\ndef"
    #expect(
        AttachmentEditing.snappedSelection(
            from: NSRange(location: 4, length: size), to: NSRange(location: 1, length: 12), in: nsString(text))
            == NSRange(location: 1, length: 4 + size - 1))
    #expect(
        AttachmentEditing.snappedSelection(
            from: NSRange(location: 1, length: 4 + size - 1), to: NSRange(location: 30, length: 27),
            in: nsString(text)) == NSRange(location: 4, length: 53))
    // And so is a selection that does not know where it came from.
    let unknown = NSRange(location: NSNotFound, length: 0)
    #expect(
        AttachmentEditing.snappedSelection(from: unknown, to: NSRange(location: 3, length: 51), in: nsString(text))
            == NSRange(location: 3, length: size + 1))
}

@Test func aTokenThatIsLiteralIsNotSnappedWhenTheSelectionShrinks() {
    let text = "```\n" + tokenA + "\n```"
    let shrunk = NSRange(location: 3, length: 20)
    #expect(
        AttachmentEditing.snappedSelection(
            from: NSRange(location: 3, length: 21), to: shrunk, in: nsString(text), ignoring: { _ in true }) == shrunk)
}

@Test func aTokenThatIsLiteralIsNotSnapped() {
    let text = "```\n" + tokenA + "\n```"
    let inside = NSRange(location: 10, length: 0)
    #expect(
        AttachmentEditing.snappedSelection(from: caret(0), to: inside, in: nsString(text), ignoring: { _ in true })
            == inside)
    let range = NSRange(location: 10, length: 5)
    #expect(
        AttachmentEditing.snappedSelection(from: caret(0), to: range, in: nsString(text), ignoring: { _ in true })
            == range)
}

@Test func aSelectionOutsideTheTextIsReturnedAsItIs() {
    let text = tokenA
    let outside = NSRange(location: 10, length: 500)
    #expect(AttachmentEditing.snappedSelection(from: caret(0), to: outside, in: nsString(text)) == outside)
    let none = NSRange(location: NSNotFound, length: 0)
    #expect(AttachmentEditing.snappedSelection(from: caret(0), to: none, in: nsString(text)) == none)
}

// MARK: Backspace

@Test func backspaceAtTheEndOfATokenLineSelectsTheToken() {
    let text = "abc\n" + tokenA
    let token = NSRange(location: 4, length: size)
    #expect(
        AttachmentEditing.deletion(.backward, selection: caret(NSMaxRange(token)), in: nsString(text))
            == .selectToken(token))
}

@Test func backspaceAtTheStartOfTheLineAfterATokenSelectsTheToken() {
    for lineBreak in ["\n", "\r\n", "\r"] {
        let text = "abc" + lineBreak + tokenA + lineBreak + "def"
        let token = NSRange(location: 3 + lineBreak.utf16.count, length: size)
        let below = NSMaxRange(token) + lineBreak.utf16.count
        #expect(
            AttachmentEditing.deletion(.backward, selection: caret(below), in: nsString(text)) == .selectToken(token),
            "line break \(lineBreak.debugDescription)")
    }
}

@Test func backspaceOnAnEmptyLineBelowATokenSelectsTheToken() {
    let text = tokenA + "\n"
    #expect(
        AttachmentEditing.deletion(.backward, selection: caret(size + 1), in: nsString(text))
            == .selectToken(NSRange(location: 0, length: size)))
}

@Test func backspaceWithTheTokenSelectedDeletesTheTokenAndItsLineBreak() {
    let text = "abc\n" + tokenA + "\ndef"
    let token = NSRange(location: 4, length: size)
    let action = AttachmentEditing.deletion(.backward, selection: token, in: nsString(text))
    guard case .removeToken(let edit)? = action else {
        Issue.record("expected removeToken, got \(String(describing: action))")
        return
    }
    #expect(apply(edit, to: text) == "abc\ndef")
    #expect(edit.selection == caret(4))
}

@Test func backspaceInTheMiddleOfTextIsNotOurs() {
    let text = "abc\n" + tokenA + "\ndef"
    #expect(AttachmentEditing.deletion(.backward, selection: caret(2), in: nsString(text)) == nil)
    #expect(AttachmentEditing.deletion(.backward, selection: caret(text.utf16.count), in: nsString(text)) == nil)
    #expect(AttachmentEditing.deletion(.backward, selection: caret(0), in: nsString(text)) == nil)
}

@Test func backspaceWithOtherTextSelectedIsNotOurs() {
    let text = "abc\n" + tokenA + "\ndef"
    #expect(
        AttachmentEditing.deletion(.backward, selection: NSRange(location: 0, length: 3), in: nsString(text)) == nil)
    // A token and its line break is more than one token.
    #expect(
        AttachmentEditing.deletion(.backward, selection: NSRange(location: 4, length: size + 1), in: nsString(text))
            == nil)
}

@Test func backspaceAtTheStartOfATokenLineBelowTextOnlyMovesTheCaret() {
    // Deleting the line break would leave "abc" and the token on one line, and the token would be text.
    let text = "abc\n" + tokenA
    #expect(AttachmentEditing.deletion(.backward, selection: caret(4), in: nsString(text)) == .moveCaret(to: 3))
    let crlf = "abc\r\n" + tokenA
    #expect(AttachmentEditing.deletion(.backward, selection: caret(5), in: nsString(crlf)) == .moveCaret(to: 3))
}

@Test func backspaceAtTheStartOfATokenLineBelowAnEmptyLineIsTheTextViewsOwn() {
    // It removes the empty line, which leaves the token a line.
    #expect(AttachmentEditing.deletion(.backward, selection: caret(5), in: nsString("abc\n\n" + tokenA)) == nil)
    #expect(AttachmentEditing.deletion(.backward, selection: caret(1), in: nsString("\n" + tokenA)) == nil)
    #expect(AttachmentEditing.deletion(.backward, selection: caret(0), in: nsString(tokenA)) == nil)
}

@Test func backspaceBetweenTwoTokensSelectsTheOneAbove() {
    let text = tokenA + "\n" + tokenB
    #expect(
        AttachmentEditing.deletion(.backward, selection: caret(size + 1), in: nsString(text))
            == .selectToken(NSRange(location: 0, length: size)))
}

@Test func backspaceLeavesATokenInACodeBlockAlone() {
    let text = "```\n" + tokenA + "\n```"
    let end = 4 + size
    #expect(
        AttachmentEditing.deletion(.backward, selection: caret(end), in: nsString(text), ignoring: { _ in true }) == nil
    )
    #expect(
        AttachmentEditing.deletion(
            .backward, selection: NSRange(location: 4, length: size), in: nsString(text), ignoring: { _ in true })
            == nil)
}

// MARK: Delete

@Test func deleteAtTheStartOfATokenLineSelectsTheToken() {
    let text = "abc\n" + tokenA + "\ndef"
    let token = NSRange(location: 4, length: size)
    #expect(AttachmentEditing.deletion(.forward, selection: caret(4), in: nsString(text)) == .selectToken(token))
}

@Test func deleteAtTheEndOfTheLineAboveATokenSelectsTheToken() {
    for lineBreak in ["\n", "\r\n", "\r"] {
        let text = "abc" + lineBreak + tokenA
        let token = NSRange(location: 3 + lineBreak.utf16.count, length: size)
        #expect(
            AttachmentEditing.deletion(.forward, selection: caret(3), in: nsString(text)) == .selectToken(token),
            "line break \(lineBreak.debugDescription)")
    }
}

@Test func deleteWithTheTokenSelectedDeletesTheTokenAndItsLineBreak() {
    let text = "abc\n" + tokenA + "\ndef"
    let token = NSRange(location: 4, length: size)
    let action = AttachmentEditing.deletion(.forward, selection: token, in: nsString(text))
    guard case .removeToken(let edit)? = action else {
        Issue.record("expected removeToken, got \(String(describing: action))")
        return
    }
    #expect(apply(edit, to: text) == "abc\ndef")
}

@Test func deleteAtTheEndOfATokenLineAboveTextOnlyMovesTheCaret() {
    let text = tokenA + "\nabc"
    #expect(
        AttachmentEditing.deletion(.forward, selection: caret(size), in: nsString(text)) == .moveCaret(to: size + 1))
    let crlf = tokenA + "\r\nabc"
    #expect(
        AttachmentEditing.deletion(.forward, selection: caret(size), in: nsString(crlf)) == .moveCaret(to: size + 2))
}

@Test func deleteAtTheEndOfATokenLineAboveAnEmptyLineOrTheEndIsTheTextViewsOwn() {
    #expect(AttachmentEditing.deletion(.forward, selection: caret(size), in: nsString(tokenA + "\n\nabc")) == nil)
    #expect(AttachmentEditing.deletion(.forward, selection: caret(size), in: nsString(tokenA + "\n")) == nil)
    #expect(AttachmentEditing.deletion(.forward, selection: caret(size), in: nsString(tokenA)) == nil)
}

@Test func deleteBetweenTwoTokensSelectsTheOneBelow() {
    let text = tokenA + "\n" + tokenB
    #expect(
        AttachmentEditing.deletion(.forward, selection: caret(size), in: nsString(text))
            == .selectToken(NSRange(location: size + 1, length: size)))
}

@Test func deleteInTheMiddleOfTextIsNotOurs() {
    let text = "abc\n" + tokenA + "\ndef"
    #expect(AttachmentEditing.deletion(.forward, selection: caret(1), in: nsString(text)) == nil)
    #expect(AttachmentEditing.deletion(.forward, selection: caret(text.utf16.count), in: nsString(text)) == nil)
    #expect(AttachmentEditing.deletion(.forward, selection: caret(4 + size + 1), in: nsString(text)) == nil)
}

// MARK: Removing a token

@Test func removingATokenTakesTheLineBreakAfterIt() {
    let text = "abc\n" + tokenA + "\ndef"
    let edit = AttachmentEditing.removal(of: NSRange(location: 4, length: size), in: nsString(text))
    #expect(apply(edit, to: text) == "abc\ndef")
    #expect(edit.selection == caret(4))
}

@Test func removingTheLastTokenTakesTheLineBreakBeforeIt() {
    let text = "abc\n" + tokenA
    let edit = AttachmentEditing.removal(of: NSRange(location: 4, length: size), in: nsString(text))
    #expect(apply(edit, to: text) == "abc")
    #expect(edit.selection == caret(3))
}

@Test func removingTheOnlyLineLeavesNothing() {
    let edit = AttachmentEditing.removal(of: NSRange(location: 0, length: size), in: nsString(tokenA))
    #expect(apply(edit, to: tokenA) == "")
    #expect(edit.selection == caret(0))
}

@Test func removingATokenTakesAWholeCRLF() {
    let text = "abc\r\n" + tokenA + "\r\ndef"
    let edit = AttachmentEditing.removal(of: NSRange(location: 5, length: size), in: nsString(text))
    #expect(apply(edit, to: text) == "abc\r\ndef")
    let last = "abc\r\n" + tokenA
    let lastEdit = AttachmentEditing.removal(of: NSRange(location: 5, length: size), in: nsString(last))
    #expect(apply(lastEdit, to: last) == "abc")
}

@Test func removingATokenThatFollowsAnEmptyLineKeepsTheEmptyLine() {
    let text = "abc\n\n" + tokenA + "\ndef"
    let edit = AttachmentEditing.removal(of: NSRange(location: 5, length: size), in: nsString(text))
    #expect(apply(edit, to: text) == "abc\n\ndef")
}

// MARK: Inserting

@Test func anAttachmentInAnEmptyNoteIsALineWithABreakAfterIt() {
    let edit = AttachmentEditing.insertion(of: [idA], over: caret(0), in: nsString(""))
    #expect(edit.range == caret(0))
    #expect(edit.replacement == tokenA + "\n")
    #expect(edit.selection == caret(size + 1), "the caret is on the line after the token")
}

@Test func anAttachmentAtTheStartOfALineNeedsNoBreakBeforeIt() {
    let text = "abc\ndef"
    let edit = AttachmentEditing.insertion(of: [idA], over: caret(4), in: nsString(text))
    #expect(apply(edit, to: text) == "abc\n" + tokenA + "\ndef")
    #expect(edit.selection == caret(4 + size + 1), "the caret is at the start of def")
}

@Test func anAttachmentInTheMiddleOfALineSplitsIt() {
    let text = "abcdef"
    let edit = AttachmentEditing.insertion(of: [idA], over: caret(3), in: nsString(text))
    #expect(apply(edit, to: text) == "abc\n" + tokenA + "\ndef")
    #expect(edit.selection == caret(4 + size + 1))
}

@Test func anAttachmentAtTheEndOfALineUsesTheBreakThatIsThere() {
    let text = "abc\ndef"
    let edit = AttachmentEditing.insertion(of: [idA], over: caret(3), in: nsString(text))
    #expect(apply(edit, to: text) == "abc\n" + tokenA + "\ndef")
    #expect(edit.selection == caret(4 + size + 1), "after the line break that was there")
}

@Test func anAttachmentAtTheEndOfTheNoteGetsALineBreakAfterIt() {
    let text = "abc"
    let edit = AttachmentEditing.insertion(of: [idA], over: caret(3), in: nsString(text))
    #expect(apply(edit, to: text) == "abc\n" + tokenA + "\n")
    #expect(edit.selection == caret(4 + size + 1))
}

@Test func anAttachmentOnTheEmptyLastLineKeepsTheBreakBeforeIt() {
    let text = "abc\n"
    let edit = AttachmentEditing.insertion(of: [idA], over: caret(4), in: nsString(text))
    #expect(apply(edit, to: text) == "abc\n" + tokenA + "\n")
}

@Test func severalAttachmentsAreSeveralLines() {
    let text = "abc"
    let edit = AttachmentEditing.insertion(of: [idA, idB], over: caret(0), in: nsString(text))
    #expect(apply(edit, to: text) == tokenA + "\n" + tokenB + "\nabc")
    #expect(edit.selection == caret(2 * size + 2), "the caret is at the start of abc")
    #expect(AttachmentToken.ids(in: apply(edit, to: text)) == [idA, idB])
}

@Test func anAttachmentReplacesTheSelection() {
    let text = "abc def ghi"
    let edit = AttachmentEditing.insertion(of: [idA], over: NSRange(location: 4, length: 3), in: nsString(text))
    #expect(apply(edit, to: text) == "abc \n" + tokenA + "\n ghi")
    #expect(edit.selection == caret(5 + size + 1))
}

@Test func anAttachmentReplacesASelectedToken() {
    let text = "abc\n" + tokenA + "\ndef"
    let edit = AttachmentEditing.insertion(of: [idB], over: NSRange(location: 4, length: size), in: nsString(text))
    #expect(apply(edit, to: text) == "abc\n" + tokenB + "\ndef")
    #expect(edit.selection == caret(4 + size + 1))
}

@Test func anAttachmentBeforeACRLFKeepsItAndEndsAfterIt() {
    let text = "abc\r\ndef"
    let edit = AttachmentEditing.insertion(of: [idA], over: caret(3), in: nsString(text))
    #expect(apply(edit, to: text) == "abc\n" + tokenA + "\r\ndef")
    #expect(edit.selection == caret(4 + size + 2))
}

@Test func nothingToInsertIsNoEdit() {
    let edit = AttachmentEditing.insertion(of: [], over: NSRange(location: 1, length: 2), in: nsString("abc def"))
    #expect(edit.range.length == 0)
    #expect(edit.replacement.isEmpty)
    #expect(edit.selection == NSRange(location: 1, length: 2))
}
