import AppKit

/// THROWAWAY, branch spike/textkit only (plan 1 task 10, ADR 0001). Prototypes hiding the `**` markers of bold runs
/// without changing the text, on each TextKit. The launch argument `-ScratchSpikeHide <technique>` switches it on:
///
/// - `glyphs`, TextKit 1 only: an `NSLayoutManagerDelegate` gives the marker glyphs the `.null` glyph property.
/// - `paragraph`, TextKit 2 only: an `NSTextContentStorageDelegate` hands out paragraphs that lack the markers.
/// - `tiny`, either: the markers get a 0.1 pt font and the clear colour.
///
/// The text between the markers is set in bold, whatever the technique.
@MainActor
final class MarkerHidingSpike: NSObject, @preconcurrency NSLayoutManagerDelegate,
    @preconcurrency NSTextContentStorageDelegate
{
    enum Technique: String {
        case glyphs
        case paragraph
        case tiny
    }

    /// One `**bold**` run: the opening marker, the bold text and the closing marker.
    struct Run {
        var open: NSRange
        var content: NSRange
        var close: NSRange
    }

    /// The delegates of a text view are weak, so the prototype in use is kept here.
    private static var current: MarkerHidingSpike?

    let technique: Technique
    private var hiddenCharacterIndexes: Set<Int> = []

    init(technique: Technique) {
        self.technique = technique
    }

    /// The technique that `-ScratchSpikeHide` asks for, if any.
    static var requestedTechnique: Technique? {
        UserDefaults.standard.string(forKey: "ScratchSpikeHide").flatMap(Technique.init(rawValue:))
    }

    /// Installs the prototype the launch argument asks for. Call it before the text is loaded.
    static func installIfRequested(on textView: NoteTextView) {
        guard let technique = requestedTechnique else { return }
        current = install(technique, on: textView)
    }

    /// Applies the prototype the launch argument asks for to the text that is loaded. Call it after `load`.
    static func applyIfRequested(to textView: NoteTextView) {
        current?.apply(to: textView)
    }

    /// Makes a prototype of `technique` and installs its delegate on `textView`.
    static func install(_ technique: Technique, on textView: NoteTextView) -> MarkerHidingSpike {
        let spike = MarkerHidingSpike(technique: technique)
        switch technique {
        case .glyphs:
            // Only on a TextKit 1 view: `layoutManager` would turn a TextKit 2 view into a TextKit 1 view.
            if textView.textLayoutManager == nil { textView.layoutManager?.delegate = spike }
        case .paragraph:
            textView.textContentStorage?.delegate = spike
        case .tiny:
            break
        }
        return spike
    }

    static func runs(in text: String) -> [Run] {
        let regex = try! NSRegularExpression(pattern: "\\*\\*([^*\\n]+)\\*\\*")
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, range: range).map { match in
            let content = match.range(at: 1)
            return Run(
                open: NSRange(location: match.range.location, length: 2), content: content,
                close: NSRange(location: NSMaxRange(content), length: 2))
        }
    }

    /// Sets the bold runs of the loaded text in bold, and hides their markers the way the technique does.
    func apply(to textView: NoteTextView) {
        guard let storage = textView.textStorage else { return }
        let runs = Self.runs(in: storage.string)
        hiddenCharacterIndexes = []
        let bold = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        let tiny = NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular)
        storage.beginEditing()
        for run in runs {
            storage.addAttribute(.font, value: bold, range: run.content)
            for marker in [run.open, run.close] {
                for index in marker.location..<NSMaxRange(marker) { hiddenCharacterIndexes.insert(index) }
                if technique == .tiny {
                    storage.addAttributes([.font: tiny, .foregroundColor: NSColor.clear], range: marker)
                }
            }
        }
        storage.endEditing()
    }

    // MARK: NSLayoutManagerDelegate (TextKit 1)

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont, forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard technique == .glyphs, !hiddenCharacterIndexes.isEmpty else { return 0 }
        var changed = false
        var modified = [NSLayoutManager.GlyphProperty](repeating: [], count: glyphRange.length)
        for index in 0..<glyphRange.length {
            modified[index] = props[index]
            if hiddenCharacterIndexes.contains(charIndexes[index]) {
                modified[index] = .null
                changed = true
            }
        }
        guard changed else { return 0 }
        layoutManager.setGlyphs(
            glyphs, properties: modified, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    // MARK: NSTextContentStorageDelegate (TextKit 2)

    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange)
        -> NSTextParagraph?
    {
        guard technique == .paragraph, let storage = textContentStorage.textStorage else { return nil }
        let paragraph = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let runs = Self.runs(in: paragraph.string)
        guard !runs.isEmpty else { return nil }
        for run in runs.reversed() {
            paragraph.deleteCharacters(in: run.close)
            paragraph.deleteCharacters(in: run.open)
        }
        return NSTextParagraph(attributedString: paragraph)
    }
}
