import AppKit

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
