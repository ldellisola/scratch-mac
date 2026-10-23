import AppKit

/// The colours of the asset catalog, and their high contrast variants when a launch forces them (plan 6 task 8,
/// docs/features/accessibility.md, "Increase Contrast").
///
/// Every colour set of `Assets.xcassets` has a high contrast variant, light and dark, and AppKit picks it by itself when
/// Increase Contrast is on in System Settings: `NSColor(named:)` is all the app asks. But an app cannot ask for it. The
/// appearances that stand for Increase Contrast cannot be made: `NSAppearance(named:)` answers nil for
/// "NSAppearanceNameAccessibilityHighContrastAqua" and turns the SDK's `.accessibilityHighContrastAqua` into plain Aqua, so a
/// colour set never answers with its high contrast variant to them (found on CI). So that a screenshot can show the variants
/// (`-ScratchAppearance light-contrast` and `dark-contrast`), `isHighContrastForced` makes `named(_:fallback:)` answer with the
/// same colours from `highContrast`, which a test holds to the catalog's own files (`AppearanceTests`).
///
/// It is `nonisolated`: the layout manager draws on the main thread but is not on the main actor, and it reads these colours.
nonisolated enum CatalogColour {
    /// True from the launch on when `-ScratchAppearance` is `light-contrast` or `dark-contrast`, and false otherwise. It is
    /// set once, at the start of the launch, before any colour is made; the colours that are made are not made again.
    nonisolated(unsafe) static var isHighContrastForced = false

    /// One colour in sRGB, with components from 0 to 255 and an alpha from 0 to 1.
    struct Swatch: Equatable, Sendable {
        let red: Int
        let green: Int
        let blue: Int
        let alpha: Double

        init(_ red: Int, _ green: Int, _ blue: Int, alpha: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        var color: NSColor {
            NSColor(
                srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255,
                alpha: CGFloat(alpha))
        }
    }

    /// The high contrast variants of a colour: the light one, and the dark one.
    struct Variants: Equatable, Sendable {
        let light: Swatch
        let dark: Swatch
    }

    /// The high contrast variant of each colour set, as the catalog has it. The text colours are the usual hues moved along
    /// their lightness, to 7:1 on the editor's background and on the tint of a block (5:1 in dark mode, where the stronger
    /// tint is lighter than the background).
    static let highContrast: [String: Variants] = [
        "CodeAttribute": Variants(light: Swatch(0x5F, 0x46, 0x02), dark: Swatch(0xD7, 0xB3, 0x95)),
        "CodeBackground": Variants(light: Swatch(0, 0, 0, alpha: 0.10), dark: Swatch(255, 255, 255, alpha: 0.14)),
        "CodeBorder": Variants(light: Swatch(0, 0, 0, alpha: 0.35), dark: Swatch(255, 255, 255, alpha: 0.45)),
        "CodeComment": Variants(light: Swatch(0x41, 0x4B, 0x54), dark: Swatch(0xB3, 0xBB, 0xC2)),
        "CodeFunction": Variants(light: Swatch(0x25, 0x51, 0x56), dark: Swatch(0x87, 0xC6, 0xB7)),
        "CodeKeyword": Variants(light: Swatch(0x80, 0x1D, 0x7A), dark: Swatch(0xFD, 0x9D, 0xC7)),
        "CodeNumber": Variants(light: Swatch(0x1B, 0x00, 0xC5), dark: Swatch(0xD2, 0xC2, 0x71)),
        "CodePreprocessor": Variants(light: Swatch(0x5C, 0x34, 0x1E), dark: Swatch(0xFD, 0xA5, 0x65)),
        "CodeString": Variants(light: Swatch(0x94, 0x14, 0x11), dark: Swatch(0xFD, 0xA1, 0x99)),
        "CodeText": Variants(light: Swatch(0x94, 0x14, 0x11), dark: Swatch(0xFD, 0xA1, 0x99)),
        "CodeType": Variants(light: Swatch(0x0A, 0x49, 0x70), dark: Swatch(0x67, 0xDA, 0xFF)),
    ]

    /// The colour set `name`, or `fallback` when the catalog has none. A dynamic colour: it follows the appearance of what it
    /// is drawn in, and its high contrast variant is AppKit's own when Increase Contrast is on. When a launch forces high
    /// contrast (`isHighContrastForced`) it is the variant of `highContrast` in light or dark, whatever the setting.
    static func named(_ name: String, fallback: NSColor) -> NSColor {
        guard let catalog = NSColor(named: NSColor.Name(name)) else { return fallback }
        guard isHighContrastForced, let variants = highContrast[name] else { return catalog }
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return (isDark ? variants.dark : variants.light).color
        }
    }

    /// True when Increase Contrast is on in System Settings, or a launch forced it: the colours that the code makes itself
    /// (the outline of the raised tab) ask here.
    @MainActor static var isIncreaseContrastOn: Bool {
        isHighContrastForced || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
}
