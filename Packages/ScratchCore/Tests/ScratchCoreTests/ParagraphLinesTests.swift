import Foundation
import Testing

@testable import ScratchCore

// The lines the editing rules (spec §6.4) are given, and how a selection moves when they change.

private func r(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

private func change(_ location: Int, removed: Int = 0, inserted: String = "") -> ParagraphLines.Change {
    ParagraphLines.Change(location: location, removed: removed, inserted: Array(inserted.utf16))
}

// MARK: Lines

@Test func paragraphLineOffsetsAreInTheDocument() {
    let text = ParagraphLines("ab\ncd", start: 10)
    #expect(text.lineStart(0) == 10)
    #expect(text.lineEnd(0) == 12)
    #expect(text.lineStart(1) == 13)
    #expect(text.lineEnd(1) == 15)
    #expect(text.text(of: 1) == "cd")
    #expect(text.string(in: r(11, 3)) == "b\nc")
}

@Test func aCaretIsInTheLineItIsOnEvenAtItsEnds() {
    let text = ParagraphLines("ab\r\ncd", start: 10)
    #expect(text.lineIndex(containing: 10) == 0)
    #expect(text.lineIndex(containing: 12) == 0)
    #expect(text.lineIndex(containing: 14) == 1)
    #expect(text.lineIndex(containing: 16) == 1)
}

@Test func aCaretInsideALineBreakOrOutsideTheParagraphsIsInNoLine() {
    let text = ParagraphLines("ab\r\ncd", start: 10)
    #expect(text.lineIndex(containing: 13) == nil)
    #expect(text.lineIndex(containing: 9) == nil)
    #expect(text.lineIndex(containing: 17) == nil)
}

@Test func aCaretTouchesItsLineOnly() {
    let text = ParagraphLines("a\nb\nc", start: 0)
    #expect(text.touchedLines(by: r(2, 0)) == 1...1)
    #expect(text.touchedLines(by: r(1, 0)) == 0...0)
}

@Test func aSelectionTouchesEveryLineThatStartsBeforeItEnds() {
    let text = ParagraphLines("a\nb\nc", start: 0)
    #expect(text.touchedLines(by: r(0, 5)) == 0...2)
    #expect(text.touchedLines(by: r(1, 2)) == 0...1)
    #expect(text.touchedLines(by: r(2, 3)) == 1...2)
}

@Test func aSelectionEndingWhereALineStartsLeavesThatLineOut() {
    let text = ParagraphLines("a\nb\nc", start: 0)
    #expect(text.touchedLines(by: r(0, 2)) == 0...0)
    #expect(text.touchedLines(by: r(0, 4)) == 0...1)
}

@Test func aSelectionStartingOutsideTheParagraphsTouchesNothing() {
    let text = ParagraphLines("a\nb", start: 5)
    #expect(text.touchedLines(by: r(0, 8)) == nil)
}

@Test func blankLinesAreEmptyOrWhiteSpace() {
    let text = ParagraphLines("\n \t\nx\n", start: 0)
    #expect(text.isBlank(0))
    #expect(text.isBlank(1))
    #expect(!text.isBlank(2))
    #expect(text.isBlank(3))
}

@Test func firstNonSpaceSkipsTheSpacesOfTheIndentation() {
    let text = ParagraphLines("  a\n\tb\n   ", start: 10)
    #expect(text.firstNonSpace(of: 0) == 12)
    #expect(text.firstNonSpace(of: 1) == 14)
    #expect(text.firstNonSpace(of: 2) == 20)
}

// MARK: Changes

@Test func noChangesReplaceNothingAndKeepTheSelection() {
    let text = ParagraphLines("abc", start: 0)
    #expect(
        text.edit(applying: [], selection: r(2, 1)) == TextEdit(range: r(2, 0), replacement: "", selection: r(2, 1)))
}

@Test func anEditReachesFromTheFirstChangeToTheEndOfTheLast() {
    let text = ParagraphLines("one\ntwo\nthree", start: 100)
    let edit = text.edit(
        applying: [change(100, inserted: "> "), change(108, removed: 2, inserted: "T")], selection: r(100, 0))
    #expect(edit.range == r(100, 10))
    #expect(edit.replacement == "> one\ntwo\nT")
}

@Test func aCaretMovesBehindTextInsertedAtIt() {
    #expect(ParagraphLines.offset(5, after: [change(5, inserted: "ab")], isSelectionEnd: false) == 7)
    #expect(ParagraphLines.offset(4, after: [change(5, inserted: "ab")], isSelectionEnd: false) == 4)
    #expect(ParagraphLines.offset(6, after: [change(5, inserted: "ab")], isSelectionEnd: false) == 8)
}

@Test func theEndOfASelectionStaysInFrontOfTextInsertedAtIt() {
    #expect(ParagraphLines.offset(5, after: [change(5, inserted: "ab")], isSelectionEnd: true) == 5)
    #expect(ParagraphLines.offset(6, after: [change(5, inserted: "ab")], isSelectionEnd: true) == 8)
}

@Test func anOffsetInsideRemovedTextGoesToTheEndOfWhatReplacesIt() {
    #expect(ParagraphLines.offset(6, after: [change(5, removed: 3)], isSelectionEnd: false) == 5)
    #expect(ParagraphLines.offset(6, after: [change(5, removed: 3, inserted: "xy")], isSelectionEnd: false) == 7)
}

@Test func anOffsetAtTheStartOfRemovedTextStaysThere() {
    #expect(ParagraphLines.offset(5, after: [change(5, removed: 3, inserted: "xy")], isSelectionEnd: false) == 5)
    #expect(ParagraphLines.offset(5, after: [change(5, removed: 3, inserted: "xy")], isSelectionEnd: true) == 5)
}

@Test func anOffsetAfterRemovedTextMovesByTheDifference() {
    #expect(ParagraphLines.offset(8, after: [change(5, removed: 3, inserted: "xy")], isSelectionEnd: false) == 7)
    #expect(ParagraphLines.offset(9, after: [change(5, removed: 3)], isSelectionEnd: true) == 6)
}

@Test func changesBeforeAnOffsetAllCount() {
    let changes = [change(0, inserted: "  "), change(4, inserted: "  "), change(10, removed: 2)]
    #expect(ParagraphLines.offset(3, after: changes, isSelectionEnd: false) == 5)
    #expect(ParagraphLines.offset(12, after: changes, isSelectionEnd: false) == 14)
    #expect(ParagraphLines.offset(20, after: changes, isSelectionEnd: false) == 22)
}
