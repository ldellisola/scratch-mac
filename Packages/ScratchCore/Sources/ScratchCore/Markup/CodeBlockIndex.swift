import Foundation

/// The fenced code blocks of a note, kept up to date from one edit to the next without scanning the note again.
///
/// A block is what ``FenceScanner`` finds: a pair of fence lines and what lies between them. Inside one nothing is
/// formatting, so the editor needs to know, for each paragraph it styles and for each key the owner presses, whether it
/// is in a block (spec §6.4). The index answers that, and says when an edit may have changed the blocks (an edit that
/// touches one of their fence lines, or one that makes a new fence line) so that only then the note is scanned again.
///
/// All offsets are UTF-16 units. The blocks are sorted and do not overlap.
public struct CodeBlockIndex: Equatable, Sendable {
    /// One block with the places where its fence lines end and begin.
    public struct Block: Equatable, Sendable {
        /// From the start of the opening fence line to the end of the closing fence line, without its line break.
        public var range: NSRange
        /// Where the opening fence line ends: its line break begins there.
        public var openingLineEnd: Int
        /// Where the closing fence line starts.
        public var closingLineStart: Int

        public init(range: NSRange, openingLineEnd: Int, closingLineStart: Int) {
            self.range = range
            self.openingLineEnd = openingLineEnd
            self.closingLineStart = closingLineStart
        }
    }

    public private(set) var blocks: [Block]

    /// No blocks.
    public init() {
        blocks = []
    }

    public init(blocks: [Block]) {
        self.blocks = blocks
    }

    /// The blocks of `text`.
    public init(text: String) {
        self.init(units: Array(text.utf16))
    }

    /// The blocks of a text given as its UTF-16 units.
    public init(units: [UInt16]) {
        let lines = TextLines.lines(in: units)
        var found: [Block] = []
        var lineIndex = 0
        for range in FenceScanner.codeBlocks(units: units, lines: lines) {
            // A block starts at the start of its opening fence line and ends at the end of its closing one.
            while lines[lineIndex].start < range.location { lineIndex += 1 }
            let opening = lines[lineIndex]
            while lines[lineIndex].end < NSMaxRange(range) { lineIndex += 1 }
            let closing = lines[lineIndex]
            found.append(Block(range: range, openingLineEnd: opening.end, closingLineStart: closing.start))
        }
        blocks = found
    }

    // MARK: Asking

    /// True when `location` is in a block: from the start of its opening fence line to the end of its closing one,
    /// both included. A caret there is in code, so a key does not make list markers (`ListEditing`).
    public func contains(_ location: Int) -> Bool {
        guard let index = firstBlock(endingAtOrAfter: location) else { return false }
        return blocks[index].range.location <= location
    }

    /// True when `range` has a character in common with a block, the fence lines included (the end of the closing fence
    /// line, where its line break begins, counts). An empty `range` is a position and is asked as ``contains(_:)``. The
    /// editor asks it for the paragraphs a command is about to change: a command never edits inside a block, which
    /// includes a selection that starts and ends outside one but holds it.
    public func intersects(_ range: NSRange) -> Bool {
        if range.length == 0 { return contains(range.location) }
        guard let index = firstBlock(endingAtOrAfter: range.location) else { return false }
        return blocks[index].range.location < NSMaxRange(range)
    }

    /// True when the paragraph that starts at `paragraphStart` is in a block, which is the rule `MarkupParser.parse`
    /// follows: its first character is from the start of the opening fence line up to, not including, the end of the
    /// closing one.
    public func covers(paragraphStart: Int) -> Bool {
        guard let index = firstBlock(endingAtOrAfter: paragraphStart + 1) else { return false }
        return blocks[index].range.location <= paragraphStart
    }

    /// The index of the first block that ends at or after `location`.
    private func firstBlock(endingAtOrAfter location: Int) -> Int? {
        var low = 0
        var high = blocks.count
        while low < high {
            let middle = (low + high) / 2
            if NSMaxRange(blocks[middle].range) < location { low = middle + 1 } else { high = middle }
        }
        return low < blocks.count ? low : nil
    }

    // MARK: Editing

    /// True when `replaced`, a range of the text before an edit, touches the opening or closing fence line of a block,
    /// the ends of the lines included. Such an edit can break the block or change which fences pair up, so the note has
    /// to be scanned again. An edit in the middle of a block cannot, and is carried over with ``apply(_:)``.
    ///
    /// This is half of the test. The other half is whether the edited paragraphs are fence lines now
    /// (``FenceScanner/isFenceLine(_:)``): an edit can make a fence from a line that was none.
    public func touchesFenceLine(_ replaced: NSRange) -> Bool {
        blocks.contains { block in
            Self.touches(
                replaced, NSRange(location: block.range.location, length: block.openingLineEnd - block.range.location))
                || Self.touches(
                    replaced,
                    NSRange(location: block.closingLineStart, length: NSMaxRange(block.range) - block.closingLineStart))
        }
    }

    /// Carries the blocks over an edit that did not touch their fence lines. A block that the edit swallowed is gone.
    public mutating func apply(_ edit: EditMapping) {
        blocks = blocks.compactMap { block in
            let range = edit.mapped(block.range)
            guard range.length > 0 else { return nil }
            return Block(
                range: range, openingLineEnd: edit.mapEnd(block.openingLineEnd),
                closingLineStart: edit.mapStart(block.closingLineStart))
        }
    }

    /// The ranges whose paragraphs are in a block in this index and in none in `other`, or the other way round. These
    /// are the paragraphs the editor styles again when a scan changed the blocks. Each range is in the same half-open
    /// terms as ``covers(paragraphStart:)``: it holds the paragraphs that start in it.
    public func changedRanges(comparedTo other: CodeBlockIndex) -> [NSRange] {
        let mine = blocks.map(\.range)
        let theirs = other.blocks.map(\.range)
        return Self.subtract(theirs, from: mine) + Self.subtract(mine, from: theirs)
    }

    // MARK: Range arithmetic

    /// True when the ranges share a position, counting the position at the end of each.
    private static func touches(_ first: NSRange, _ second: NSRange) -> Bool {
        first.location <= NSMaxRange(second) && second.location <= NSMaxRange(first)
    }

    /// The parts of the sorted, disjoint ranges `source` that no range of `removed` (sorted, disjoint) covers.
    private static func subtract(_ removed: [NSRange], from source: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        var first = 0
        for range in source {
            var start = range.location
            let end = NSMaxRange(range)
            while first < removed.count, NSMaxRange(removed[first]) <= start { first += 1 }
            var index = first
            while start < end {
                if index < removed.count, removed[index].location < end {
                    if removed[index].location > start {
                        result.append(NSRange(location: start, length: removed[index].location - start))
                    }
                    start = max(start, NSMaxRange(removed[index]))
                    index += 1
                } else {
                    result.append(NSRange(location: start, length: end - start))
                    start = end
                }
            }
        }
        return result
    }
}
