import AppKit
import ScratchCore

extension NSAppearance.Name {
    /// The light appearance with Increase Contrast on, which the high contrast variants of the colour assets answer to.
    ///
    /// Not `NSAppearance.Name.accessibilityHighContrastAqua`: that constant's raw value is "NSAppearanceNameAccessibilityAqua", and
    /// `NSAppearance(named:)` resolves it back to plain Aqua (the dark one to plain Dark Aqua), so a colour asset never
    /// answers with its high contrast variant to it (found on CI, plan 6 task 8). The name that AppKit uses for the
    /// appearance, and that an appearance made with it has, is this one.
    static let highContrastAqua = NSAppearance.Name("NSAppearanceNameAccessibilityHighContrastAqua")

    /// The dark appearance with Increase Contrast on (see `highContrastAqua`).
    static let highContrastDarkAqua = NSAppearance.Name("NSAppearanceNameAccessibilityHighContrastDarkAqua")
}

extension AppearanceOverride {
    /// The AppKit appearance that `-ScratchAppearance` forces: aqua or dark aqua, and with Increase Contrast on the two
    /// high contrast ones that the colour assets' high contrast variants answer to (plan 6 task 8).
    var nsAppearanceName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        case .lightContrast: .highContrastAqua
        case .darkContrast: .highContrastDarkAqua
        }
    }
}
