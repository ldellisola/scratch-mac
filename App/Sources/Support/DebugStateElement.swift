import AppKit

/// A 1 x 1 point view that publishes the editor's state to UI tests, which cannot see the font size or how far a note
/// is scrolled. It is an accessibility element with the identifier `AccessibilityID.debugState` and a JSON string as
/// its value, for example `{"attachments":[],"fontSize":13,"launchTimes":[],"pendingHighlights":0,"pendingPastes":0,"pendingPreviews":0,"readOnly":false,"scrollAnchor":0,"scrollY":0,"topInset":0}`.
/// `launchTimes` is not the editor's: it is the newest 20 records of the launch log, newest first (`LaunchTimer.debugRecords`),
/// empty until the log has been written after the first frame. `firstResponder` says which part of the window has the
/// keyboard (`firstResponderName(in:)`).
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
        var object = state?() ?? [:]
        object["launchTimes"] = LaunchTimer.debugRecords()
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

extension DebugStateElement {
    /// Which part of the window has the keyboard, for the UI tests that follow Tab (plan 6 task 8, the key view loop): `editor`
    /// (the note's text), `title`, `search` (the sidebar's search field), `sidebar` (its note list) or `other`. A text field
    /// that is being edited has the keyboard in the window's field editor, a text view that is a subview of the field and its
    /// delegate, so the answer is found from the first view on the way up from the responder that has one of the identifiers.
    static func firstResponderName(in window: NSWindow?) -> String {
        guard let responder = window?.firstResponder else { return "other" }
        var candidates: [NSView] = []
        if let textView = responder as? NSTextView, textView.isFieldEditor, let owner = textView.delegate as? NSView {
            candidates.append(owner)
        }
        var view = responder as? NSView
        while let current = view {
            candidates.append(current)
            view = current.superview
        }
        for candidate in candidates {
            switch candidate.accessibilityIdentifier() {
            case AccessibilityID.editorTextView: return "editor"
            case AccessibilityID.titleField: return "title"
            case AccessibilityID.sidebarSearch: return "search"
            case AccessibilityID.sidebarTable: return "sidebar"
            default: continue
            }
        }
        return "other"
    }
}
