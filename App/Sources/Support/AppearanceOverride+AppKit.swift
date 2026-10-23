import AppKit
import ScratchCore

extension AppearanceOverride {
    /// The AppKit appearance that `-ScratchAppearance` forces: aqua or dark aqua, and with Increase Contrast on the two
    /// accessibility appearances that the colour assets' high contrast variants answer to (plan 6 task 8).
    var nsAppearanceName: NSAppearance.Name {
        isDark ? .darkAqua : .aqua
    }
}
