import AppKit

/// The credits of the About panel: the licences of tree-sitter and of every grammar in the build, from
/// `Acknowledgements.rtf` in the app's resources (plan 5 task 7, a 0.4.0 follow-up; docs/decisions/0007-tree-sitter.md).
///
/// `scripts/make-acknowledgements.py` writes the file from `Package.resolved`, SwiftPM's checkouts and the vendored grammars
/// (a new grammar adds itself), `scripts/tests/test-acknowledgements.sh` holds the checked-in file to them, and
/// `scripts/check-release-zip.sh` fails a release that lacks it. The panel is `NSApplication.orderFrontStandardAboutPanel(options:)`
/// with these options (`AppCommands.showAbout`).
enum AboutCredits {
    /// The file's name, without its extension.
    static let resourceName = "Acknowledgements"

    /// The text of the file, or nil when `bundle` has none (the panel then shows what it always did). The file has no colour
    /// of its own: the text takes the colour of the label, so that it is as readable in a dark window as in a light one.
    static func credits(in bundle: Bundle = .main) -> NSAttributedString? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "rtf"),
            let data = try? Data(contentsOf: url),
            let loaded = try? NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        else { return nil }
        let credits = NSMutableAttributedString(attributedString: loaded)
        credits.addAttribute(
            .foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: credits.length))
        return credits
    }

    /// The options of the About panel: its credits. Empty when there are none.
    static func panelOptions(in bundle: Bundle = .main) -> [NSApplication.AboutPanelOptionKey: Any] {
        guard let credits = credits(in: bundle) else { return [:] }
        return [.credits: credits]
    }
}
