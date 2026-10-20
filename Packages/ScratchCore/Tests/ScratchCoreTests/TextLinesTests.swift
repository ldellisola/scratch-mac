import Foundation
import Testing

@testable import ScratchCore

// The line splitting and white space rules the markup scanners share (AGENTS.md: "\r\n" is one line break).

private func lines(_ text: String) -> [TextLine] {
    TextLines.lines(in: Array(text.utf16))
}

private func line(_ start: Int, _ end: Int, _ next: Int) -> TextLine {
    TextLine(start: start, end: end, next: next)
}

@Test func aTextWithoutBreaksIsOneLine() {
    #expect(lines("abc") == [line(0, 3, 3)])
    #expect(lines("") == [line(0, 0, 0)])
}

@Test func linesEndAtLineFeedCarriageReturnAndBoth() {
    #expect(lines("a\nb") == [line(0, 1, 2), line(2, 3, 3)])
    #expect(lines("a\rb") == [line(0, 1, 2), line(2, 3, 3)])
    #expect(lines("a\r\nb") == [line(0, 1, 3), line(3, 4, 4)])
}

@Test func aFinalBreakLeavesAnEmptyLastLine() {
    #expect(lines("a\n") == [line(0, 1, 2), line(2, 2, 2)])
    #expect(lines("a\r\n") == [line(0, 1, 3), line(3, 3, 3)])
}

@Test func emptyLinesAreLines() {
    #expect(lines("\n\n") == [line(0, 0, 1), line(1, 1, 2), line(2, 2, 2)])
    #expect(lines("\r\n\r\n") == [line(0, 0, 2), line(2, 2, 4), line(4, 4, 4)])
    #expect(lines("\n\r") == [line(0, 0, 1), line(1, 1, 2), line(2, 2, 2)])
}

@Test func offsetsAreUTF16() {
    #expect(lines("😀\na") == [line(0, 2, 3), line(3, 4, 4)])
}

@Test func whiteSpaceUnits() {
    for unit: UInt16 in [0x20, 0x09, 0x0A, 0x0D, 0xA0, 0x2003, 0x3000] {
        #expect(unit.isMarkupWhitespace, "\(unit)")
    }
    for unit: UInt16 in [0x61, 0x2A, 0x60, 0x2D, 0xD83D, 0xDE00, 0x00E9] {
        #expect(!unit.isMarkupWhitespace, "\(unit)")
    }
}
