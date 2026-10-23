import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/accessibility.md ("Increase Contrast"): every colour of the asset catalog has a
/// high contrast variant, light and dark, that differs from the usual one and reads on the editor's background and on the
/// tint of a code block, a launch that forces `light-contrast` or `dark-contrast` draws with those same colours
/// (`CatalogColour`), and the tint and the border are stronger (spec §6.1, plan 6 task 8). Reduce Transparency has no test:
/// only system materials are translucent, and they follow the setting by themselves.
///
/// The high contrast variants are read from the catalog's own files, `Contents.json` of each colour set, found from this
/// file's place in the source tree: AppKit cannot be asked for them from a test, because the appearances that stand for
/// Increase Contrast cannot be made (`NSAppearance(named:)` answers nil for "NSAppearanceNameAccessibilityHighContrastAqua" and
/// turns the SDK's `.accessibilityHighContrastAqua` into plain Aqua: found on CI), so `NSColor(named:)` never answers with its
/// high contrast variant in a test.
@MainActor
final class AppearanceTests: XCTestCase {
    /// The colour sets of the asset catalog: a colour that is added or removed makes `testTheCatalogHoldsTheKnownColours` fail.
    private static let knownNames = [
        "CodeAttribute", "CodeBackground", "CodeBorder", "CodeComment", "CodeFunction", "CodeKeyword", "CodeNumber",
        "CodePreprocessor", "CodeString", "CodeText", "CodeType",
    ]

    /// The colours that are drawn as text, on the editor's background or on the tint of a block or a pill.
    private static let textNames = [
        "CodeAttribute", "CodeComment", "CodeFunction", "CodeKeyword", "CodeNumber", "CodePreprocessor", "CodeString",
        "CodeText", "CodeType",
    ]

    // MARK: The catalog's files

    /// A colour as the catalog's file has it: sRGB, with components from 0 to 255 and an alpha from 0 to 1.
    private struct Swatch: Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double

