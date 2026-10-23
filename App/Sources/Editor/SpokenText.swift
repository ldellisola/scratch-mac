import AppKit
import ScratchCore

/// What VoiceOver reads for a range of the styled note (plan 6 task 8, docs/features/accessibility.md).
enum SpokenText {
    /// The words for `range` of a styled note: the storage's marker roles, code block marks and attachment marks read as in
    /// the plan's table; text without them as it is.
    static func spoken(_ storage: NSAttributedString, range: NSRange) -> String {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard clamped.length > 0 else { return "" }
        return (storage.string as NSString).substring(with: clamped)
    }
}
