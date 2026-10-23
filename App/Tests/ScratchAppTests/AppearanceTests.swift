import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/accessibility.md ("Increase Contrast"): every colour of the asset catalog has a
/// high contrast variant, light and dark, that differs from the usual one and reads on the tint of a code block, and
/// `-ScratchAppearance light-contrast` and `dark-contrast` force the two accessibility appearances that those variants
/// answer to (spec §6.1, plan 6 task 8). Reduce Transparency has no test: only system materials are translucent, and they
/// follow the setting by themselves.
@MainActor
final class AppearanceTests: XCTestCase {
    /// The colour sets of the asset catalog. The test also reads the catalog folder when it can, so a colour that is added
    /// without a high contrast variant is found here.
    private static let knownNames = [
        "CodeAttribute", "CodeBackground", "CodeBorder", "CodeComment", "CodeFunction", "CodeKeyword", "CodeNumber",
        "CodePreprocessor", "CodeString", "CodeText", "CodeType",
    ]

    /// The colours that are drawn as text, on the editor's background or on the tint of a block or a pill.
    private static let textNames = [
        "CodeAttribute", "CodeComment", "CodeFunction", "CodeKeyword", "CodeNumber", "CodePreprocessor", "CodeString",
        "CodeText", "CodeType",
    ]

    /// The names of the `.colorset` folders of the app's asset catalog, found from this file's place in the repository.
    private func catalogNames() -> [String] {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let catalog =
            tests.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Assets.xcassets", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: catalog.path)) ?? []
        return folders.filter { $0.hasSuffix(".colorset") }.map { String($0.dropLast(".colorset".count)) }
    }

    private var allNames: [String] {
        Array(Set(Self.knownNames).union(catalogNames())).sorted()
    }

    /// The colour `name` as it resolves in `appearance`, as red, green, blue and alpha.
    private func components(_ color: NSColor, in appearanceName: NSAppearance.Name) throws -> [CGFloat] {
        let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
        var result: [CGFloat] = []
        appearance.performAsCurrentDrawingAppearance {
            if let rgb = color.usingColorSpace(.sRGB) {
                result = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
            }
        }
        XCTAssertEqual(result.count, 4, "\(color) has no sRGB value in \(appearanceName)")
        return result
    }

    private func asset(_ name: String) throws -> NSColor {
        try XCTUnwrap(NSColor(named: NSColor.Name(name)), "the asset catalog has no colour \(name)")
    }

    // MARK: Every colour has a high contrast variant

    func testEveryColourHasAHighContrastVariant() throws {
        XCTAssertFalse(allNames.isEmpty)
        for name in allNames {
            let color = try asset(name)
            XCTAssertNotEqual(
                try components(color, in: .highContrastAqua), try components(color, in: .aqua),
                "\(name) has no light high contrast variant")
            XCTAssertNotEqual(
                try components(color, in: .highContrastDarkAqua), try components(color, in: .darkAqua),
                "\(name) has no dark high contrast variant")
        }
    }

    func testCatalogFolderIsFoundAndHoldsEveryKnownColour() {
        let found = catalogNames()
        // The catalog is read from the source tree, which a test run on a machine without it cannot do.
        guard !found.isEmpty else { return }
        XCTAssertEqual(Set(found), Set(Self.knownNames), "a colour was added or removed: update `knownNames`")
    }

    // MARK: Readable with Increase Contrast

    /// The relative luminance of an sRGB colour (WCAG 2).
    private func luminance(_ rgb: [CGFloat]) -> Double {
        func linear(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])
    }

    private func contrast(_ first: [CGFloat], _ second: [CGFloat]) -> Double {
        let (high, low) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (high + 0.05) / (low + 0.05)
    }

    /// `tint` laid over `background`.
    private func composite(_ tint: [CGFloat], over background: [CGFloat]) -> [CGFloat] {
        let alpha = tint[3]
        return (0..<3).map { tint[$0] * alpha + background[$0] * (1 - alpha) } + [1]
    }

    /// With Increase Contrast every colour of code reads at 7:1 on the editor's own background, and at 7:1 (light) or 5:1
    /// (dark) on the tint of a block or a pill, which is stronger than the usual one.
    func testHighContrastTextReadsOnTheBackgroundAndTheTint() throws {
        let cases: [(NSAppearance.Name, NSAppearance.Name, Double, Double)] = [
            (.highContrastAqua, .aqua, 7, 7), (.highContrastDarkAqua, .darkAqua, 7, 5),
        ]
        for (high, usual, onBackground, onTint) in cases {
            let background = try components(NSColor.textBackgroundColor, in: high)
            let tint = try components(try asset("CodeBackground"), in: high)
            let usualTint = try components(try asset("CodeBackground"), in: usual)
            XCTAssertGreaterThan(tint[3], usualTint[3], "the tint is stronger in \(high)")
            let tinted = composite(tint, over: background)
            for name in Self.textNames {
                let text = try components(try asset(name), in: high)
                XCTAssertGreaterThanOrEqual(
                    contrast(text, background), onBackground, "\(name) on the background in \(high)")
                XCTAssertGreaterThanOrEqual(contrast(text, tinted), onTint, "\(name) on the tint in \(high)")
            }
        }
    }

    func testHighContrastBorderIsStrongerThanTheUsualOne() throws {
        let border = try asset("CodeBorder")
        XCTAssertGreaterThan(
            try components(border, in: .highContrastAqua)[3], try components(border, in: .aqua)[3])
        XCTAssertGreaterThan(
            try components(border, in: .highContrastDarkAqua)[3], try components(border, in: .darkAqua)[3])
    }

    // MARK: -ScratchAppearance

    func testContrastLaunchAppearancesAreTheHighContrastOnes() {
        XCTAssertEqual(AppearanceOverride.light.nsAppearanceName, .aqua)
        XCTAssertEqual(AppearanceOverride.dark.nsAppearanceName, .darkAqua)
        XCTAssertEqual(AppearanceOverride.lightContrast.nsAppearanceName, .highContrastAqua)
        XCTAssertEqual(AppearanceOverride.darkContrast.nsAppearanceName, .highContrastDarkAqua)
        XCTAssertEqual(NSAppearance.Name.highContrastAqua.rawValue, "NSAppearanceNameAccessibilityHighContrastAqua")
        XCTAssertEqual(
            NSAppearance.Name.highContrastDarkAqua.rawValue, "NSAppearanceNameAccessibilityHighContrastDarkAqua")
        // An appearance made with the name keeps it: the SDK's own `.accessibilityHighContrastAqua` is turned into plain Aqua
        // by `NSAppearance(named:)`, and would never have a colour asset answer with its high contrast variant.
        for option in AppearanceOverride.allCases {
            XCTAssertEqual(
                NSAppearance(named: option.nsAppearanceName)?.name, option.nsAppearanceName,
                "\(option) is forced as \(option.nsAppearanceName.rawValue)")
        }
    }

    /// The code colours that the editor draws with are the catalog's: a block in high contrast gets the stronger tint.
    func testCodeBlockColoursFollowTheAppearance() throws {
        let usual = try components(CodeBlockColors.background, in: .aqua)
        let high = try components(CodeBlockColors.background, in: .highContrastAqua)
        XCTAssertGreaterThan(high[3], usual[3])
        let border = try components(CodeBlockColors.border, in: .highContrastDarkAqua)
        XCTAssertEqual(border[3], 0.45, accuracy: 0.01)
    }
}
