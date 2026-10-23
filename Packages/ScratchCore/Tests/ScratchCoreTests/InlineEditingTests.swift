import Foundation
import Testing

@testable import ScratchCore

// Spec §6.4 (bold: "`**text**`, or select + ⌘B"): what ⌘B changes. A `|` marks the caret, or the two ends of a
// selection (TextEditSupport.swift).

/// The marked text after ⌘B, or nil when the rule says that ⌘B beeps.
private func toggleBold(_ marked: String) -> String? {
    result(of: marked) { InlineEditing.toggleBold(paragraphs: $0, start: $1, selection: $2) }
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

@Test func wrapSelectionAcrossLinesWrapsEachLine() {
    // Bold is one line only, so each line is a run of its own (plan 6 task 5). The selection covers the content, as it
    // does for one line: from after the first stars to before the last ones.
    #expect(toggleBold("|a\nb|") == "**|a**\n**b|**")
    #expect(toggleBold("x |a\nb| y") == "x **|a**\n**b|** y")
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

@Test func aSelectionOfOnlyWhiteSpaceIsNil() {
    // Nothing to make bold: the text view beeps (plan 6 task 5).
    #expect(toggleBold("a|  |b") == nil)
    #expect(toggleBold("|   |") == nil)
    #expect(toggleBold("|\n|") == nil)
    #expect(toggleBold("|  \n  |") == nil)
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
    // Where there is no word under the caret.
    #expect(toggleBold("|") == "**|**")
    #expect(toggleBold("a | b") == "a **|** b")
    #expect(toggleBold("a |") == "a **|**")
    #expect(toggleBold("a\n|\nb") == "a\n**|**\nb")
}

@Test func emptySelectionInsertsFourStarsWithTheCaretInTheMiddle() {
    let edit = InlineEditing.toggleBold(paragraphs: "a  b", start: 10, selection: r(12, 0))
    #expect(edit == TextEdit(range: r(12, 0), replacement: "****", selection: r(14, 0)))
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

@Test func twiceRestoresTheText() throws {
    let wrapped = try #require(toggleBold("a |word| b"))
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

// MARK: A caret (plan 6 task 5: ⌘B on a word)

@Test func boldCaretInWordWrapsWord() {
    // The plan's example: the caret at 6 of "say hello now" gives the caret at 8.
    #expect(toggleBold("say he|llo now") == "say **he|llo** now")
    let edit = InlineEditing.toggleBold(paragraphs: "say hello now", start: 0, selection: r(6, 0))
    #expect(edit == TextEdit(range: r(4, 5), replacement: "**hello**", selection: r(8, 0)))
}

@Test func boldCaretAtTheEdgeOfAWordWrapsIt() {
    #expect(toggleBold("say |hello now") == "say **|hello** now")
    #expect(toggleBold("say hello| now") == "say **hello|** now")
    #expect(toggleBold("|hello") == "**|hello**")
    #expect(toggleBold("hello|") == "**hello|**")
}

@Test func boldCaretNextToPunctuationWrapsTheWordOnly() {
    #expect(toggleBold("(word|)") == "(**word|**)")
    #expect(toggleBold("a, b|.") == "a, **b|**.")
    #expect(toggleBold("src/he|llo.ts") == "src/**he|llo**.ts")
}

@Test func boldCaretWrapsTheWordOfALaterLine() {
    #expect(toggleBold("first\nsecond wo|rd\nthird") == "first\nsecond **wo|rd**\nthird")
    #expect(toggleBold("a\r\nsay |hi\r\nb") == "a\r\nsay **|hi**\r\nb")
}

@Test func boldCaretTakesAnApostropheInsideAWord() {
    #expect(toggleBold("don't| stop") == "**don't|** stop")
    #expect(toggleBold("don|\u{2019}t stop") == "**don|\u{2019}t** stop")
    // A quote mark at the edge of a word is not part of it.
    #expect(toggleBold("'quoted|'") == "'**quoted|**'")
}

@Test func boldCaretKnowsLettersAndDigitsOfAnyScriptAndNotEmoji() {
    #expect(toggleBold("caf\u{e9}| au lait") == "**caf\u{e9}|** au lait")
    #expect(toggleBold("b\u{f6}se wo|rd") == "b\u{f6}se **wo|rd**")
    #expect(toggleBold("v2|") == "**v2|**")
    #expect(toggleBold("\u{1F600} he|llo") == "\u{1F600} **he|llo**")
    // An emoji is no word: nothing to wrap, so the stars go in empty.
    #expect(toggleBold("\u{1F600}|") == "\u{1F600}**|**")
}

@Test func boldCaretInAListItemWrapsTheWordAfterTheMarker() {
    #expect(toggleBold("- |hello") == "- **|hello**")
    #expect(toggleBold("- hel|lo") == "- **hel|lo**")
    #expect(toggleBold("[ ] bu|y milk") == "[ ] **bu|y** milk")
    #expect(toggleBold("  - nes|ted") == "  - **nes|ted**")
}

@Test func boldCaretInAMarkerActsAtTheStartOfTheText() {
    // The stars must not go into `- ` or `[x]`: that would end the list item.
    #expect(toggleBold("-| hello") == "- **|hello**")
    #expect(toggleBold("|- hello") == "- **|hello**")
    #expect(toggleBold("[x|] done") == "[x] **|done**")
    #expect(toggleBold("|[ ] done") == "[ ] **|done**")
    // Nothing after the marker: the pairs go in after it.
    #expect(toggleBold("- |") == "- **|**")
    // A lone `-` is no list item, so it is text like any other.
    #expect(toggleBold("-|") == "-**|**")
}

@Test func boldCaretInRunUnwraps() {
    #expect(toggleBold("say **he|llo** now") == "say he|llo now")
    // Touching the run counts: right inside the stars, and at either outer edge.
    #expect(toggleBold("say **|hello** now") == "say |hello now")
    #expect(toggleBold("say **hello|** now") == "say hello| now")
    #expect(toggleBold("say |**hello** now") == "say |hello now")
    #expect(toggleBold("say **hello**| now") == "say hello| now")
    // Between the two stars of a marker.
    #expect(toggleBold("say *|*hello** now") == "say |hello now")
    #expect(toggleBold("say **hello*|* now") == "say hello| now")
}

@Test func boldCaretInOneRunOfSeveralUnwrapsThatRun() {
    #expect(toggleBold("**a** **b|**") == "**a** b|")
    #expect(toggleBold("**a|** **b**") == "a| **b**")
}

@Test func boldCaretInARunInAListItemUnwraps() {
    #expect(toggleBold("- **wo|rd** x") == "- wo|rd x")
    #expect(toggleBold("[x] **wo|rd**") == "[x] wo|rd")
}

@Test func boldCaretInEmptyPairRemovesIt() {
    #expect(toggleBold("**|**") == "|")
    #expect(toggleBold("a **|** b") == "a | b")
    #expect(toggleBold("- **|**") == "- |")
    let edit = InlineEditing.toggleBold(paragraphs: "a **** b", start: 20, selection: r(24, 0))
    #expect(edit == TextEdit(range: r(22, 4), replacement: "", selection: r(22, 0)))
}

@Test func boldTwiceInWordRestoresText() throws {
    let wrapped = try #require(toggleBold("say he|llo now"))
    #expect(wrapped == "say **he|llo** now")
    #expect(toggleBold(wrapped) == "say he|llo now")
    // And at the edges, where the caret is touching the run.
    let atStart = try #require(toggleBold("say |hello now"))
    #expect(toggleBold(atStart) == "say |hello now")
    let atEnd = try #require(toggleBold("say hello| now"))
    #expect(toggleBold(atEnd) == "say hello| now")
}

@Test func boldTwiceOnTheEmptyPairRestoresText() throws {
    let inserted = try #require(toggleBold("a | b"))
    #expect(inserted == "a **|** b")
    #expect(toggleBold(inserted) == "a | b")
}

@Test func boldCaretWrapsAWordThatIsARun() throws {
    // The result is a run, whatever is next to the word.
    for marked in ["say he|llo now", "(he|llo)", "\"he|llo\"", "he|llo", "- he|llo", "x, he|llo."] {
        let edit = try #require(toggleBold(marked), "\(marked)")
        let text = MarkedText(edit).text
        #expect(MarkupParser.parse(text).contains { $0.kind == .bold }, "\(text)")
    }
}

@Test func boldCaretOutsideTheParagraphsIsNil() {
    #expect(InlineEditing.toggleBold(paragraphs: "word", start: 10, selection: r(3, 0)) == nil)
    #expect(InlineEditing.toggleBold(paragraphs: "word", start: 10, selection: r(20, 0)) == nil)
}

// MARK: Several lines (plan 6 task 5)

@Test func boldLinesWrapEachLine() {
    // The plan's example: both lines of a list, selected whole.
    #expect(toggleBold("|- one\n- two\n|") == "- **|one**\n- **two|**\n")
    let input = MarkedText("|- one\n- two\n|")
    let cut = coveringParagraphs(of: input.text, selection: input.selection)
    let edit = InlineEditing.toggleBold(paragraphs: cut.paragraphs, start: cut.start, selection: input.selection)
    #expect(edit?.replacement == "**one**\n- **two**")
    #expect(edit?.range == r(2, 9))
}

@Test func boldLinesWrapAfterTheListMarkerAndKeepTheIndent() {
    #expect(toggleBold("|[ ] a\n  - b\nc|") == "[ ] **|a**\n  - **b**\n**c|**")
}

@Test func boldLinesLeaveWhiteSpaceAtTheEndsOutside() {
    #expect(toggleBold("|  one  \n\ttwo |") == "  **|one**  \n\t**two|** ")
}

@Test func boldLinesStartAndEndInTheMiddleOfTheirLines() {
    // The first line is wrapped from the selection to its end, the last from its start to the selection.
    #expect(toggleBold("one t|wo\nthree\nfo|ur five") == "one t**|wo**\n**three**\n**fo|**ur five")
}

@Test func boldLinesSkipBlankLines() {
    #expect(toggleBold("|a\n\nb|") == "**|a**\n\n**b|**")
    #expect(toggleBold("|a\n   \n- \nb|") == "**|a**\n   \n- \n**b|**")
}

@Test func boldLinesUnwrapWhenAllBold() {
    #expect(toggleBold("- |**one**\n- **two**|\n") == "- |one\n- two|\n")
    #expect(toggleBold("|**a**\n\n**b**|") == "|a\n\nb|")
}

@Test func boldLinesUnwrapWhenTheSelectionIsTheContent() {
    // The selection is what ⌘B left after wrapping them: from after the first stars to before the last ones.
    #expect(toggleBold("**|one**\n**two|**") == "|one\ntwo|")
}

@Test func boldLinesTwiceRestoreTheText() throws {
    let wrapped = try #require(toggleBold("|- one\n- two\nthree|"))
    #expect(wrapped == "- **|one**\n- **two**\n**three|**")
    #expect(toggleBold(wrapped) == "- |one\n- two\nthree|")
}

@Test func boldLinesWrapOnlyTheLinesThatAreNotRunsYet() {
    // Some are bold already: those stay as they are, and the others become bold, as ⇧⌘L does with boxes.
    #expect(toggleBold("|**a**\nb|") == "|**a**\n**b|**")
    #expect(toggleBold("|a\n**b**\nc|") == "**|a**\n**b**\n**c|**")
}

@Test func boldLinesOfOnlyWhiteSpaceAreNil() {
    #expect(toggleBold("|  \n\t|") == nil)
    #expect(toggleBold("|- \n- |") == nil)
}

@Test func boldLinesOfALongerDocumentUseTheStartOffset() {
    let edit = InlineEditing.toggleBold(paragraphs: "- a\n- b", start: 100, selection: r(100, 7))
    #expect(edit == TextEdit(range: r(102, 5), replacement: "**a**\n- **b**", selection: r(104, 9)))
}

@Test func boldLinesWithCRLF() {
    #expect(toggleBold("|a\r\nb|") == "**|a**\r\n**b|**")
    #expect(toggleBold("|**a**\r\n**b**|") == "|a\r\nb|")
}

@Test func aTripleClickOnAListLineWrapsTheTextAfterTheMarker() {
    // The selection starts in the marker and holds the line break: one line, the content only.
    #expect(toggleBold("|- one\n|two") == "- **|one|**\ntwo")
    #expect(toggleBold("|[x] one\n|two") == "[x] **|one|**\ntwo")
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
