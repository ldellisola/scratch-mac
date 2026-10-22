import AppKit
import ScratchCode
import ScratchCore

extension NSAttributedString.Key {
    /// What a marker character is for: the value is a `MarkerRole`'s raw value. The characters of a bold run's `**` and
    /// of inline code's backticks carry `hidden` or `revealed`, a bullet's `-` carries `bullet` and a checkbox's `[?]`
    /// carries `checkboxOpen` or `checkboxChecked` (spec §6.4). `MarkupLayoutManager` reads it to give the hidden ones
    /// null glyphs and to draw the bullets and boxes over the others. Nothing else sets or reads it.
    nonisolated static let scratchMarker = NSAttributedString.Key("io.github.ldellisola.Scratch.marker")

    /// The URL of a link, on the characters of the URL (a `URL` value). It is not `.link` on purpose: AppKit opens a
    /// `.link` with a plain click and changes the cursor over it, and Scratch opens a link only with ⌘-click, so that a
    /// click that places the caret never opens a browser (spec §6.4).
    nonisolated static let scratchLink = NSAttributedString.Key("io.github.ldellisola.Scratch.link")

    /// What a paragraph of a fenced code block is: a `CodeBlockMark`, on the whole paragraph (its line break included),
    /// for the lines of the block and for both of its fence lines. `MarkupLayoutManager` reads it to draw the tinted
    /// block behind the lines and the language label at its top right, and `CodeBlockStyler.language(ofBlockAt:)` reads
    /// the language off the one on the opening fence line. Only `MarkupStyler` and `CodeBlockStyler` set it.
    nonisolated static let scratchCodeBlock = NSAttributedString.Key("io.github.ldellisola.Scratch.codeBlock")

    /// What an attachment line is: an `AttachmentMark`, on the whole paragraph of a token line `[[attachment:<id>]]` (its line
    /// break included). `MarkupLayoutManager` reads it to draw the preview or the chip in the line's rectangle, and
    /// `MarkupStyler` reads it to size the line again when the text width or the attachment changes. Only `MarkupStyler` sets
    /// it, and only on a line outside a fenced block.
    nonisolated static let scratchAttachment = NSAttributedString.Key("io.github.ldellisola.Scratch.attachment")
}

/// The roles a marker character can have (`NSAttributedString.Key.scratchMarker`).
nonisolated enum MarkerRole: String, Sendable {
    /// A `**` or backtick of a closed run while the caret is away: no glyph, no width.
    case hidden
    /// The same characters while the caret or the selection touches the run: shown in `tertiaryLabelColor`.
    case revealed
    /// The `-` of a bullet: transparent, with a `•` drawn over it.
    case bullet
    /// The `[ ]` of an unticked checkbox: transparent, with a box drawn over it (plan 3, task 4).
    case checkboxOpen
    /// The `[x]` of a ticked checkbox: transparent, with a ticked box drawn over it (plan 3, task 4).
    case checkboxChecked
    /// The characters of a fence line of a code block (the three backticks and the language name) while the caret is
    /// away: no glyph, no width, so that the line is the 6 pt of padding that its paragraph style makes of it (plan 4,
    /// task 5). The line break of the line has no role. While the caret or selection touches the line its characters
    /// are `revealed`.
    case fence
    /// Every character of an attachment's token line but the first (plan 5, task 4): no glyph and no width, so that the
    /// line holds only what `MarkupLayoutManager` draws over it. The first character has no role and a clear colour: its
    /// glyph is what gives the line a line fragment of its own, as high as the paragraph style says.
    case attachment
}

/// Which line of a fenced block a paragraph is (`CodeBlockMark`).
nonisolated enum CodeBlockPart: Int, Sendable {
    /// The line with the opening fence.
    case opening
    /// A line of code between the fences.
    case body
    /// The line with the closing fence.
    case closing
}

/// The value of `NSAttributedString.Key.scratchCodeBlock`: where the paragraph is in its block, and, on the opening
/// fence line, which language the block is and what its label says. Immutable, and equal to another mark with the same
/// values, so that the attribute runs of the lines of a block are one run.
///
/// The label state is only on the mark of the opening fence line, so that a keystroke in a line of code never has to
/// know it, and the label does not flicker while the new result is on its way (`MarkupStyler` keeps a detected label
/// when it styles the fence line again).
nonisolated final class CodeBlockMark: NSObject, @unchecked Sendable {
    let part: CodeBlockPart
    /// The language of the block: the one the fence names, or the one detected from the code. Nil for a name Scratch
    /// does not know (`ruby`), and until the detection of an unnamed fence has a language.
    let language: CodeLanguage?
    /// True when the language was detected, which is when the fence has no name: the label is shown in italics.
    let isDetected: Bool
    /// What the label says: the language's label, or an unknown fence name as written. Empty when there is none.
    let name: String

    init(part: CodeBlockPart, language: CodeLanguage? = nil, isDetected: Bool = false, name: String = "") {
        self.part = part
        self.language = language
        self.isDetected = isDetected
        self.name = name
        super.init()
    }

    /// The mark of a line of code and of a closing fence line: they have no label.
    static let body = CodeBlockMark(part: .body)
    static let closing = CodeBlockMark(part: .closing)

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CodeBlockMark else { return false }
        return part == other.part && language == other.language && isDetected == other.isDetected && name == other.name
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(part)
        hasher.combine(language)
        hasher.combine(isDetected)
        hasher.combine(name)
        return hasher.finalize()
    }
}

