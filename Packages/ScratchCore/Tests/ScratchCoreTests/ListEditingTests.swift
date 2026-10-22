import Foundation
import Testing

@testable import ScratchCore

// Spec §6.4 (list behaviour): what Return, Tab, ⇧Tab, ⇧⌘L and a checkbox click change. Review Focus 3: Return in the
// middle of an item, on an empty nested item, on an empty top-level item, with the caret before the marker.
// A `|` marks the caret, or the two ends of a selection (TextEditSupport.swift).

private func newline(_ marked: String) -> String? {
    result(of: marked) { ListEditing.newline(paragraphs: $0, start: $1, selection: $2) }
}

private func indent(_ marked: String) -> String? {
    result(of: marked) { ListEditing.indent(paragraphs: $0, start: $1, selection: $2) }
}

private func outdent(_ marked: String) -> String? {
    result(of: marked) { ListEditing.outdent(paragraphs: $0, start: $1, selection: $2) }
}

private func toggleChecklist(_ marked: String) -> String {
    result(of: marked) { ListEditing.toggleChecklist(paragraphs: $0, start: $1, selection: $2) }!
}

private func r(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

/// The line of an attachment: a token and nothing else (docs/features/attachments.md, "Format commands").
private let token = "[[attachment:6f9619ff-8b86-4d11-b42d-00c04fc964ff]]"

// MARK: Return

@Test func newlineContinuesBullet() {
    #expect(newline("- a|") == "- a\n- |")
}

@Test func newlineContinuesCheckbox() {
    #expect(newline("[ ] a|") == "[ ] a\n[ ] |")
}

@Test func newlineSplitsItem() {
    #expect(newline("- ab|cd") == "- ab\n- |cd")
    #expect(newline("[ ] ab|cd") == "[ ] ab\n[ ] |cd")
}

@Test func newlineOnCheckedItemAddsUnchecked() {
    #expect(newline("[x] a|") == "[x] a\n[ ] |")
    #expect(newline("[X] a|") == "[X] a\n[ ] |")
}

@Test func newlineSplittingACheckedItemKeepsTheRestUnchecked() {
    #expect(newline("[x] ab|cd") == "[x] ab\n[ ] |cd")
}

@Test func newlineKeepsIndentation() {
    #expect(newline("  - a|") == "  - a\n  - |")
    #expect(newline("    [x] a|") == "    [x] a\n    [ ] |")
    // The indentation is copied as typed, not rounded to a level.
    #expect(newline("   - a|") == "   - a\n   - |")
}

@Test func newlineInTheMiddleOfALaterLine() {
    #expect(newline("plain\n- ab|cd\nplain") == "plain\n- ab\n- |cd\nplain")
}

@Test func newlineAtTheStartOfTheItemsTextInsertsAnEmptyItemAbove() {
    // The caret is at the end of the marker, not before it: "- " stays above and the text moves down.
    #expect(newline("- |a") == "- \n- |a")
}

@Test func newlineOnEmptyTopLevelItemEndsList() {
    #expect(newline("- a\n- |") == "- a\n|")
    #expect(newline("[ ] a\n[ ] |") == "[ ] a\n|")
    #expect(newline("[x] a\n[x] |") == "[x] a\n|")
}

@Test func newlineOnTheOnlyEmptyItemEndsTheList() {
    #expect(newline("- |") == "|")
}

@Test func newlineOnEmptyTopLevelItemBeforeMoreText() {
    #expect(newline("- a\n- |\n- b") == "- a\n|\n- b")
}

@Test func newlineOnEmptyTopLevelItemWithOneSpaceOfIndentLeavesAnEmptyLine() {
    // One space is level 0 and not a nested item: the whole marker goes, and the indentation with it.
    #expect(newline(" - |") == "|")
}

@Test func newlineOnEmptyNestedItemOutdents() {
    #expect(newline("  - |") == "- |")
    #expect(newline("    - |") == "  - |")
    #expect(newline("    [ ] |") == "  [ ] |")
    #expect(newline("- a\n  - |") == "- a\n- |")
}

@Test func newlineBeforeMarkerIsDefault() {
    #expect(newline("|- a") == nil)
    #expect(newline("-| a") == nil)
    #expect(newline("  |- a") == nil)
    #expect(newline("|[ ] a") == nil)
    #expect(newline("[|] a") == nil)
    #expect(newline("[ |] a") == nil)
    #expect(newline("[ ]| a") == nil)
    #expect(newline("|") == nil)
}

@Test func newlineBeforeTheMarkerOfALaterLineIsDefault() {
    #expect(newline("- a\n|- b") == nil)
}

@Test func newlineOnPlainLineIsDefault() {
    #expect(newline("abc|") == nil)
    #expect(newline("|") == nil)
    #expect(newline("-a|") == nil)
    #expect(newline("--- a|") == nil)
    #expect(newline("[] a|") == nil)
    #expect(newline("[y] a|") == nil)
    #expect(newline("\t- a|") == nil)
}

@Test func newlineOnABulletThatHoldsACheckboxIsABulletLine() {
    // "- [ ] a" is a bullet, not a checkbox [call].
    #expect(newline("- [ ] a|") == "- [ ] a\n- |")
}

@Test func newlineWithSelectionIsDefault() {
    #expect(newline("- |ab|c") == nil)
    #expect(newline("|- a\n- b|") == nil)
}

@Test func newlineAfterAnEmojiCountsUTF16() throws {
    let text = "- 😀"
    let edit = try #require(ListEditing.newline(paragraphs: text, start: 0, selection: r(4, 0)))
    #expect(edit == TextEdit(range: r(4, 0), replacement: "\n- ", selection: r(7, 0)))
    #expect(newline("- 😀|") == "- 😀\n- |")
}

@Test func newlineHonoursTheStartOffset() {
    let edit = ListEditing.newline(paragraphs: "- a", start: 100, selection: r(103, 0))
    #expect(edit == TextEdit(range: r(103, 0), replacement: "\n- ", selection: r(106, 0)))

    let outdent = ListEditing.newline(paragraphs: "  - ", start: 50, selection: r(54, 0))
    #expect(outdent == TextEdit(range: r(50, 2), replacement: "", selection: r(52, 0)))

    let end = ListEditing.newline(paragraphs: "- ", start: 7, selection: r(9, 0))
    #expect(end == TextEdit(range: r(7, 2), replacement: "", selection: r(7, 0)))
}

@Test func newlineOnTheEmptyLastLineAfterAListIsDefault() {
    // `paragraphRange` of a caret after a final line break is empty: the caret's line is an empty one.
    #expect(newline("- a\n|") == nil)
}

@Test func newlineOutsideTheParagraphsIsDefault() {
    #expect(ListEditing.newline(paragraphs: "- a", start: 10, selection: r(5, 0)) == nil)
    #expect(ListEditing.newline(paragraphs: "- a", start: 10, selection: r(20, 0)) == nil)
}

@Test func newlineWithCRLFLines() {
    #expect(newline("- a|\r\n- b") == "- a\n- |\r\n- b")
    #expect(newline("- a\r\n- |\r\n- b") == "- a\r\n|\r\n- b")
    #expect(newline("- a\r\n  - |\r\nb") == "- a\r\n- |\r\nb")
}

// MARK: Tab and ⇧Tab

@Test func indentAddsTwoSpacesToEachListLine() {
    #expect(indent("|- a\n- b|") == "  |- a\n  - b|")
    #expect(indent("|- a\n  - b\n[ ] c|") == "  |- a\n    - b\n  [ ] c|")
}

@Test func indentMovesTheCaretWithTheText() {
    #expect(indent("- a|") == "  - a|")
    #expect(indent("- |a") == "  - |a")
    #expect(indent("|- a") == "  |- a")
    #expect(indent("[x] a|") == "  [x] a|")
}

@Test func indentSkipsPlainLinesInTheSelection() {
    #expect(indent("|- a\nplain\n- b|") == "  |- a\nplain\n  - b|")
}

@Test func indentOnlyTouchesTheLinesOfTheSelection() {
    #expect(indent("- a\n- b|\n- c") == "- a\n  - b|\n- c")
    #expect(indent("- a\n- |b\n- c|\n- d") == "- a\n  - |b\n  - c|\n- d")
}

@Test func indentLeavesOutALineThatTheSelectionOnlyEndsBefore() {
    // The selection ends where the second line starts: that line is not in it.
    #expect(indent("|- a\n|- b") == "  |- a\n|- b")
}

@Test func indentOnPlainLineIsDefault() {
    #expect(indent("abc|") == nil)
    #expect(indent("|") == nil)
    #expect(indent("|abc\nde|") == nil)
    #expect(indent("-a|") == nil)
}

@Test func indentWithAPlainLineInTheSelectionIndentsTheListLine() {
    #expect(indent("|abc\n- no|") == "|abc\n  - no|")
}

@Test func indentUsesTheIndentUnit() {
    #expect(ListEditing.indentUnit == "  ")
}

@Test func indentWorksOnTheLinesOfALargerDocument() {
    let edit = ListEditing.indent(paragraphs: "- a\nplain\n- b", start: 20, selection: r(20, 13))
    // The edit ends where the last change is, at the start of "- b".
    #expect(edit == TextEdit(range: r(20, 10), replacement: "  - a\nplain\n  ", selection: r(22, 15)))
}

@Test func outdentRemovesAtMostTwoSpaces() {
    #expect(outdent("    - a|") == "  - a|")
    #expect(outdent("  - a|") == "- a|")
    #expect(outdent("   - a|") == " - a|")
    #expect(outdent(" - a|") == "- a|")
    #expect(outdent("  [x] a|") == "[x] a|")
}

@Test func outdentOnTopLevelListLineChangesNothing() throws {
    // It is still a list action, so ⇧Tab does not move the focus away: the edit replaces nothing with nothing.
    let marked = MarkedText("- a|")
    let edit = try #require(ListEditing.outdent(paragraphs: "- a", start: 0, selection: marked.selection))
    #expect(edit.range.length == 0)
    #expect(edit.replacement.isEmpty)
    #expect(edit.selection == marked.selection)
    #expect(outdent("- a|") == "- a|")
}

@Test func outdentOnPlainLineIsDefault() {
    #expect(outdent("abc|") == nil)
    #expect(outdent("  abc|") == nil)
    #expect(outdent("|") == nil)
}

@Test func outdentOutdentsEveryListLineOfTheSelection() {
    #expect(outdent("|  - a\n    - b\n- c|") == "|- a\n  - b\n- c|")
}

@Test func outdentSelectionMovesWithText() {
    let edit = ListEditing.outdent(paragraphs: "  - a\n  - b", start: 0, selection: r(0, 11))
    // The edit ends where the last change does (after the spaces of the second line), so "b" is not in it.
    #expect(edit == TextEdit(range: r(0, 8), replacement: "- a\n", selection: r(0, 7)))
}

@Test func outdentCaretInsideTheRemovedSpacesGoesToTheLineStart() {
    #expect(outdent(" |   - a") == "|  - a")
    #expect(outdent(" | - a") == "|- a")
    #expect(outdent("|  - a") == "|- a")
    #expect(outdent(" |- a") == "|- a")
}

@Test func outdentCaretAfterTheRemovedSpacesFollowsTheText() {
    #expect(outdent("    - a|") == "  - a|")
    #expect(outdent("    -| a") == "  -| a")
}

// MARK: ⇧⌘L

@Test func toggleChecklistAddsBoxes() {
    #expect(toggleChecklist("buy|") == "[ ] buy|")
    #expect(toggleChecklist("|buy") == "[ ] |buy")
    #expect(toggleChecklist("|a\nb|") == "[ ] |a\n[ ] b|")
    #expect(toggleChecklist("a\n|b\nc") == "a\n[ ] |b\nc")
}

@Test func toggleChecklistKeepsIndentation() {
    #expect(toggleChecklist("  buy|") == "  [ ] buy|")
    #expect(toggleChecklist("    - a|") == "    [ ] a|")
}

@Test func toggleChecklistReplacesBulletMarker() {
    #expect(toggleChecklist("- a|") == "[ ] a|")
    #expect(toggleChecklist("- |a") == "[ ] |a")
    #expect(toggleChecklist("|- a") == "|[ ] a")
    #expect(toggleChecklist("-| a") == "[ ] |a")
    #expect(toggleChecklist("  - a|") == "  [ ] a|")
    #expect(toggleChecklist("- |") == "[ ] |")
    #expect(toggleChecklist("|- a\n- b|") == "|[ ] a\n[ ] b|")
}

@Test func toggleChecklistAddsToTheLinesThatAreNotCheckboxesOnly() {
    #expect(toggleChecklist("|[x] a\nb\n- c|") == "|[x] a\n[ ] b\n[ ] c|")
    #expect(toggleChecklist("|[ ] a\n[x] b\nc|") == "|[ ] a\n[x] b\n[ ] c|")
}

@Test func toggleChecklistRemovesWhenAllChecked() {
    #expect(toggleChecklist("|[ ] a\n[x] b|") == "|a\nb|")
    #expect(toggleChecklist("[x] a|") == "a|")
    #expect(toggleChecklist("[X] a|") == "a|")
    #expect(toggleChecklist("  [ ] a|") == "  a|")
    #expect(toggleChecklist("[ ] |") == "|")
}

@Test func toggleChecklistTwiceRestoresPlainLines() {
    let added = toggleChecklist("|one\ntwo|")
    #expect(added == "[ ] |one\n[ ] two|")
    #expect(toggleChecklist(added) == "|one\ntwo|")
}

@Test func toggleChecklistRemovalIgnoresBlankLines() {
    #expect(toggleChecklist("|[ ] a\n\n[x] b|") == "|a\n\nb|")
}

@Test func toggleChecklistSkipsBlankLinesWhenOtherLinesAreInTheSelection() {
    #expect(toggleChecklist("|a\n\nb|") == "[ ] |a\n\n[ ] b|")
}

@Test func toggleChecklistOnABlankLineAddsABox() {
    #expect(toggleChecklist("|") == "[ ] |")
    #expect(toggleChecklist("text\n|") == "text\n[ ] |")
    // Only blank lines are in the selection (it ends where the third line starts), so each gets a box.
    #expect(toggleChecklist("|\n\n|") == "[ ] |\n[ ] \n|")
}

@Test func toggleChecklistOnlyTouchesTheLinesOfTheSelection() {
    #expect(toggleChecklist("a\nb|\nc") == "a\n[ ] b|\nc")
    #expect(toggleChecklist("a\n[x] b|\n[x] c") == "a\nb|\n[x] c")
}

@Test func toggleChecklistWithACheckboxAmongPlainLinesAddsNoSecondBox() {
    #expect(toggleChecklist("|[ ] a\nb|") == "|[ ] a\n[ ] b|")
}

@Test func toggleChecklistSkipsTokenLines() {
    // A box in front of the token would make it text, and the picture would be gone.
    #expect(toggleChecklist("|a\n\(token)\nb|") == "[ ] |a\n\(token)\n[ ] b|")
    #expect(toggleChecklist("|\(token)\nb|") == "|\(token)\n[ ] b|")
    #expect(toggleChecklist("|a\n\(token)|") == "[ ] |a\n\(token)|")
    #expect(toggleChecklist("|a\r\n\(token)\r\nb|") == "[ ] |a\r\n\(token)\r\n[ ] b|")
    // Offsets of the paragraphs do not matter.
    #expect(toggleChecklist("a\nb\n|\(token)\nc|") == "a\nb\n|\(token)\n[ ] c|")
}

@Test func toggleChecklistOnlyOnATokenChangesNothing() {
    // A caret on the line, at either end of it, a selection that is the token (a click selects that), and Select All of a
    // note that holds a picture only: the edit is empty, so the text view has nothing to apply.
    #expect(toggleChecklist("\(token)|") == "\(token)|")
    #expect(toggleChecklist("|\(token)") == "|\(token)")
    #expect(toggleChecklist("|\(token)|") == "|\(token)|")
    #expect(toggleChecklist("a\n|\(token)|\nb") == "a\n|\(token)|\nb")
    let edit = ListEditing.toggleChecklist(paragraphs: token, start: 0, selection: r(0, token.utf16.count))
    #expect(edit == TextEdit(range: r(0, 0), replacement: "", selection: r(0, token.utf16.count)))
}

@Test func toggleChecklistLeavesTheBlankLinesAroundATokenEmpty() {
    // Select All over a picture and the empty line after it: the empty line is not "a caret on a blank line".
    #expect(toggleChecklist("|\(token)\n\n|") == "|\(token)\n\n|")
    #expect(toggleChecklist("|\n\(token)\n|b") == "|\n\(token)\n|b")
    // A caret on the blank line below a picture still gets its box.
    #expect(toggleChecklist("\(token)\n|") == "\(token)\n[ ] |")
}

@Test func toggleChecklistDoesNotCountATokenLineAsText() {
    // The token is no line with text, so the other lines are all checkboxes, and they are unchecked.
    #expect(toggleChecklist("|[ ] a\n\(token)\n[x] b|") == "|a\n\(token)\nb|")
    #expect(toggleChecklist("|[x] a\n\(token)|") == "|a\n\(token)|")
}

@Test func toggleChecklistJudgesATokenLineAsTyped() {
    // A line that holds more than the token is text (AGENTS.md: an attachment line is judged as typed).
    #expect(toggleChecklist("\(token) x|") == "[ ] \(token) x|")
    #expect(toggleChecklist("  \(token)|") == "  [ ] \(token)|")
    // The id is lowercase hex only.
    let upper = "[[attachment:6F9619FF-8b86-4d11-b42d-00c04fc964ff]]"
    #expect(toggleChecklist("|\(upper)|") == "[ ] |\(upper)|")
}

@Test func theOtherListRulesLeaveTokenLinesAlone() {
    // A token line is no list line, so Return, Tab and ⇧Tab never change it.
    #expect(newline("\(token)|") == nil)
    #expect(indent("|\(token)|") == nil)
    #expect(outdent("|\(token)|") == nil)
    #expect(indent("|- a\n\(token)\n- b|") == "  |- a\n\(token)\n  - b|")
    #expect(outdent("|  - a\n\(token)\n  - b|") == "|- a\n\(token)\n- b|")
}

@Test func toggleChecklistCountsUTF16() {
    #expect(toggleChecklist("😀|") == "[ ] 😀|")
    #expect(toggleChecklist("😀 a\n|b|") == "😀 a\n[ ] |b|")
    let edit = ListEditing.toggleChecklist(paragraphs: "😀", start: 5, selection: r(7, 0))
    #expect(edit == TextEdit(range: r(5, 0), replacement: "[ ] ", selection: r(11, 0)))
}

@Test func toggleChecklistWithCRLFLines() {
    #expect(toggleChecklist("|a\r\nb|") == "[ ] |a\r\n[ ] b|")
}

@Test func toggleChecklistKeepsTheLineBreaksBetweenTheLines() throws {
    let edit = ListEditing.toggleChecklist(paragraphs: "a\r\n\r\nb", start: 0, selection: r(0, 6))
    // The edit ends where the last change is (the second box), so the "b" after it is not in the replaced range.
    #expect(edit == TextEdit(range: r(0, 5), replacement: "[ ] a\r\n\r\n[ ] ", selection: r(4, 10)))
}

// MARK: A click on the box

@Test func toggleCheckmarkFlips() {
    #expect(
        ListEditing.toggleCheckmark(line: "[ ] a", lineStart: 0, selection: r(5, 0))
            == TextEdit(range: r(1, 1), replacement: "x", selection: r(5, 0)))
    #expect(
        ListEditing.toggleCheckmark(line: "[x] a", lineStart: 0, selection: r(5, 0))
            == TextEdit(range: r(1, 1), replacement: " ", selection: r(5, 0)))
    #expect(
        ListEditing.toggleCheckmark(line: "[X] a", lineStart: 0, selection: r(0, 0))
            == TextEdit(range: r(1, 1), replacement: " ", selection: r(0, 0)))
}

