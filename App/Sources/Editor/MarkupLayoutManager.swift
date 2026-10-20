import AppKit

/// The editor's layout manager. It hides markers and draws what stands in for them, without changing a character of
/// the text (spec §6.4, docs/decisions/0001).
///
/// - **Hidden markers have no glyph.** It is its own delegate, and `layoutManager(_:shouldGenerateGlyphs:…)` gives
///   every character whose `scratchMarker` role is `hidden` the `.null` glyph property, so the `**` of a bold run takes
///   no room and the text between the stars is laid out as if they were not there. The caret still stops at each
///   hidden character, which is why `MarkupStyler` shows the markers of a run while the caret or selection touches it.
/// - **Bullets are drawn over their `-`.** The `-` of a bullet is transparent and a `•` in the accent colour is drawn
///   where it is. (Plan 3, task 4 draws the boxes of checklists the same way.)
///
/// `TextViewFactory` makes it the layout manager of the editor and sets it as its own delegate once the text view is
/// made, because the text view sets its own delegate when it is created. The delegate of a layout manager is weak, so
/// the manager is its own delegate for free.
///
/// **Isolation.** AppKit does not annotate `NSLayoutManager` or its delegate for the main actor, and the app's default
/// isolation is the main actor, which would make a subclass main-actor and its inherited `init()` mismatch the
/// superclass's. So the class is `nonisolated` (and `@unchecked Sendable`, which lets the drawing below go through
/// `MainActor.assumeIsolated`: AppKit lays out and draws on the main thread, and nothing here is shared).
nonisolated final class MarkupLayoutManager: NSLayoutManager, NSLayoutManagerDelegate, @unchecked Sendable {
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

    /// Draws the text as the superclass does, then the bullets over the glyphs that `MarkupStyler` made transparent.
    /// AppKit calls this on the main thread.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        MainActor.assumeIsolated {
            drawBullets(forGlyphRange: glyphsToShow, at: origin)
        }
    }

    @MainActor
    private func drawBullets(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.scratchMarker, in: characters, options: []) { value, range, _ in
            guard let role = value as? String, role == MarkerRole.bullet.rawValue else { return }
            drawBullet(over: range, in: storage, at: origin)
        }
    }

    /// Draws a `•` in the accent colour in the place of the `-` at `characterRange`: centred in its advance, on the
    /// baseline the `-` is on. `origin` is where the text container's origin is in the text view's coordinates.
    @MainActor
    private func drawBullet(over characterRange: NSRange, in storage: NSTextStorage, at origin: NSPoint) {
        let glyphRange = self.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }
        let glyph = glyphRange.location
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let location = self.location(forGlyphAt: glyph)
        let font =
            storage.attribute(.font, at: characterRange.location, effectiveRange: nil) as? NSFont
            ?? NoteTextView.noteFont
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.controlAccentColor]
        let advance = ("-" as NSString).size(withAttributes: attributes).width
        let bullet = "\u{2022}" as NSString
        let width = bullet.size(withAttributes: attributes).width
        let point = NSPoint(
            x: origin.x + fragment.minX + location.x + (advance - width) / 2,
            y: origin.y + fragment.minY + location.y - font.ascender)
        bullet.draw(at: point, withAttributes: attributes)
    }
}
