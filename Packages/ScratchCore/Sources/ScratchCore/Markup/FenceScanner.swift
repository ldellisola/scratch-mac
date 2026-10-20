import Foundation

/// Finds the fenced code blocks of a note: pairs of lines that start with three backticks (spec §6.4).
///
/// Inside a block nothing is formatting, so the parser skips it and the editor leaves its text as typed. Plan 3 only
/// uses fences to make their contents literal. The block's look, its language label and hidden fences are Plan 4.
public enum FenceScanner {
    /// True when the line has optional spaces and then at least three backticks. Whatever follows, a language name
    /// for instance, does not matter.
    public static func isFenceLine(_ line: String) -> Bool {
        let units = Array(line.utf16)
        return isFence(units, in: TextLine(start: 0, end: units.count, next: units.count))
    }

    /// The blocks of `text`, in order, as UTF-16 ranges from the start of the opening fence line to the end of the
    /// closing fence line (without its line break).
    ///
    /// Fences pair up from the top: the first with the second, the third with the fourth. A fence left without a
    /// partner is not a block [call], so typing three backticks never un-renders the rest of the note until the
    /// closing fence is typed. A fence of four backticks closes a fence of three.
    public static func codeBlocks(in text: String) -> [NSRange] {
        let units = Array(text.utf16)
        return codeBlocks(units: units, lines: TextLines.lines(in: units))
    }

    static func codeBlocks(units: [UInt16], lines: [TextLine]) -> [NSRange] {
        var blocks: [NSRange] = []
        var opening: TextLine?
        for line in lines where isFence(units, in: line) {
            if let first = opening {
                blocks.append(NSRange(location: first.start, length: line.end - first.start))
                opening = nil
            } else {
                opening = line
            }
        }
        return blocks
    }

    private static func isFence(_ units: [UInt16], in line: TextLine) -> Bool {
        let space: UInt16 = 0x20
        let backtick: UInt16 = 0x60
        var index = line.start
        while index < line.end, units[index] == space { index += 1 }
        var backticks = 0
        while index < line.end, units[index] == backtick {
            backticks += 1
            index += 1
        }
        return backticks >= 3
    }
}
