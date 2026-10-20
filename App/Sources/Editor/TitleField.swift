import AppKit
import ScratchCore

/// The note's optional title: a borderless single-line text field above the editor's text (spec §6.4). It shows the
/// title in bold, three points larger than the text, and a dimmed "Untitled" while it is empty. It does not scroll with
/// the text. `EditorViewController` places it and reports what is typed in it.
final class TitleField: NSTextField {
    /// How much larger than the note text the title is, in points.
    static let extraSize: Double = 3

    /// The title font for a note font of `noteSize` points: bold SF Mono, three points larger (spec §6.4: one font,
    /// emphasis from weight).
    static func titleFont(noteSize: Double) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: CGFloat(noteSize + extraSize), weight: .bold)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        isEditable = true
        isSelectable = true
        // One line that scrolls while it is edited and is cut off with an ellipsis otherwise, never wrapped.
        cell?.isScrollable = true
        cell?.wraps = false
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        textColor = .textColor
        // The field is as wide as the editor and as tall as its text.
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setAccessibilityIdentifier(AccessibilityID.titleField)
        setAccessibilityLabel("Title")
        applyFontSize(FontSize.standard)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TitleField is created in code")
    }

    /// Sets the title font, and the placeholder's, for a note font of `noteSize` points.
    func applyFontSize(_ noteSize: Double) {
        let titleFont = Self.titleFont(noteSize: noteSize)
        font = titleFont
        placeholderAttributedString = NSAttributedString(
            string: "Untitled", attributes: [.font: titleFont, .foregroundColor: NSColor.placeholderTextColor])
    }
}
