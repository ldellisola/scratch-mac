import AppKit

/// What the base text and each kind of marker look like at one font size, built once per size (`MarkupStyler`).
///
/// A paragraph is styled by giving it `base` and then adding what its spans need (bold, colours, an indent, a role on
/// each marker). Everything a span adds comes from here.
final class MarkupAppearance {
    let fontSize: Double
    /// The note font and the standard text colour: what every character has before a span changes it.
    let base: [NSAttributedString.Key: Any]
    /// The regular note font: what a line of a code block has, whatever it was before.
    let regularFont: NSFont
    /// The font of a bold run.
    let boldFont: NSFont
    /// The width of one character of the monospaced note font, which is what a list's hanging indent counts in.
    let spaceWidth: CGFloat
    private var indentStyles: [Int: NSParagraphStyle] = [:]

    init(fontSize: Double) {
        self.fontSize = fontSize
        base = NoteTextView.noteAttributes(size: fontSize)
        regularFont = NoteTextView.noteFont(size: fontSize)
        boldFont = NoteTextView.boldNoteFont(size: fontSize)
        spaceWidth = (" " as NSString).size(withAttributes: [.font: NoteTextView.noteFont(size: fontSize)]).width
    }

    /// The paragraph style of a list line whose text starts `characters` characters in: its wrapped lines start there
    /// too, under the text of the item and not under its marker (spec §6.4, "hanging indent").
    func indentStyle(characters: Int) -> NSParagraphStyle {
        if let style = indentStyles[characters] { return style }
        let style = NSMutableParagraphStyle()
        style.headIndent = CGFloat(characters) * spaceWidth
        style.firstLineHeadIndent = 0
        indentStyles[characters] = style
        return style
    }

    /// The attributes of a marker character with `role`: the role itself and the colour that goes with it. A hidden
    /// marker has no glyph, whatever its colour, and a revealed one is shown dimmed so that the owner sees the
    /// characters next to the caret without taking them for text. A bullet's or checkbox's marker is transparent, and
    /// `MarkupLayoutManager` draws the bullet or the box over it.
    func markerAttributes(_ role: MarkerRole) -> [NSAttributedString.Key: Any] {
        switch role {
        case .hidden, .fence:
            return [.scratchMarker: role.rawValue, .foregroundColor: NSColor.textColor]
        case .revealed:
            return [.scratchMarker: role.rawValue, .foregroundColor: NSColor.tertiaryLabelColor]
        case .bullet, .checkboxOpen, .checkboxChecked:
            return [.scratchMarker: role.rawValue, .foregroundColor: NSColor.clear]
        }
    }

    /// What the text of a ticked checkbox looks like: struck through and dimmed (spec §6.4).
    static var tickedTextAttributes: [NSAttributedString.Key: Any] {
        [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor]
    }

    /// The paragraph style of a line of a code block, and of a fence line while it is shown: the lines are
    /// `CodeBlockMetrics.inset` in from both sides of the tinted block (plan 4 "Blocks").
    static let codeBodyStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = CodeBlockMetrics.inset
        style.headIndent = CodeBlockMetrics.inset
        style.tailIndent = -CodeBlockMetrics.inset
        return style
    }()

    /// The paragraph style of a fence line while it is hidden: a line of exactly `CodeBlockMetrics.fenceHeight`, so that
    /// the top and the bottom of the block have a little padding and no text.
    static let codeFenceStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = CodeBlockMetrics.inset
        style.headIndent = CodeBlockMetrics.inset
        style.tailIndent = -CodeBlockMetrics.inset
        style.minimumLineHeight = CodeBlockMetrics.fenceHeight
        style.maximumLineHeight = CodeBlockMetrics.fenceHeight
        return style
    }()

    /// What a link looks like: the link colour and an underline. The URL is kept for ⌘-click (`MarkupStyler.link(at:)`).
    static func linkAttributes(for url: URL) -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue,
            .scratchLink: url,
        ]
    }

    /// What inline code looks like: the code colour on a tint.
    static var inlineCodeAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: MarkupColors.codeText, .backgroundColor: MarkupColors.codeBackground]
    }
}
