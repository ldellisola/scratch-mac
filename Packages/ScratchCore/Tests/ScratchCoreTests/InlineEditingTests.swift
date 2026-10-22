import Foundation
import Testing

@testable import ScratchCore

// Spec §6.4 (bold: "`**text**`, or select + ⌘B"): what ⌘B changes. A `|` marks the caret, or the two ends of a
// selection (TextEditSupport.swift).

private func toggleBold(_ marked: String) -> String {
    result(of: marked) { InlineEditing.toggleBold(paragraphs: $0, start: $1, selection: $2) }!
}

private func r(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

/// The line of an attachment: a token and nothing else (docs/features/attachments.md, "Format commands").
private let token = "[[attachment:6f9619ff-8b86-4d11-b42d-00c04fc964ff]]"

/// What the text view asks before it does ⌘B: whether the selection touches the line of an attachment.
private func touchesAttachment(_ marked: String) -> Bool {
    let input = MarkedText(marked)
    let cut = coveringParagraphs(of: input.text, selection: input.selection)
    return InlineEditing.touchesAttachment(paragraphs: cut.paragraphs, start: cut.start, selection: input.selection)
}

@Test func wrapSelection() {
    #expect(toggleBold("a |word| b") == "a **|word|** b")
    #expect(toggleBold("|word|") == "**|word|**")
}

@Test func wrapSelectionInAListItem() {
    #expect(toggleBold("- |word|") == "- **|word|**")
    #expect(toggleBold("[ ] a |word|") == "[ ] a **|word|**")
}

@Test func wrapSelectionOnALaterLine() {
    #expect(toggleBold("first\nsecond |word|\nthird") == "first\nsecond **|word|**\nthird")
}

@Test func wrapSelectionAcrossLinesWrapsItWhole() {
    // One edit, as the plan says. Bold is one line only, so the parser does not render this one.
    #expect(toggleBold("|a\nb|") == "**|a\nb|**")
}

@Test func wrapDoesNotSwallowWhiteSpaceAtTheEdges() {
    // A run that starts or ends with white space is not bold [call], so the stars go around the words.
    #expect(toggleBold("a| word |b") == "a **|word|** b")
    #expect(toggleBold("|word |") == "**|word|** ")
}

@Test func wrapAfterATripleClickLeavesTheLineBreakOutside() {
    // A triple click selects the paragraph with its line break.
    #expect(toggleBold("|word\n|") == "**|word|**\n")
    #expect(toggleBold("a\n|word\r\n|b") == "a\n**|word|**\r\nb")
}

@Test func wrapASelectionOfOnlyWhiteSpaceIsLiteral() {
    #expect(toggleBold("a|  |b") == "a**|  |**b")
}

@Test func unwrapContentSelection() {
    #expect(toggleBold("a **|word|** b") == "a |word| b")
}

@Test func unwrapWholeRunSelection() {
    #expect(toggleBold("a |**word**| b") == "a |word| b")
}

@Test func unwrapAfterATripleClick() {
    #expect(toggleBold("|**word**\n|") == "|word|\n")
}

@Test func unwrapOnlyTheRunThatIsSelected() {
    #expect(toggleBold("**a** **|b|**") == "**a** |b|")
    #expect(toggleBold("**|a|** **b**") == "|a| **b**")
}

@Test func unwrapInAListItemOnALaterLine() {
    #expect(toggleBold("x\n- **|word|** y") == "x\n- |word| y")
}

@Test func aSelectionInsideABoldRunIsWrappedLikeAnyOther() {
    // The selection is neither a run's content nor a whole run: it is wrapped like any other.
    #expect(toggleBold("**a |b| c**") == "**a **|b|** c**")
}

@Test func wrapInsideAWordStillInsertsStarsButTheyAreNotBold() {
    // Bold needs word boundaries (docs/decisions/0006): the stars go in as always, and the parser does not make a run
    // of them. ⌘B in the middle of a word shows its stars, as typing them there does.
    #expect(toggleBold("ab|c|d") == "ab**|c|**d")
    #expect(MarkupParser.parseLine("ab**c**d", at: 0).isEmpty)
    #expect(toggleBold("a|b|c") == "a**|b|**c")
}

@Test func unwrapNextToPunctuationStillWorks() {
    #expect(toggleBold("(**|word|**)") == "(|word|)")
    #expect(toggleBold("\"|**word**|\"") == "\"|word|\"")
}

@Test func wrapNextToPunctuationMakesARun() {
    let wrapped = toggleBold("(|word|)")
    #expect(wrapped == "(**|word|**)")
    #expect(MarkupParser.parseLine("(**word**)", at: 0).count == 1)
}

@Test func emptySelectionInsertsPairs() {
    #expect(toggleBold("|") == "**|**")
    #expect(toggleBold("a| b") == "a**|** b")
}

@Test func emptySelectionInsertsFourStarsWithTheCaretInTheMiddle() {
    let edit = InlineEditing.toggleBold(paragraphs: "ab", start: 10, selection: r(11, 0))
    #expect(edit == TextEdit(range: r(11, 0), replacement: "****", selection: r(13, 0)))
}

@Test func unicodeSelectionOffsets() {
    #expect(toggleBold("😀 |word|") == "😀 **|word|**")
    #expect(toggleBold("a|😀|b") == "a**|😀|**b")
    #expect(toggleBold("😀 **|wörd 😀|**") == "😀 |wörd 😀|")

    let edit = InlineEditing.toggleBold(paragraphs: "😀 word", start: 0, selection: r(3, 4))
    #expect(edit == TextEdit(range: r(3, 4), replacement: "**word**", selection: r(5, 4)))
}

@Test func theStartOffsetIsRespected() {
    let wrap = InlineEditing.toggleBold(paragraphs: "a word", start: 50, selection: r(52, 4))
    #expect(wrap == TextEdit(range: r(52, 4), replacement: "**word**", selection: r(54, 4)))

    let unwrapContent = InlineEditing.toggleBold(paragraphs: "a **word**", start: 50, selection: r(54, 4))
    #expect(unwrapContent == TextEdit(range: r(52, 8), replacement: "word", selection: r(52, 4)))

    let unwrapRun = InlineEditing.toggleBold(paragraphs: "a **word**", start: 50, selection: r(52, 8))
    #expect(unwrapRun == TextEdit(range: r(52, 8), replacement: "word", selection: r(52, 4)))
}

@Test func twiceRestoresTheText() {
    let wrapped = toggleBold("a |word| b")
    #expect(wrapped == "a **|word|** b")
    #expect(toggleBold(wrapped) == "a |word| b")
}

@Test func inlineCodeStarsAreNotARun() {
    // Inside inline code every character is literal, so there is no bold run to unwrap.
    #expect(toggleBold("`|**x**|`") == "`**|**x**|**`")
}

@Test func boldWithCRLFLines() {
    #expect(toggleBold("a\r\n**|word|**\r\nb") == "a\r\n|word|\r\nb")
    #expect(toggleBold("a\r\n|word|\r\nb") == "a\r\n**|word|**\r\nb")
}

// MARK: Attachments (⌘B never wraps a token)

@Test func aSelectedAttachmentIsTouched() {
    // A click on an attachment selects exactly its token line.
    #expect(touchesAttachment("|\(token)|"))
    #expect(touchesAttachment("a\n|\(token)|\nb"))
    #expect(touchesAttachment("a\r\n|\(token)|\r\nb"))
}

@Test func aSelectionThatHoldsATokenLineIsTouched() {
    #expect(touchesAttachment("|a\n\(token)\nb|"))
    #expect(touchesAttachment("|a\n\(token)|"))
    #expect(touchesAttachment("|\(token)\nb|"))
    #expect(touchesAttachment("a|\n\(token)|"))
}

@Test func aCaretAtEitherEndOfATokenLineTouchesIt() {
    // Where a click beside a chip puts it, and where Backspace next to a token leaves it.
    #expect(touchesAttachment("|\(token)"))
    #expect(touchesAttachment("\(token)|"))
    #expect(touchesAttachment("a\n|\(token)\nb"))
    #expect(touchesAttachment("a\n\(token)|\nb"))
}

@Test func aCaretOrSelectionNextToATokenLineButNotOnItIsNotTouched() {
    // The caret a paste leaves is on the line below the token.
    #expect(!touchesAttachment("\(token)\n|"))
    #expect(!touchesAttachment("\(token)\n|b"))
    #expect(!touchesAttachment("a|\n\(token)"))
    #expect(!touchesAttachment("a\n|\n\(token)"))
    // A selection that ends where the token starts, or starts where it ends, has no character of it.
    #expect(!touchesAttachment("|a\n|\(token)"))
    #expect(!touchesAttachment("\(token)|\nb|"))
    #expect(!touchesAttachment("\(token)|\r\nb|"))
}

@Test func boldTreatsALineThatHoldsMoreThanTheTokenAsText() {
    // Judged as typed (AGENTS.md): white space, or any other character, makes it text, and ⌘B wraps it as any text.
    #expect(!touchesAttachment("| \(token)|"))
    #expect(!touchesAttachment("|\(token) x|"))
    #expect(!touchesAttachment("x\(token)|"))
    #expect(!touchesAttachment("|a word|"))
    #expect(toggleBold("| \(token)|") == " **|\(token)|**")
}
