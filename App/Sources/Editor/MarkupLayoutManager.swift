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
///   SF Symbol `square` (open) or `checkmark.square.fill` (ticked) in the accent colour is drawn in their rectangle,
///   which `NoteTextView` uses to find out whether a click is on the box.
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
        for index in 0..<glyphRange.length {
            let character = charIndexes[index]
            if character < runStart || character >= runEnd {
                var run = NSRange(location: 0, length: 0)
                let role = storage.attribute(.scratchMarker, at: character, effectiveRange: &run) as? String
                isHidden = role == MarkerRole.hidden.rawValue
                runStart = run.location
                runEnd = NSMaxRange(run)
            }
            guard isHidden else { continue }
            if modified == nil { modified = Array(UnsafeBufferPointer(start: props, count: glyphRange.length)) }
            modified?[index] = .null
        }
        guard let modified else { return 0 }
        layoutManager.setGlyphs(
            glyphs, properties: modified, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    // MARK: Drawing

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
            case .hidden, .revealed:
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

        let configuration = NSImage.SymbolConfiguration(
            pointSize: rect.height * Self.checkboxScale, weight: .regular, scale: .medium
        ).applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.controlAccentColor]))
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
}