        /// The components from 0 to 1.
        var unit: [Double] { [red / 255, green / 255, blue / 255] }
    }

    /// The four entries of a colour set.
    private struct ColourSet {
        var light: Swatch?
        var dark: Swatch?
        var highLight: Swatch?
        var highDark: Swatch?
    }

    private func catalogFolder() throws -> URL {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let catalog =
            tests.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Assets.xcassets", isDirectory: true)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: catalog.path, isDirectory: &isDirectory) && isDirectory.boolValue,
            "the asset catalog is not at \(catalog.path)")
        return catalog
    }

    private func catalogNames() throws -> [String] {
        let folders = try FileManager.default.contentsOfDirectory(atPath: try catalogFolder().path)
        return folders.filter { $0.hasSuffix(".colorset") }.map { String($0.dropLast(".colorset".count)) }.sorted()
    }

    /// A component as `Contents.json` writes it: "0x9B" for 155, or a decimal "0.060", or a number.
    private func component(_ value: Any?, isAlpha: Bool) -> Double? {
        if let number = value as? Double { return isAlpha ? number : number * 255 }
        guard let text = value as? String else { return nil }
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return Int(text.dropFirst(2), radix: 16).map(Double.init)
        }
        return Double(text).map { isAlpha || $0 > 1 ? $0 : $0 * 255 }
    }

    /// The tags of an entry's appearances: "luminosity=dark" and "contrast=high".
    private func tags(of entry: [String: Any]) -> Set<String> {
        let appearances = (entry["appearances"] as? [[String: String]]) ?? []
        var result: Set<String> = []
        for item in appearances {
            if let appearance = item["appearance"], let value = item["value"] {
                result.insert("\(appearance)=\(value)")
            }
        }
        return result
    }

    private func colourSet(_ name: String) throws -> ColourSet {
        let url = try catalogFolder().appendingPathComponent("\(name).colorset/Contents.json")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(root["colors"] as? [[String: Any]], "\(name) has no colors")
        var set = ColourSet()
        for entry in entries {
            let components = ((entry["color"] as? [String: Any])?["components"] as? [String: Any]) ?? [:]
            guard let red = component(components["red"], isAlpha: false),
                let green = component(components["green"], isAlpha: false),
                let blue = component(components["blue"], isAlpha: false),
                let alpha = component(components["alpha"], isAlpha: true)
            else {
                XCTFail("\(name) has an entry with no sRGB components: \(entry)")
                continue
            }
            let swatch = Swatch(red: red, green: green, blue: blue, alpha: alpha)
            let entryTags = tags(of: entry)
            if entryTags.isEmpty {
                set.light = swatch
            } else if entryTags == ["luminosity=dark"] {
                set.dark = swatch
            } else if entryTags == ["contrast=high"] {
                set.highLight = swatch
            } else if entryTags == ["luminosity=dark", "contrast=high"] {
                set.highDark = swatch
            } else {
                XCTFail("\(name) has an entry for \(entryTags)")
            }
        }
        return set
    }

    // MARK: Every colour has a high contrast variant

    func testTheCatalogHoldsTheKnownColours() throws {
        XCTAssertEqual(try catalogNames(), Self.knownNames, "a colour was added or removed: update `knownNames`")
    }

    func testEveryColourHasAHighContrastVariant() throws {
        for name in try catalogNames() {
            let set = try colourSet(name)
            XCTAssertNotNil(set.light, "\(name) has no light colour")
            XCTAssertNotNil(set.dark, "\(name) has no dark colour")
            XCTAssertNotNil(set.highLight, "\(name) has no light high contrast variant")
            XCTAssertNotNil(set.highDark, "\(name) has no dark high contrast variant")
            XCTAssertNotEqual(set.highLight, set.light, "\(name)'s light high contrast variant is the usual colour")
            XCTAssertNotEqual(set.highDark, set.dark, "\(name)'s dark high contrast variant is the usual colour")
        }
    }

    // MARK: Readable with Increase Contrast

    /// The relative luminance of an sRGB colour with components from 0 to 1 (WCAG 2).
    private func luminance(_ rgb: [Double]) -> Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])
    }

    private func contrast(_ first: [Double], _ second: [Double]) -> Double {
        let (high, low) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (high + 0.05) / (low + 0.05)
    }

    /// `tint` laid over `background` (components from 0 to 1).
    private func composite(_ tint: Swatch, over background: [Double]) -> [Double] {
        (0..<3).map { tint.unit[$0] * tint.alpha + background[$0] * (1 - tint.alpha) }
    }

    /// With Increase Contrast every colour of code reads at 7:1 on the editor's background and on the tint of a block or a
    /// pill in light mode, and in dark mode at 7:1 on the background and at 5:1 on the tint, which is stronger and lighter.
    /// The light background is white. The dark one is measured against the usual `#1E1E1E` and against black, which Increase
    /// Contrast may make it.
    func testHighContrastTextReadsOnTheBackgroundAndTheTint() throws {
        let tint = try colourSet("CodeBackground")
        let lightTint = try XCTUnwrap(tint.highLight)
        let darkTint = try XCTUnwrap(tint.highDark)
        let white = [1.0, 1.0, 1.0]
        let darkBackgrounds = [[30.0 / 255, 30.0 / 255, 30.0 / 255], [0.0, 0.0, 0.0]]
        for name in Self.textNames {
            let set = try colourSet(name)
            let light = try XCTUnwrap(set.highLight).unit
            let dark = try XCTUnwrap(set.highDark).unit
            XCTAssertGreaterThanOrEqual(contrast(light, white), 7, "\(name) on white")
            XCTAssertGreaterThanOrEqual(
                contrast(light, composite(lightTint, over: white)), 7, "\(name) on the light tint")
            for background in darkBackgrounds {
                XCTAssertGreaterThanOrEqual(contrast(dark, background), 7, "\(name) on \(background)")
                XCTAssertGreaterThanOrEqual(
                    contrast(dark, composite(darkTint, over: background)), 5,
                    "\(name) on the dark tint over \(background)")
            }
        }
    }

    func testHighContrastTintAndBorderAreStronger() throws {
        for name in ["CodeBackground", "CodeBorder"] {
            let set = try colourSet(name)
            XCTAssertGreaterThan(try XCTUnwrap(set.highLight).alpha, try XCTUnwrap(set.light).alpha, "\(name), light")
            XCTAssertGreaterThan(try XCTUnwrap(set.highDark).alpha, try XCTUnwrap(set.dark).alpha, "\(name), dark")
        }
        let border = try colourSet("CodeBorder")
        XCTAssertEqual(try XCTUnwrap(border.highLight).alpha, 0.35, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(border.highDark).alpha, 0.45, accuracy: 0.001)
    }

    // MARK: A launch that forces Increase Contrast

    /// `CatalogColour.highContrast` is what the catalog says, colour for colour, so that a screenshot of a forced launch shows
    /// the variants that a Mac with Increase Contrast on shows.
    func testForcedHighContrastIsTheCatalogsHighContrast() throws {
        XCTAssertEqual(Set(CatalogColour.highContrast.keys), Set(Self.knownNames))
        for name in try catalogNames() {
            let set = try colourSet(name)
            let forced = try XCTUnwrap(CatalogColour.highContrast[name], "\(name) has no forced variants")
            for (swatch, expected, mode) in [
                (forced.light, set.highLight, "light"), (forced.dark, set.highDark, "dark"),
            ] {
                let expected = try XCTUnwrap(expected)
                XCTAssertEqual(Double(swatch.red), expected.red, accuracy: 0.5, "\(name), \(mode), red")
                XCTAssertEqual(Double(swatch.green), expected.green, accuracy: 0.5, "\(name), \(mode), green")
                XCTAssertEqual(Double(swatch.blue), expected.blue, accuracy: 0.5, "\(name), \(mode), blue")
                XCTAssertEqual(swatch.alpha, expected.alpha, accuracy: 0.001, "\(name), \(mode), alpha")
            }
        }
    }

    /// The colour as it resolves in `appearance`: red, green and blue from 0 to 255, and alpha from 0 to 1.
    private func resolved(_ color: NSColor, in appearanceName: NSAppearance.Name) throws -> [Double] {
        let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
        var result: [Double] = []
        appearance.performAsCurrentDrawingAppearance {
            if let rgb = color.usingColorSpace(.sRGB) {
                result = [
                    Double(rgb.redComponent) * 255, Double(rgb.greenComponent) * 255, Double(rgb.blueComponent) * 255,
                    Double(rgb.alphaComponent),
                ]
            }
        }
        XCTAssertEqual(result.count, 4, "\(color) has no sRGB value in \(appearanceName)")
        return result
    }

    private func values(of swatch: CatalogColour.Swatch) -> [Double] {
        [Double(swatch.red), Double(swatch.green), Double(swatch.blue), swatch.alpha]
    }

    private func assertEqual(
        _ actual: [Double], _ expected: [Double], _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, message, file: file, line: line)
        for (index, value) in actual.enumerated() where index < expected.count {
            XCTAssertEqual(value, expected[index], accuracy: index == 3 ? 0.002 : 0.6, message, file: file, line: line)
        }
    }

    func testForcedHighContrastColoursResolveByAppearance() throws {
        CatalogColour.isHighContrastForced = true
        defer { CatalogColour.isHighContrastForced = false }

        for name in Self.knownNames {
            let color = CatalogColour.named(name, fallback: .systemPink)
            let forced = try XCTUnwrap(CatalogColour.highContrast[name])
            assertEqual(try resolved(color, in: .aqua), values(of: forced.light), "\(name) in light")
            assertEqual(try resolved(color, in: .darkAqua), values(of: forced.dark), "\(name) in dark")
        }
    }

    func testWithoutAForcedLaunchTheCatalogIsAskedAsBefore() throws {
        XCTAssertFalse(CatalogColour.isHighContrastForced)
        for name in Self.knownNames {
            let color = CatalogColour.named(name, fallback: .systemPink)
            let catalog = try XCTUnwrap(NSColor(named: NSColor.Name(name)), name)
            assertEqual(try resolved(color, in: .aqua), try resolved(catalog, in: .aqua), "\(name) in light")
            assertEqual(try resolved(color, in: .darkAqua), try resolved(catalog, in: .darkAqua), "\(name) in dark")
        }
        // A name that the catalog does not have is the fallback.
        let missing = CatalogColour.named("NoSuchColour", fallback: .systemPink)
        assertEqual(try resolved(missing, in: .aqua), try resolved(.systemPink, in: .aqua), "the fallback")
    }

    func testCodeBlockColoursFollowTheForcedContrast() throws {
        let usual = try resolved(CodeBlockColors.background, in: .aqua)
        CatalogColour.isHighContrastForced = true
        defer { CatalogColour.isHighContrastForced = false }

        let high = try resolved(CodeBlockColors.background, in: .aqua)
        XCTAssertGreaterThan(high[3], usual[3], "the tint of a block is stronger")
        XCTAssertEqual(try resolved(CodeBlockColors.border, in: .darkAqua)[3], 0.45, accuracy: 0.002)
    }

    // MARK: -ScratchAppearance

    func testContrastLaunchAppearances() {
        XCTAssertEqual(AppearanceOverride.light.nsAppearanceName, .aqua)
        XCTAssertEqual(AppearanceOverride.dark.nsAppearanceName, .darkAqua)
        XCTAssertEqual(AppearanceOverride.lightContrast.nsAppearanceName, .aqua, "light, with its colours forced")
        XCTAssertEqual(AppearanceOverride.darkContrast.nsAppearanceName, .darkAqua, "dark, with its colours forced")
        for option in AppearanceOverride.allCases {
            XCTAssertNotNil(NSAppearance(named: option.nsAppearanceName), "\(option)")
        }
    }
}
