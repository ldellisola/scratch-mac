import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/launch-times.md ("Help > Launch Times…"): the alert holds the report in a
/// selectable text view, with the buttons Copy and OK, and Copy puts the report on the pasteboard as plain text. No test
/// shows the alert: a modal alert would wait for a click.
@MainActor
final class LaunchTimesPanelTests: XCTestCase {
    private let report = "Scratch 1.0.0, launch times on this Mac, newest first:\n2026-10-23 09:20   118 ms"

    private func reportView(of alert: NSAlert) throws -> NSTextView {
        let scrollView = try XCTUnwrap(alert.accessoryView as? NSScrollView)
        return try XCTUnwrap(scrollView.documentView as? NSTextView)
    }

    func testAlertHoldsTheReportInASelectableTextView() throws {
        let alert = LaunchTimesPanel.makeAlert(report: report)
        let textView = try reportView(of: alert)

        XCTAssertEqual(textView.string, report)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.isEditable)
        XCTAssertEqual(textView.accessibilityIdentifier(), AccessibilityID.launchTimesReport)
        XCTAssertTrue(
            textView.font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false,
            "the columns of the report line up")
        XCTAssertEqual(alert.accessoryView?.frame.size, LaunchTimesPanel.reportSize)
    }

    func testAlertHasCopyAndOK() {
        let alert = LaunchTimesPanel.makeAlert(report: report)
        XCTAssertEqual(alert.buttons.map(\.title), ["Copy", "OK"])
        XCTAssertEqual(alert.buttons.last?.keyEquivalent, "\u{1b}", "Escape presses OK")
    }

    func testCopyWritesThePlainTextAndNothingElse() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("older", forType: .string)

        LaunchTimesPanel.copy(report, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), report)
        XCTAssertEqual(pasteboard.types, [.string])
    }

    func testReportIsTheLogsReportForThisVersion() {
        var log = LaunchLog()
        XCTAssertEqual(LaunchTimesPanel.report(of: log), "No launches recorded yet.")

        log.append(
            LaunchRecord(
                date: Date(timeIntervalSince1970: 1_792_746_000), version: "1.0.0",
                bootTime: Date(timeIntervalSince1970: 1_792_700_000), phases: ["firstFrame": 118],
                isFirstAfterStartUp: false))
        let text = LaunchTimesPanel.report(of: log, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(
            text.hasPrefix("Scratch \(LaunchTimesPanel.appVersion), launch times on this Mac, newest first:"), text)
        XCTAssertTrue(text.contains("2026-10-23 09:00   118 ms   first after start-up"), text)
    }
}
