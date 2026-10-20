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
