import AppKit

/// A 1 x 1 point view that publishes the editor's state to UI tests, which cannot see the font size or how far a note
/// is scrolled. It is an accessibility element with the identifier `AccessibilityID.debugState` and a JSON string as
/// its value, for example `{"fontSize":13,"pendingHighlights":0,"pendingPastes":0,"readOnly":false,"scrollAnchor":0,"scrollY":0,"topInset":0}`.
///
/// It draws nothing, takes no clicks and exists only in an isolated data directory (`AppDelegate` asks the editor to
/// install it), so a normal launch has no such view and a screenshot shows nothing of it. The value is computed when
/// something asks for it, so it is always current and costs nothing while nobody reads it (the performance tests run
/// isolated too).
final class DebugStateElement: NSView {
    /// The state to publish. Read each time the element's value is asked for.
    var state: (() -> [String: Any])?

    /// A view of 1 x 1 point: `frame`'s size is ignored.
    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: frameRect.origin, size: NSSize(width: 1, height: 1)))
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityIdentifier(AccessibilityID.debugState)
        setAccessibilityLabel("Debug state")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DebugStateElement is created in code")
    }

    /// Never the target of a click: the view is only for the accessibility tree.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func accessibilityValue() -> Any? {
        let object = state?() ?? [:]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
