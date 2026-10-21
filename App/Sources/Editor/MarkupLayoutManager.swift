import AppKit

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
///   of its code block (plan 4, task 5). The line break of the line is a glyph of its own and stays, and so does the last
///   character of the note when a fence line ends it: a line with no glyph but null ones is as high as the font, whatever
///   its paragraph style says (the character is clear, so nothing is drawn).
/// - **Code blocks are drawn behind their lines.** The lines of a fenced block carry a `CodeBlockMark`. `drawBackground`
///   fills the rounded, tinted rectangle that they make together, and the label with the block's language at its top
///   right, without changing anything in the text.
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
                isHidden = role == MarkerRole.hidden.rawValue || isFence
                runStart = run.location
                runEnd = NSMaxRange(run)
            }
            guard isHidden else { continue }
            // A line of null glyphs only has no height of its own: the typesetter does not look at its paragraph style,
            // so a closing fence that ends the note (no line break after it) was a full line. Its last character keeps its
            // glyph, which is as clear as the other characters of the line, and the line is as high as the style says.
            if isFence {
                switch Self.diagnosticsKeep {
                case .noteEnd: if character == storage.length - 1 { continue }
                case .first: if character == runStart { continue }
                case .last: if character == runEnd - 1 { continue }
                case .all: continue
                case .never: break
                }
            }
            if modified == nil { modified = Array(UnsafeBufferPointer(start: props, count: glyphRange.length)) }
            modified?[index] = .null
        }
        guard let modified else { return 0 }
        layoutManager.setGlyphs(
            glyphs, properties: modified, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    // MARK: Drawing

    /// Draws the tinted blocks and their labels behind the text, and then the rest of what is behind it (the tint of
    /// inline code and the selection). AppKit calls this on the main thread, for the glyphs of the area it redraws.
    nonisolated(unsafe) static var diagnosticsDrawsCodeBlocks = true
    enum DiagnosticsKeep { case noteEnd, first, last, all, never }
    nonisolated(unsafe) static var diagnosticsKeep = DiagnosticsKeep.noteEnd
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if Self.diagnosticsDrawsCodeBlocks { drawCodeBlocks(forGlyphRange: glyphsToShow, at: origin) }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
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
            case .hidden, .revealed, .fence:
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

    /// The share of the line's height that the symbol of a box is as high as.
    private static let checkboxScale: CGFloat = 0.85

    /// Draws the box of a checklist item in the place of its `[?]` at `characterRange`: the symbol is centred in the
    /// rectangle of the three characters and is `checkboxScale` of the line's height, in the accent colour. The symbol
    /// is made for each draw, so it has the accent colour and the appearance of the moment. `origin` is where the text
    /// container's origin is in the text view's coordinates.
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

        // The open box is one layer. The ticked one has two: the checkmark (first palette colour) on the filled square
        // (second), so that the tick shows against the fill and not as one more patch of the accent colour.
        let colors = isChecked ? [NSColor.white, NSColor.controlAccentColor] : [NSColor.controlAccentColor]
        let configuration = NSImage.SymbolConfiguration(
            pointSize: rect.height * Self.checkboxScale, weight: .medium, scale: .medium
        ).applying(NSImage.SymbolConfiguration(paletteColors: colors))
        let name = isChecked ? "checkmark.square.fill" : "square"
        guard
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(
                configuration)
        else { return }
        let size = symbol.size
        let target = NSRect(
            x: origin.x + rect.midX - size.width / 2, y: origin.y + rect.midY - size.height / 2, width: size.width,
            height: size.height)
        symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
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

    /// Fills `rect` with the block tint, with the top corners rounded when `roundsTop` and the bottom ones when
    /// `roundsBottom`. A corner that is not rounded is cut off by a clip: the rounded rectangle is made taller than `rect`
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
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The font and colour of a label, and its lean when the language was detected, for the note font size at
    /// `characterIndex`.
    private func labelAttributes(for mark: CodeBlockMark, at characterIndex: Int, in storage: NSTextStorage)
        -> [NSAttributedString.Key: Any]
    {
        let noteSize = (storage.attribute(.font, at: characterIndex, effectiveRange: nil) as? NSFont)?.pointSize ?? 13
        let size = max(noteSize - CodeBlockMetrics.labelSizeReduction, 7)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
            .foregroundColor: CodeBlockColors.label,
        ]
        if mark.isDetected { attributes[.obliqueness] = CodeBlockMetrics.labelObliqueness }
        return attributes
    }

    /// Draws the label of a block at its top right: `secondaryLabelColor`, two points smaller than the note font, and
    /// leaning when the language was detected. `right` is the right edge of the tinted block.
    private func drawLabel(_ label: BlockLabel, right: CGFloat, in storage: NSTextStorage) {
        let attributes = labelAttributes(for: label.mark, at: label.characterIndex, in: storage)
        let text = label.mark.name as NSString
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: right - CodeBlockMetrics.inset - size.width, y: label.fragmentTop + CodeBlockMetrics.labelTopOffset)
        text.draw(at: point, withAttributes: attributes)
    }
}