/// The measures of a code block, in points (plan 4 "Blocks"). The paragraph styles, the layout manager and the tests
/// all read them from here.
nonisolated enum CodeBlockMetrics {
    /// The space between the edge of the tinted block and its lines, on each side.
    static let inset: CGFloat = 10
    /// The height of a hidden fence line: the padding at the top and the bottom of the block.
    static let fenceHeight: CGFloat = 6
    /// The radius of the block's corners.
    static let cornerRadius: CGFloat = 6
    /// How much smaller than the note font the label is.
    static let labelSizeReduction: CGFloat = 2
    /// The space between the top of the block and the top of the label.
    static let labelTopOffset: CGFloat = 2
    /// How far the label of a detected language leans (`NSAttributedString.Key.obliqueness`): italics.
    static let labelObliqueness: CGFloat = 0.2
    /// The space between the end of the first line of code and the label that reaches into it (plan 5 task 7).
    static let labelGap: CGFloat = 12
    /// The most that a label takes from the first line of code, whatever its name: a fence name of a hundred characters
    /// would otherwise leave no room for the code.
    static let maximumLabelReserve: CGFloat = 240

    /// The font of a label, for text at `noteSize` points: monospaced, `labelSizeReduction` smaller, and never below 7 pt.
    /// `MarkupLayoutManager` draws the label in it and `labelReserve(name:noteSize:)` measures it, so that the room that is
    /// kept is the room that the label takes.
    static func labelFont(noteSize: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: max(noteSize - labelSizeReduction, 7), weight: .regular)
    }

    /// How far in from the right, beyond the `inset` that every line has, the first line of code of a block whose label says
    /// `name` must end: the width of the label and `labelGap`, at most `maximumLabelReserve`. The label is drawn at the top
    /// right of the block and reaches into that line, so a line that ended under it would be covered, and a click on its end
    /// would open the label's menu. Zero for a block with no label.
    static func labelReserve(name: String, noteSize: CGFloat) -> CGFloat {
        guard !name.isEmpty else { return 0 }
        let width = (name as NSString).size(withAttributes: [.font: labelFont(noteSize: noteSize)]).width
        return min(width + labelGap, maximumLabelReserve)
    }
}

/// The colours of a code block that the layout manager draws, which is not on the main actor.
nonisolated enum CodeBlockColors {
    /// The tint behind the lines of a block: the `CodeBackground` asset, black at 6% in light mode and white at 10% in
    /// dark mode, as behind inline code.
    static var background: NSColor {
        NSColor(named: "CodeBackground") ?? NSColor.labelColor.withAlphaComponent(0.06)
    }

    /// The colour of the language label.
    static var label: NSColor { NSColor.secondaryLabelColor }
}

/// The value of `NSAttributedString.Key.scratchAttachment`: what an attachment line is drawn as, and how big. Immutable.
/// The layout manager draws from it alone, because it is not on the main actor and cannot ask the catalog.
///
/// Two marks are equal only when they are the same object, so the marks of two lines for the same attachment stay two
/// runs of the text storage, and `hasSameLook(as:)` tells whether styling a line again would change anything.
nonisolated final class AttachmentMark: NSObject, @unchecked Sendable {
    /// What the line is drawn as.
    nonisolated enum Kind: Equatable, Sendable {
        /// An image whose file is in place: a preview scaled into the text width, up to 240 pt high.
        case image
        /// Any other file whose copy is in place: a chip with the file's icon, name and size.
        case file
        /// A file whose copy is still being made: a chip that says "Copying…".
        case copying
        /// An id with no row, a file that is gone or an image that cannot be decoded: a chip that says "Missing attachment".
        case missing
    }

    let id: AttachmentID
    let kind: Kind
    /// The size of what is drawn, in points: the preview, or the chip. The line is 12 pt higher (6 pt above and below).
    let displaySize: NSSize
    /// The file's name, which a chip shows. Empty for an id that has no row.
    let fileName: String
    /// The file's size in bytes, which a file chip shows. Nil for an id that has no row.
    let byteSize: Int64?
    /// Where Scratch's copy of an image is, for the layout manager to ask `AttachmentPreviews` for. Nil for any other kind.
    let fileURL: URL?
    /// The size in pixels, of the longer side, that the preview of an image is asked for. Zero for any other kind.
    let previewPixelSize: Int
    /// The icon of a chip: the file's Finder icon, or the one of its type while it is being copied. Nil for a missing
    /// attachment, which draws a symbol.
    let icon: NSImage?

    init(
        id: AttachmentID, kind: Kind, displaySize: NSSize, fileName: String, byteSize: Int64?, fileURL: URL? = nil,
        previewPixelSize: Int = 0, icon: NSImage? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displaySize = displaySize
        self.fileName = fileName
        self.byteSize = byteSize
        self.fileURL = fileURL
        self.previewPixelSize = previewPixelSize
        self.icon = icon
        super.init()
    }

    /// True when a line with `other` would be drawn in the same way as one with this mark, and as high.
    func hasSameLook(as other: AttachmentMark) -> Bool {
        id == other.id && kind == other.kind && displaySize == other.displaySize && fileName == other.fileName
            && byteSize == other.byteSize && fileURL == other.fileURL && previewPixelSize == other.previewPixelSize
    }
}

/// The colours of inline code, from the asset catalog (`CodeText` and `CodeBackground`, each with a light and a dark
/// variant), so that they follow the appearance of the window.
enum MarkupColors {
    private static let text = NSColor(named: "CodeText") ?? NSColor.systemRed
    private static let background = NSColor(named: "CodeBackground") ?? NSColor.labelColor.withAlphaComponent(0.06)

    /// The colour of the text of inline code: `#C41A16` in light mode and `#FC6A5D` in dark mode.
    static var codeText: NSColor { text }

    /// The tint behind inline code: black at 6% in light mode and white at 10% in dark mode.
    static var codeBackground: NSColor { background }
}
