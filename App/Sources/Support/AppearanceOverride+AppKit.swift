import AppKit
import ScratchCore

extension AppearanceOverride {
    /// The AppKit appearance that `-ScratchAppearance` forces: aqua, or dark aqua. With Increase Contrast on (`light-contrast`
    /// and `dark-contrast`) it is the same, and the high contrast variants of the colours come from
    /// `CatalogColour.isHighContrastForced`: the appearances that stand for Increase Contrast cannot be made with
    /// `NSAppearance(named:)` (see `CatalogColour`).
    var nsAppearanceName: NSAppearance.Name {
        isDark ? .darkAqua : .aqua
    }

    /// Forces this appearance on `application`, and the high contrast variants of the colours when it is a contrast one.
    /// Call it before any colour of the catalog is made: the launch does, first thing.
    @MainActor func force(on application: NSApplication) {
        CatalogColour.isHighContrastForced = isHighContrast
        application.appearance = NSAppearance(named: nsAppearanceName)
    }
}
