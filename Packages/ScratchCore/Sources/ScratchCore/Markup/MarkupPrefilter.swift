import Foundation

extension MarkupParser {
    /// A cheap test the editor runs on every line of a note it styles: false means ``parseLine(_:at:)`` finds no span
    /// in `line`, so the editor skips the parse. It scans the line once and allocates nothing.
    ///
    /// `line` is one line's UTF-16 units without its line break. The answer is true for a line that has a span and
    /// may be true for one that has none (`-5 degrees`, a lone `*`), never false for a line that has one:
    /// - A bullet starts with spaces and then `-`, and a checkbox with spaces and then `[`.
    /// - Bold has `**` and inline code has a backtick.
    /// - A link has `://` after its scheme.
    ///
    /// Every marker the parser learns needs its first character here, or the editor will not render it
    /// (`MarkupPrefilterTests` holds the parser to this).
    public static func mayHaveSpans(in line: ArraySlice<UInt16>) -> Bool {
        let space: UInt16 = 0x20
        let dash: UInt16 = 0x2D
        let openBracket: UInt16 = 0x5B
        let star: UInt16 = 0x2A
        let backtick: UInt16 = 0x60
        let colon: UInt16 = 0x3A
        let slash: UInt16 = 0x2F

        var index = line.startIndex
        let end = line.endIndex
        while index < end, line[index] == space { index += 1 }
        if index < end, line[index] == dash || line[index] == openBracket { return true }
        while index < end {
            let unit = line[index]
            if unit == star || unit == backtick { return true }
            if unit == colon, index + 2 < end, line[index + 1] == slash, line[index + 2] == slash { return true }
            index += 1
        }
        return false
    }
}