@Test func toggleCheckmarkUsesTheLineStartAndTheIndentation() {
    #expect(
        ListEditing.toggleCheckmark(line: "  [ ] a", lineStart: 10, selection: r(12, 0))
            == TextEdit(range: r(13, 1), replacement: "x", selection: r(12, 0)))
}

@Test func toggleCheckmarkOnAnEmptyCheckbox() {
    #expect(
        ListEditing.toggleCheckmark(line: "[ ] ", lineStart: 0, selection: r(4, 0))
            == TextEdit(range: r(1, 1), replacement: "x", selection: r(4, 0)))
}

@Test func toggleCheckmarkPassesTheSelectionThrough() {
    let selection = r(2, 3)
    #expect(ListEditing.toggleCheckmark(line: "[ ] abc", lineStart: 0, selection: selection)?.selection == selection)
}

@Test func toggleCheckmarkOnPlainLineIsNil() {
    #expect(ListEditing.toggleCheckmark(line: "a", lineStart: 0, selection: r(0, 0)) == nil)
    #expect(ListEditing.toggleCheckmark(line: "- a", lineStart: 0, selection: r(0, 0)) == nil)
    #expect(ListEditing.toggleCheckmark(line: "- [ ] a", lineStart: 0, selection: r(0, 0)) == nil)
    #expect(ListEditing.toggleCheckmark(line: "[] a", lineStart: 0, selection: r(0, 0)) == nil)
    #expect(ListEditing.toggleCheckmark(line: "[ ]a", lineStart: 0, selection: r(0, 0)) == nil)
    #expect(ListEditing.toggleCheckmark(line: "", lineStart: 0, selection: r(0, 0)) == nil)
}
