import AppKit

/// Hides the scroll pocket that macOS 26 puts in the titlebar over the editor.
///
/// A window whose scroll view starts below the titlebar gets a hard scroll pocket there: an opaque background and, at
/// the bottom of the titlebar, a one point line in `separatorColor` (`_NSLayerBasedFillColorView`) across the whole
/// editor. The editor's scroll view starts below the title field, so it is such a window, and the line would be the
/// only chrome in it, where spec §6.1 and the mockup have the toolbar float over the note. The pocket does not look at
/// `NSWindow.titlebarSeparatorStyle` or `NSSplitViewItem.titlebarSeparatorStyle`: each was set to `.none` on CI, and
/// the screenshots had the line on the same pixels both times.
///
/// There is no public API for the pocket, so it is found by its class name. If a later macOS renames the classes the
/// line comes back, and `TitlebarPocketTests` fails.
enum TitlebarPocket {
    private static let backgroundClassName = "NSTitlebarBackgroundView"
    private static let pocketClassName = "NSScrollPocket"

    /// The scroll pockets inside the titlebar backgrounds anywhere in `splitView`, hidden or not. It does not look
    /// inside a scroll view: the sidebar's own pocket is there, and it is not the line over the editor.
    static func pockets(in splitView: NSView) -> [NSView] {
        var found: [NSView] = []
        collectPockets(in: splitView, into: &found)
        return found
    }

    /// Hides every pocket that `pockets(in:)` finds. A pocket that is hidden already is left alone, so that calling
    /// this from every layout does not ask for another layout.
    static func hide(in splitView: NSView) {
        for pocket in pockets(in: splitView) where !pocket.isHidden {
            pocket.isHidden = true
        }
    }

    private static func collectPockets(in view: NSView, into found: inout [NSView]) {
        for subview in view.subviews {
            if className(of: subview) == backgroundClassName {
                found += subview.subviews.filter { className(of: $0) == pocketClassName }
            } else if !(subview is NSScrollView) {
                collectPockets(in: subview, into: &found)
            }
        }
    }

    private static func className(of view: NSView) -> String {
        NSStringFromClass(type(of: view))
    }
}
