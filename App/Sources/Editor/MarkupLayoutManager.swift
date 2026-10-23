import AppKit
import ScratchCore

/// The editor's layout manager. It hides markers and draws what stands in for them, without changing a character of
/// the text (spec §6.4, docs/decisions/0001).
///
/// - **Hidden markers have no glyph.** It is its own delegate, and `layoutManager(_:shouldGenerateGlyphs:…)` gives
///   every character whose `scratchMarker` role is `hidden` the `.null` glyph property, so the `**` of a bold run takes
///   no room and the text between the stars is laid out as if they were not there. The caret still stops at each
///   hidden character, which is why `MarkupStyler` shows the markers of a run while the caret or selection touches it.
/// - **Bullets are drawn over their `-`.** The `-` of a bullet is transparent and a `•` in the accent colour is drawn
///   where it is.
/// - **Checkboxes are drawn over their `[?]`.** The three characters of a checklist item's box are transparent, and the
///   SF Symbol `square` (open) or `checkmark.square.fill` (ticked: a white checkmark on a square filled with the accent
///   colour) is drawn in their rectangle, which `NoteTextView` uses to find out whether a click is on the box.
/// - **Fence lines have no glyphs either.** The characters of a fence line (role `fence`) are null glyphs like a hidden
///   marker, and the paragraph style of the line is 6 pt high, so that the line is the padding at the top or the bottom
///   of its code block (plan 4, task 5). The first character of the line keeps its glyph, which is clear: null glyphs
///   take no line fragment of their own, they sit at the end of the line above (see `shouldGenerateGlyphs`).
/// - **Code blocks are drawn behind their lines.** The lines of a fenced block carry a `CodeBlockMark`. `drawBackground`
///   fills the rounded, tinted rectangle that they make together, with a hairline border inside its edge (plan 6 task 7),
///   and the label with the block's language at its top right, without changing anything in the text.
/// - **Inline code is a pill.** The characters of inline code carry `scratchInlineCode` and no background colour:
///   `drawBackground` fills a rounded rectangle behind each line of them, 2 pt wider than the text on each side (plan 6 task 7).
///
/// - **Attachments are drawn over their token lines.** The characters of a token line `[[attachment:<id>]]` but the first
///   are null glyphs, like a fence line's, and its paragraph is as high as what is drawn on it. `drawBackground` draws the
///   preview or the chip in the line's rectangle, from the line's `AttachmentMark`, and the outline of a selected one
///   (plan 5, task 4). A preview is drawn from `previews` when it is decoded, and a tint stands in for it until then.
///
/// `TextViewFactory` makes it the layout manager of the editor and sets it as its own delegate once the text view is
/// made, because the text view sets its own delegate when it is created. The delegate of a layout manager is weak, so
/// the manager is its own delegate for free.
///
/// **Isolation.** AppKit does not annotate `NSLayoutManager` or its delegate for the main actor, and the app's default
/// isolation is the main actor, which would make a subclass main-actor and its inherited `init()` mismatch the
/// superclass's. So the class is `nonisolated`, and so is everything in it: AppKit lays out and draws on the main
/// thread, and the text storage, layout manager and drawing calls used here are not main-actor types either.
nonisolated final class MarkupLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    // MARK: Attachments

    /// The decoded previews of the images in the note. `MarkupStyler` sets it. The layout manager draws what is cached and
    /// asks for what is not (`AttachmentPreviews.request`), and the styler invalidates the display of the line when the
    /// answer arrives (`AttachmentPreviews.onChange`).
    var previews: AttachmentPreviews?

    /// True while the note has an attachment line, which `MarkupStyler` keeps current. A note without one is not looked
    /// through for them every time a line is drawn.
    var hasAttachments = false

    /// The range that is selected, which `MarkupStyler` keeps current: an attachment whose token it touches is drawn with
    /// an outline. Not read from the text view, which is main-actor isolated and this class is not.
    var attachmentSelection = NSRange(location: 0, length: 0)

    // MARK: Glyphs

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont, forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return 0 }
        var modified: [NSLayoutManager.GlyphProperty]?
        // The characters of one attribute run share a role, so the attribute is read once per run and not per glyph.
        var runStart = 0
        var runEnd = 0
        var isHidden = false
        var isFence = false
        for index in 0..<glyphRange.length {
            let character = charIndexes[index]
            if character < runStart || character >= runEnd {
                var run = NSRange(location: 0, length: 0)
                let role = storage.attribute(.scratchMarker, at: character, effectiveRange: &run) as? String
                isFence = role == MarkerRole.fence.rawValue
                // A token line's characters but the first have no glyph either: the first has no role and keeps its (clear)
                // glyph, which is what gives the line its own line fragment.
                isHidden = role == MarkerRole.hidden.rawValue || isFence || role == MarkerRole.attachment.rawValue
                runStart = run.location
                runEnd = NSMaxRange(run)
            }
            guard isHidden else { continue }
            // A null glyph is zero wide and sits on the line fragment before it, whatever line it is on: a fence line of
            // null glyphs only has no line fragment of its own (its characters end up on the end of the line above, and
            // a closing fence that ends the note has no padding at all), and its line break is a line of its own that
            // is 6 pt but that the caret and a click cannot tell from the line above. The first character of a fence
            // line keeps its glyph, which is clear (`MarkupAppearance.markerAttributes`), so that the line starts a
            // fragment of its own, as high as its paragraph style says.
            if isFence, character == runStart { continue }
            if modified == nil { modified = Array(UnsafeBufferPointer(start: props, count: glyphRange.length)) }
            modified?[index] = .null
        }
        guard let modified else { return 0 }
        layoutManager.setGlyphs(
            glyphs, properties: modified, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    // MARK: Drawing

    /// Draws the tinted blocks and their labels behind the text, then the rest of what is behind it (the tint of inline
    /// code and the selection), and over that the previews and chips of the attachments. AppKit calls this on the main
    /// thread, for the glyphs of the area it redraws.
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawCodeBlocks(forGlyphRange: glyphsToShow, at: origin)
        drawInlineCode(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        // After the superclass, which draws the selection: what the selection highlights of a token line (its first
        // character, 8 pt wide) is under the preview.
        drawAttachments(forGlyphRange: glyphsToShow, at: origin)
    }

    /// Draws the text as the superclass does, then the bullets and the boxes over the glyphs that `MarkupStyler` made
    /// transparent. AppKit calls this on the main thread.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawMarkerReplacements(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawMarkerReplacements(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.scratchMarker, in: characters, options: []) { value, range, _ in
            guard let raw = value as? String, let role = MarkerRole(rawValue: raw) else { return }
            switch role {
            case .bullet:
                drawBullet(over: range, in: storage, at: origin)
            case .checkboxOpen:
                drawCheckbox(isChecked: false, over: range, in: storage, at: origin)
            case .checkboxChecked:
                drawCheckbox(isChecked: true, over: range, in: storage, at: origin)
            case .hidden, .revealed, .fence, .attachment:
                break
            }
        }
    }

    /// Draws a `•` in the accent colour in the place of the `-` at `characterRange`: centred in its advance, on the
    /// baseline the `-` is on. `origin` is where the text container's origin is in the text view's coordinates.
    private func drawBullet(over characterRange: NSRange, in storage: NSTextStorage, at origin: NSPoint) {
        let glyphRange = self.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }
        let glyph = glyphRange.location
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let location = self.location(forGlyphAt: glyph)
        let font =
            storage.attribute(.font, at: characterRange.location, effectiveRange: nil) as? NSFont
            ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.controlAccentColor]
        let advance = ("-" as NSString).size(withAttributes: attributes).width
        let bullet = "\u{2022}" as NSString
        let width = bullet.size(withAttributes: attributes).width
        let point = NSPoint(
            x: origin.x + fragment.minX + location.x + (advance - width) / 2,
            y: origin.y + fragment.minY + location.y - font.ascender)
        bullet.draw(at: point, withAttributes: attributes)
    }

    /// The share of the font's line height that the symbol of a box is as high as.
    private static let checkboxScale: CGFloat = 0.85

    /// The point size of the symbol of a box for text in `font`: `checkboxScale` of the font's own line height. Not of the
    /// line fragment's height, which includes the spacing after the line (plan 6 task 7): the box would grow with it.
    func checkboxPointSize(for font: NSFont) -> CGFloat {
        defaultLineHeight(for: font) * Self.checkboxScale
    }

    /// Draws the box of a checklist item in the place of its `[?]` at `characterRange`: the symbol is centred on the three
    /// characters, in the middle of the font's line, and is `checkboxScale` of the font's line height. An open box is
    /// `secondaryLabelColor`, a grey, and a ticked one is the accent colour with a white tick (mockup B). The symbol is made
    /// for each draw, so it has the colours and the appearance of the moment. `origin` is where the text container's origin
    /// is in the text view's coordinates.
    private func drawCheckbox(
        isChecked: Bool, over characterRange: NSRange, in storage: NSTextStorage, at origin: NSPoint
    ) {
        // The whole marker, also when only a part of it is in the range that is drawn.
        var marker = characterRange
        _ = storage.attribute(
            .scratchMarker, at: characterRange.location, longestEffectiveRange: &marker,
            in: NSRange(location: 0, length: storage.length))
        let glyphRange = self.glyphRange(forCharacterRange: marker, actualCharacterRange: nil)
        guard glyphRange.length > 0,
            let container = textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil)
        else { return }
        let rect = boundingRect(forGlyphRange: glyphRange, in: container)
        guard rect.width > 0, rect.height > 0 else { return }
        let font =
            storage.attribute(.font, at: marker.location, effectiveRange: nil) as? NSFont
            ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // The middle of the font's line, from the baseline: the fragment is as high as the line and the spacing after it.
        let fragment = lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let baseline = fragment.minY + location(forGlyphAt: glyphRange.location).y
        let centerY = baseline - (font.ascender + font.descender) / 2

        // The open box is one layer. The ticked one has two: the checkmark (first palette colour) on the filled square
        // (second), so that the tick shows against the fill and not as one more patch of the accent colour. The grey is
        // resolved here, in the appearance that is being drawn.
        let grey = NSColor(cgColor: NSColor.secondaryLabelColor.cgColor) ?? NSColor.secondaryLabelColor
        let colors = isChecked ? [NSColor.white, NSColor.controlAccentColor] : [grey]
        let configuration = NSImage.SymbolConfiguration(
            pointSize: checkboxPointSize(for: font), weight: .medium, scale: .medium
        ).applying(NSImage.SymbolConfiguration(paletteColors: colors))
        let name = isChecked ? "checkmark.square.fill" : "square"
        guard
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(
                configuration)
        else { return }
        let size = symbol.size
        let target = NSRect(
            x: origin.x + rect.midX - size.width / 2, y: origin.y + centerY - size.height / 2, width: size.width,
            height: size.height)
        symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    // MARK: Inline code

    /// Fills a pill behind each line of each run of inline code that has a glyph in `glyphsToShow`: a rounded rectangle
    /// `InlineCodeMetrics.horizontalPadding` wider than the characters on each side, as high as the font's line (its ascent
    /// and descent, and `InlineCodeMetrics.verticalPadding` more), from the baseline and not from the line fragment, which has
    /// the spacing after the line in it. Drawn before the selection, which is over it. `origin` is where the text container's
    /// origin is in the text view's coordinates.
    private func drawInlineCode(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0, glyphsToShow.length > 0 else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var runs: [NSRange] = []
        storage.enumerateAttribute(.scratchInlineCode, in: characters, options: []) { value, range, _ in
            guard value != nil else { return }
            // The whole run, also when only a part of it is in the range that is drawn: the pill is one shape.
            var whole = range
            _ = storage.attribute(
                .scratchInlineCode, at: range.location, longestEffectiveRange: &whole,
                in: NSRange(location: 0, length: storage.length))
            if runs.last != whole { runs.append(whole) }
        }
        guard !runs.isEmpty else { return }
        CodeBlockColors.background.setFill()
        for run in runs {
            let glyphs = glyphRange(forCharacterRange: run, actualCharacterRange: nil)
            guard glyphs.length > 0, let container = textContainer(forGlyphAt: glyphs.location, effectiveRange: nil)
            else { continue }
            enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, lineGlyphs, _ in
                let part = NSIntersectionRange(glyphs, lineGlyphs)
                guard part.length > 0 else { return }
                let box = self.boundingRect(forGlyphRange: part, in: container)
                guard box.width > 0 else { return }
                let character = self.characterIndexForGlyph(at: part.location)
                let font =
                    storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont
                    ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                let baseline = fragment.minY + self.location(forGlyphAt: part.location).y
                // Not above the line fragment: a redraw of the line above would not redraw what reaches into it.
                let top = max(baseline - font.ascender - InlineCodeMetrics.verticalPadding, fragment.minY)
                let bottom = baseline - font.descender + InlineCodeMetrics.verticalPadding
                let pill = NSRect(
                    x: origin.x + box.minX - InlineCodeMetrics.horizontalPadding, y: origin.y + top,
                    width: box.width + 2 * InlineCodeMetrics.horizontalPadding, height: bottom - top)
                NSBezierPath(
                    roundedRect: pill, xRadius: InlineCodeMetrics.cornerRadius, yRadius: InlineCodeMetrics.cornerRadius
                ).fill()
            }
        }
    }

    // MARK: Attachments drawing

    /// Draws the preview or the chip of each attachment line that has a glyph in `glyphsToShow`, in the rectangle that
    /// `attachmentRect(forTokenAt:)` gives, moved by `origin` (where the text container's origin is in the text view's
    /// coordinates). An image that is not decoded yet is a tint, and is asked for: whoever set `previews.onChange`
    /// invalidates the display of its line when it arrives. A line whose token is touched by the selection has the outline.
    private func drawAttachments(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard hasAttachments, let storage = textStorage, storage.length > 0, glyphsToShow.length > 0 else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let text = storage.string as NSString
        storage.enumerateAttribute(.scratchAttachment, in: characters, options: []) { value, range, _ in
            guard let mark = value as? AttachmentMark else { return }
            // A run that is cut to the characters being drawn can start inside the line: the token is where its paragraph
            // starts.
            let start = text.paragraphRange(for: NSRange(location: range.location, length: 0)).location
            guard let rect = attachmentRect(forTokenAt: start) else { return }
            var preview: NSImage?
            if mark.kind == .image, let url = mark.fileURL, let previews {
                preview = previews.cachedImage(forID: mark.id, minPixelSize: 1)
                if preview == nil { previews.request(for: url, id: mark.id, maxPixelSize: mark.previewPixelSize) }
            }
            let token = NSRange(location: start, length: AttachmentToken.lineLength)
            let isSelected = NSIntersectionRange(attachmentSelection, token).length > 0
            AttachmentDrawing.draw(
                mark, in: rect.offsetBy(dx: origin.x, dy: origin.y), preview: preview, isSelected: isSelected)
        }
    }

    /// The rectangle that the preview or chip of the attachment whose token line starts at `location` is drawn in, in the
    /// coordinates of the text container (add the text view's `textContainerOrigin` for the view's): the line fragment's
    /// width less the padding on the left, and `AttachmentMetrics.verticalPadding` below its top, as big as the line's
    /// `AttachmentMark` says. Nil when `location` is not in an attachment line.
    ///
    /// It lays out the line, and what is above it that has not been laid out yet. `drawAttachments` draws in this rectangle
    /// and a click on an attachment asks for it, so that what is clicked is what is drawn.
    func attachmentRect(forTokenAt location: Int) -> NSRect? {
        guard let storage = textStorage, location >= 0, location < storage.length,
            let mark = storage.attribute(.scratchAttachment, at: location, effectiveRange: nil) as? AttachmentMark
        else { return nil }
        let glyph = glyphIndexForCharacter(at: location)
        guard let container = textContainer(forGlyphAt: glyph, effectiveRange: nil) else { return nil }
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return NSRect(
            x: fragment.minX + container.lineFragmentPadding, y: fragment.minY + AttachmentMetrics.verticalPadding,
            width: mark.displaySize.width, height: mark.displaySize.height)
    }

    // MARK: Code blocks

    /// The run of line fragments of one block that `drawCodeBlocks` has seen so far: filled in one piece, so that there is
    /// no seam between two lines, and with round corners only where the block begins or ends.
    nonisolated private struct BlockRun {
        var rect: NSRect
        var roundsTop: Bool
        var lastPart: CodeBlockPart
    }

    /// A label to draw: the opening fence line's mark and where that line is.
    nonisolated private struct BlockLabel {
        var mark: CodeBlockMark
        var fragmentTop: CGFloat
        var characterIndex: Int
    }

    /// Fills the part of each code block that is in `glyphsToShow`, then draws the labels of the blocks whose top is in
    /// it or just above it. `origin` is where the text container's origin is in the text view's coordinates.
    ///
    /// The tint is a rounded rectangle from the opening fence line to the closing one, as wide as the text container less
    /// its line fragment padding on each side (so that the tint is as wide as the text it holds plus the block's inset).
    /// It is drawn line fragment by line fragment from what is laid out, never from the block's end: the end of a block of
    /// thousands of lines would have to be laid out first.
    private func drawCodeBlocks(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0, glyphsToShow.length > 0,
            let container = textContainer(forGlyphAt: glyphsToShow.location, effectiveRange: nil)
        else { return }
        let padding = container.lineFragmentPadding
        let left = origin.x + padding
        let width = container.size.width - 2 * padding
        guard width > 0 else { return }

        var run: BlockRun?
        var labels: [BlockLabel] = []
        func flush() {
            guard let finished = run else { return }
            fillBlock(finished.rect, roundsTop: finished.roundsTop, roundsBottom: finished.lastPart == .closing)
            run = nil
        }

        var glyph = glyphsToShow.location
        let end = NSMaxRange(glyphsToShow)
        var isFirst = true
        while glyph < end {
            var lineGlyphs = NSRange(location: 0, length: 0)
            let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineGlyphs)
            let character = characterIndexForGlyph(at: glyph)
            let mark = storage.attribute(.scratchCodeBlock, at: character, effectiveRange: nil) as? CodeBlockMark
            let band = NSRect(x: left, y: origin.y + fragment.minY, width: width, height: fragment.height)

            if isFirst, let mark, mark.part != .opening {
                // The first line to draw is below the top of its block. The label overlaps the first line of code, so it
                // is drawn again with it.
                if let opening = openingFence(above: character, in: storage) {
                    labels.append(
                        BlockLabel(
                            mark: opening.mark, fragmentTop: origin.y + opening.fragment.minY,
                            characterIndex: opening.characterIndex))
                }
            }
            isFirst = false

            if let mark {
                if let current = run, mark.part == .opening, current.lastPart != .opening {
                    flush()
                } else if let current = run, current.lastPart == .closing, mark.part != .closing {
                    flush()
                }
                if var current = run {
                    current.rect = current.rect.union(band)
                    current.lastPart = mark.part
                    run = current
                } else {
                    run = BlockRun(rect: band, roundsTop: mark.part == .opening, lastPart: mark.part)
                    if mark.part == .opening, !mark.name.isEmpty {
                        labels.append(
                            BlockLabel(mark: mark, fragmentTop: band.minY, characterIndex: character))
                    }
                }
            } else {
                flush()
            }
            glyph = max(NSMaxRange(lineGlyphs), glyph + 1)
        }
        flush()

        for label in labels {
            drawLabel(label, right: left + width, in: storage)
        }
    }

    /// The opening fence line of the block that the paragraph holding `character` is in, when the paragraph is the first
    /// line after it (the only line the label reaches into): its mark, its character index and its line fragment.
    private func openingFence(
        above character: Int, in storage: NSTextStorage
    ) -> (mark: CodeBlockMark, characterIndex: Int, fragment: NSRect)? {
        let text = storage.string as NSString
        let paragraphStart = text.paragraphRange(for: NSRange(location: character, length: 0)).location
        guard paragraphStart > 0 else { return nil }
        let openingStart = text.paragraphRange(for: NSRange(location: paragraphStart - 1, length: 0)).location
        guard let mark = storage.attribute(.scratchCodeBlock, at: openingStart, effectiveRange: nil) as? CodeBlockMark,
            mark.part == .opening, !mark.name.isEmpty
        else { return nil }
        let glyph = glyphIndexForCharacter(at: openingStart)
        return (mark, openingStart, lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil))
    }

    /// Fills `rect` with the block tint and a hairline border, with the top corners rounded when `roundsTop` and the
    /// bottom ones when `roundsBottom`. A corner that is not rounded is cut off by a clip: the rounded rectangle is made taller than `rect`
    /// on that side, so that its corner lies outside it.
    private func fillBlock(_ rect: NSRect, roundsTop: Bool, roundsBottom: Bool) {
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = CodeBlockMetrics.cornerRadius
        var shape = rect
        if !roundsTop {
            shape.origin.y -= radius
            shape.size.height += radius
        }
        if !roundsBottom { shape.size.height += radius }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        CodeBlockColors.background.setFill()
        NSBezierPath(roundedRect: shape, xRadius: radius, yRadius: radius).fill()
        // The hairline is inside the edge of the tint, and drawn on the same shape: the edges that are cut off by the clip
        // (the top of a block that goes on above, the bottom of one that goes on below) leave no line across the block.
        let inset = CodeBlockMetrics.borderWidth / 2
        let outline = NSBezierPath(
            roundedRect: shape.insetBy(dx: inset, dy: inset), xRadius: radius - inset, yRadius: radius - inset)
        outline.lineWidth = CodeBlockMetrics.borderWidth
        CodeBlockColors.border.setStroke()
        outline.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The font and colour of a label, and its lean when the language was detected, for the note font size at
    /// `characterIndex`.
    private func labelAttributes(for mark: CodeBlockMark, at characterIndex: Int, in storage: NSTextStorage)
        -> [NSAttributedString.Key: Any]
    {
        let noteSize = (storage.attribute(.font, at: characterIndex, effectiveRange: nil) as? NSFont)?.pointSize ?? 13
        var attributes: [NSAttributedString.Key: Any] = [
            .font: CodeBlockMetrics.labelFont(noteSize: noteSize),
            .foregroundColor: CodeBlockColors.label,
        ]
        if mark.isDetected { attributes[.obliqueness] = CodeBlockMetrics.labelObliqueness }
        return attributes
    }

    /// The rectangle of a label drawn with `attributes`, from where its block's opening fence line is: `right` is the
    /// right edge of the tinted block, and the label ends one inset from it. `drawLabel` draws in this rectangle and
    /// `labelRect(forBlockAt:)` answers it, so that what is clicked is what is drawn.
    private func labelFrame(
        of name: String, attributes: [NSAttributedString.Key: Any], fragmentTop: CGFloat, right: CGFloat
    ) -> NSRect {
        let size = (name as NSString).size(withAttributes: attributes)
        return NSRect(
            x: right - CodeBlockMetrics.inset - size.width, y: fragmentTop + CodeBlockMetrics.labelTopOffset,
            width: size.width, height: size.height)
    }

    /// Draws the label of a block at its top right: `secondaryLabelColor`, two points smaller than the note font, and
    /// leaning when the language was detected. `right` is the right edge of the tinted block.
    private func drawLabel(_ label: BlockLabel, right: CGFloat, in storage: NSTextStorage) {
        let attributes = labelAttributes(for: label.mark, at: label.characterIndex, in: storage)
        let frame = labelFrame(
            of: label.mark.name, attributes: attributes, fragmentTop: label.fragmentTop, right: right)
        (label.mark.name as NSString).draw(at: frame.origin, withAttributes: attributes)
    }

    /// The rectangle that the label of the block whose opening fence line starts at `location` is drawn in, in the
    /// coordinates of the text container (add the text view's `textContainerOrigin` for the view's). Nil when there is
    /// no label to click: `location` is not the start of an opening fence line, or the block has no name to show (a
    /// fence with no name and no detected language).
    ///
    /// It lays out the opening fence line, and what is above it that has not been laid out yet. A click calls it for
    /// the block that is under the mouse only, never for every block of the note.
    func labelRect(forBlockAt location: Int) -> NSRect? {
        guard let storage = textStorage, location >= 0, location < storage.length,
            let mark = storage.attribute(.scratchCodeBlock, at: location, effectiveRange: nil) as? CodeBlockMark,
            mark.part == .opening, !mark.name.isEmpty
        else { return nil }
        let glyph = glyphIndexForCharacter(at: location)
        guard let container = textContainer(forGlyphAt: glyph, effectiveRange: nil) else { return nil }
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        // The tint is as wide as the text container less its padding on each side (`drawCodeBlocks`).
        let right = container.size.width - container.lineFragmentPadding
        let attributes = labelAttributes(for: mark, at: location, in: storage)
        return labelFrame(of: mark.name, attributes: attributes, fragmentTop: fragment.minY, right: right)
    }
}
