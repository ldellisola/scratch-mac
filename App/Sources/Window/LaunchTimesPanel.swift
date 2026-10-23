import AppKit
import ScratchCore

/// Help > Launch Times…: the launch log's report (`LaunchLog.report`) in an alert, in a monospaced text view that can be
/// selected, with the buttons Copy (the report, as plain text, to the general pasteboard) and OK. It is how the owner
/// checks the spec's cold-boot budget on a real Mac and passes the numbers on (docs/features/launch-times.md).
@MainActor
enum LaunchTimesPanel {
    /// The size of the text view in the alert: about 60 characters of the report across, and a screenful of launches.
    static let reportSize = NSSize(width: 560, height: 220)
    static let title = "Launch Times"

    /// The app's version, as the bundle says it (`CFBundleShortVersionString`, from `VERSION`).
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// The text of the panel: `log`'s report for this version of the app, in the Mac's time zone.
    static func report(of log: LaunchLog, timeZone: TimeZone = .current) -> String {
        log.report(version: appVersion, timeZone: timeZone)
    }

    /// The alert, not shown: the text view with `report` (identifier `launchTimes.report`, selectable, never editable), and
    /// the buttons Copy, which is the default, and OK, which Escape presses.
    static func makeAlert(report: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "From the start of the process until the note is on screen and takes keystrokes."

        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(origin: .zero, size: reportSize)
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.textColor = .labelColor
            textView.string = report
            textView.setAccessibilityIdentifier(AccessibilityID.launchTimesReport)
            textView.setAccessibilityLabel("Launch times")
        }
        alert.accessoryView = scrollView

        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "OK").keyEquivalent = "\u{1b}"
        return alert
    }

    /// Puts `report` on `pasteboard` as plain text, and nothing else.
    static func copy(_ report: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
    }

    /// Shows the alert as a sheet of `window` (the app stays usable), or as a panel of its own without a window, and copies
    /// the report when Copy is pressed.
    static func present(report: String, over window: NSWindow?) {
        let alert = makeAlert(report: report)
        if let window, window.isVisible {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated {
                    if response == .alertFirstButtonReturn { copy(report) }
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            copy(report)
        }
    }
}
