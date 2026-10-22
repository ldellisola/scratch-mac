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
    /// The styles of the first line of code, by the name on the label of the block (`firstCodeLineStyle(labelName:)`).
    private var firstCodeLineStyles: [String: NSParagraphStyle] = [:]

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
        case .hidden:
            return [.scratchMarker: role.rawValue, .foregroundColor: NSColor.textColor]
        case .fence:
            // No glyph, but for the first character of the line, which is clear.
            return [.scratchMarker: role.rawValue, .foregroundColor: NSColor.clear]
        case .revealed:
            return [.scratchMarker: role.rawValue, .foregroundColor: NSColor.tertiaryLabelColor]
        case .bullet, .checkboxOpen, .checkboxChecked, .attachment:
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

    /// The paragraph style of the first line of code of a block whose label takes `labelReserve` points of the right side of
    /// that line (`CodeBlockMetrics.labelReserve`): the style of a line of code with its tail indent pulled in by that much,
    /// so that the line, and what it wraps into, ends before the label that reaches into it (plan 5 task 7). The style of any
    /// other line of code, `codeBodyStyle`, for a block with no label.
    static func firstCodeLineStyle(labelReserve: CGFloat) -> NSParagraphStyle {
        guard labelReserve > 0 else { return codeBodyStyle }
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = CodeBlockMetrics.inset
        style.headIndent = CodeBlockMetrics.inset
        style.tailIndent = -(CodeBlockMetrics.inset + labelReserve)
        return style
    }

    /// The style of the first line of code of a block whose label says `name`, at this font size: measuring a label is not free,
    /// and a note of 100 blocks styles 100 first lines when it is shown, so the styles are kept by name. Empty `name`: no label.
    func firstCodeLineStyle(labelName name: String) -> NSParagraphStyle {
        if let style = firstCodeLineStyles[name] { return style }
        let style = Self.firstCodeLineStyle(
            labelReserve: CodeBlockMetrics.labelReserve(name: name, noteSize: CGFloat(fontSize)))
        // A note can have any number of fence names, each a label of its own: the table stays small.
        if firstCodeLineStyles.count >= Self.firstCodeLineStyleLimit { firstCodeLineStyles.removeAll() }
        firstCodeLineStyles[name] = style
        return style
    }

    private static let firstCodeLineStyleLimit = 64

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

    /// The paragraph style of an attachment's token line: `lineHeight` high, no more and no less, whatever the font, so that the
    /// line is as high as the preview or chip that is drawn on it and the space above and below it (plan 5, task 4).
    static func attachmentStyle(lineHeight: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }

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
