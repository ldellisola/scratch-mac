import AppKit

/// The measures of an attachment line, in points (plan 5 "Display"). The styler, the layout manager and the tests all read
/// them from here.
nonisolated enum AttachmentMetrics {
    /// The tallest an image preview is, whatever its proportions.
    static let imageMaxHeight: CGFloat = 240
    /// The space above and below what is drawn: the line is this much higher than the preview or the chip, twice.
    static let verticalPadding: CGFloat = 6
    /// The height of a file chip.
    static let chipHeight: CGFloat = 44
    /// The widest a file chip is.
    static let chipMaxWidth: CGFloat = 360
    /// The size of the icon in a chip.
    static let iconSize: CGFloat = 32
    /// The space between the edge of a chip and its icon, and between the icon and the text.
    static let chipInset: CGFloat = 8
    /// The radius of the corners of a preview and of a chip.
    static let cornerRadius: CGFloat = 6
    /// The width of the outline of a selected attachment.
    static let outlineWidth: CGFloat = 2
    /// What the text width is taken to be before the text view has one (a note shown at launch is styled before the window
    /// has laid anything out): wide enough that only an image's own size and the height cap limit it.
    static let unknownWidth: CGFloat = 10_000

    /// How high the line of an attachment whose preview or chip is `displayHeight` high is.
    static func lineHeight(forDisplayHeight displayHeight: CGFloat) -> CGFloat {
        displayHeight + 2 * verticalPadding
    }

    /// The size of the preview of an image of `pixelWidth` x `pixelHeight` pixels: as wide as the text (`availableWidth`) and
    /// at most `imageMaxHeight` high, in the proportions of the image, and never bigger than the image is. Whole points.
    static func imageSize(pixelWidth: Int, pixelHeight: Int, availableWidth: CGFloat) -> NSSize {
        let width = CGFloat(max(pixelWidth, 1))
        let height = CGFloat(max(pixelHeight, 1))
        let scale = min(1, availableWidth / width, imageMaxHeight / height)
        return NSSize(width: max((width * scale).rounded(), 1), height: max((height * scale).rounded(), 1))
    }

    /// The size of a chip: `chipHeight` high and at most `chipMaxWidth` wide, and no wider than the text.
    static func chipSize(availableWidth: CGFloat) -> NSSize {
        NSSize(width: max(min(chipMaxWidth, availableWidth), 1), height: chipHeight)
    }

    /// The size, in pixels of the longer side, that the thumbnail of a preview of `size` points is asked for on a screen of
    /// `scale` pixels to the point.
    static func previewPixelSize(for size: NSSize, scale: CGFloat) -> Int {
        Int((max(size.width, size.height) * max(scale, 1)).rounded(.up))
    }
}

/// Draws what an attachment line stands for: a preview or a chip, and the outline of a selected one (plan 5, task 4). The
/// layout manager calls it from `drawBackground`, with the rectangle that the line gives it. It is not on the main actor,
/// like the layout manager.
nonisolated enum AttachmentDrawing {
    /// Draws the attachment of `mark` in `rect`. `preview` is the decoded image of an image mark, or nil while it is on its
    /// way, when a tint stands in for it. `isSelected` draws the outline round it.
    static func draw(_ mark: AttachmentMark, in rect: NSRect, preview: NSImage?, isSelected: Bool) {
        guard rect.width > 0, rect.height > 0 else { return }
        switch mark.kind {
        case .image:
            drawPreview(preview, in: rect)
        case .file, .copying, .missing:
            drawChip(mark, in: rect)
        }
        if isSelected { drawOutline(around: rect) }
    }

    // MARK: Previews

    /// The image with rounded corners and a hairline round it, or the tint of a code block where it will be.
    private static func drawPreview(_ image: NSImage?, in rect: NSRect) {
        let radius = AttachmentMetrics.cornerRadius
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        guard let image else {
            CodeBlockColors.background.setFill()
            shape.fill()
            return
        }
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()

        let border = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        border.lineWidth = 1
        NSColor.separatorColor.setStroke()
        border.stroke()
    }

    // MARK: Chips

    /// A chip: the tint of a code block with the icon of the file at its left, and its name and, under it, its size, or
    /// "Copying…". A missing attachment says so, with the file's name under it when it has one.
    private static func drawChip(_ mark: AttachmentMark, in rect: NSRect) {
        let radius = AttachmentMetrics.cornerRadius
        CodeBlockColors.background.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        let inset = AttachmentMetrics.chipInset
        let iconSize = AttachmentMetrics.iconSize
        let iconRect = NSRect(
            x: rect.minX + inset, y: rect.minY + (rect.height - iconSize) / 2, width: iconSize, height: iconSize)
        drawIcon(of: mark, in: iconRect)

        let textX = iconRect.maxX + inset
        let textWidth = rect.maxX - inset - textX
        guard textWidth > 1 else { return }

        let title: String
        let subtitle: String?
        switch mark.kind {
        case .missing:
            title = "Missing attachment"
            subtitle = mark.fileName.isEmpty ? nil : mark.fileName
        case .copying:
            title = mark.fileName
            subtitle = "Copying\u{2026}"
        case .file, .image:
            title = mark.fileName
            subtitle = mark.byteSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        }

        let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let subtitleFont = NSFont.systemFont(ofSize: 11)
        let titleHeight = lineHeight(of: titleFont)
        let subtitleHeight = subtitle == nil ? 0 : lineHeight(of: subtitleFont)
        var y = rect.minY + (rect.height - titleHeight - subtitleHeight) / 2
        drawLine(
            title, font: titleFont, color: .labelColor,
            in: NSRect(x: textX, y: y, width: textWidth, height: titleHeight))
        y += titleHeight
        if let subtitle {
            drawLine(
                subtitle, font: subtitleFont, color: .secondaryLabelColor,
                in: NSRect(x: textX, y: y, width: textWidth, height: subtitleHeight))
        }
    }

    /// The icon of a chip: the Finder icon of the file (or of its type), and a warning symbol for a missing attachment.
    private static func drawIcon(of mark: AttachmentMark, in rect: NSRect) {
        if let icon = mark.icon, mark.kind != .missing {
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height * 0.7, weight: .regular, scale: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor]))
        guard
            let symbol = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        else { return }
        let size = symbol.size
        let target = NSRect(
            x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// The height of one line of text in `font`.
    private static func lineHeight(of font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// One line of `text`, cut short in the middle where it does not fit `rect`, which is one line high.
    private static func drawLine(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: style,
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    // MARK: Selection

    /// The outline of a selected attachment: `controlAccentColor`, `outlineWidth` wide, just outside `rect`.
    private static func drawOutline(around rect: NSRect) {
        let radius = AttachmentMetrics.cornerRadius + 1
        let outline = NSBezierPath(
            roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: radius, yRadius: radius)
        outline.lineWidth = AttachmentMetrics.outlineWidth
        NSColor.controlAccentColor.setStroke()
        outline.stroke()
    }
}
