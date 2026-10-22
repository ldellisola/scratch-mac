import AppKit
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/code.md ("Licences") and docs/decisions/0007-tree-sitter.md: the About panel shows
/// the licences of tree-sitter and of every grammar, from `Acknowledgements.rtf` in the app's resources (plan 5 task 7, a
/// 0.4.0 follow-up). The file is made by `scripts/make-acknowledgements.py`; `scripts/tests/test-acknowledgements.sh` holds
/// it to Package.resolved, and `scripts/check-release-zip.sh` checks that a release carries it.
@MainActor
final class AboutCreditsTests: XCTestCase {
    /// The bundle of the app that hosts the tests: where the resource is.
    private let bundle = Bundle(for: AppDelegate.self)

    func testAboutCreditsListTreeSitter() throws {
        let credits = try XCTUnwrap(AboutCredits.credits(in: bundle), "Acknowledgements.rtf is in the app's resources")

        XCTAssertTrue(credits.string.contains("tree-sitter"), "tree-sitter is credited")
        XCTAssertTrue(credits.string.contains("MIT"), "with its licence")
    }

    func testEveryComponentOfTheBuildIsCredited() throws {
        let credits = try XCTUnwrap(AboutCredits.credits(in: bundle)).string

        // The runtime and the wrapper, the fetched grammars and the three vendored ones (docs/decisions/0007).
        let names = [
            "tree-sitter", "swift-tree-sitter", "tree-sitter-swift", "tree-sitter-python", "tree-sitter-javascript",
            "tree-sitter-typescript", "tree-sitter-json", "tree-sitter-bash", "tree-sitter-sql", "tree-sitter-yaml",
            "tree-sitter-html", "tree-sitter-css", "tree-sitter-c-sharp", "tree-sitter-go", "tree-sitter-rust",
            "tree-sitter-c", "tree-sitter-cpp", "tree-sitter-java", "tree-sitter-powershell",
        ]
        for name in names { XCTAssertTrue(credits.contains(name + " "), "\(name) is credited, with its version") }
        XCTAssertTrue(credits.contains("BSD 3-Clause"), "swift-tree-sitter's licence is not MIT")
        XCTAssertTrue(
            credits.contains("Permission is hereby granted, free of charge"), "the text of the licence is there")
        XCTAssertTrue(credits.contains("Max Brunsfeld"), "and its copyright holders")
    }

    func testCreditsTextHasNoColourOfItsOwn() throws {
        // The panel is as dark as the window: black text from the file would be unreadable on it.
        let credits = try XCTUnwrap(AboutCredits.credits(in: bundle))
        var index = 0
        var runs = 0
        while index < credits.length {
            var range = NSRange(location: 0, length: 0)
            let colour = credits.attribute(.foregroundColor, at: index, effectiveRange: &range) as? NSColor
            XCTAssertEqual(colour, NSColor.labelColor, "the run at \(index)")
            index = NSMaxRange(range)
            runs += 1
        }
        XCTAssertGreaterThan(runs, 0)
    }

    func testPanelOptionsCarryTheCredits() throws {
        let options = AboutCredits.panelOptions(in: bundle)

        let credits = try XCTUnwrap(options[.credits] as? NSAttributedString, "the options have the credits")
        XCTAssertEqual(credits.string, try XCTUnwrap(AboutCredits.credits(in: bundle)).string)
    }

    func testABundleWithoutTheFileHasNoCredits() {
        // Foundation's own bundle has no Acknowledgements.rtf: the About panel then shows what it always did.
        let other = Bundle(for: NSObject.self)

        XCTAssertNil(AboutCredits.credits(in: other))
        XCTAssertTrue(AboutCredits.panelOptions(in: other).isEmpty)
    }
}
