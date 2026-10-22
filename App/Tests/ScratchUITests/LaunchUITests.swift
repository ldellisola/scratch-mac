import AppKit
import XCTest

/// The app launches in an isolated data directory, seeds the fixture there and shows the note that the fixture's
/// session restores (spec §6.6, §9.4). Without isolation the launch would be refused, so this also proves that
/// `-ScratchDataDir` isolates on macOS.
@MainActor
final class LaunchUITests: XCTestCase {
    func testLaunchShowsActiveNoteFromFixture() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "typical")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")
        let text = editor.value as? String ?? ""
        XCTAssertTrue(text.contains("bump version to"), "the editor shows: \(text)")
    }

    // MARK: The launch log (docs/features/launch-times.md)

    /// The records of the launch log that `debug.state` shows, newest first, once there are `count` of them. The app writes a
    /// record on a background queue after the first frame, so the test waits for it.
    private func launchTimes(in app: XCUIApplication, count: Int) -> [[String: Any]] {
        var records: [[String: Any]] = []
        _ = UITestSupport.wait(timeout: 15) {
            records = UITestSupport.debugState(in: app)["launchTimes"] as? [[String: Any]] ?? []
            return records.count >= count
        }
        return records
    }

    /// A launch writes its phases to `launch-times.json`, in order, and the next launch of the same data is not the first
    /// after start-up (the same boot) while the first was.
    func testLaunchesAreRecordedInTheLaunchLog() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "typical")
        let first = launchTimes(in: app, count: 1)
        XCTAssertEqual(first.count, 1, "no launch record after the first frame: \(first)")
        let phases = first.first?["phases"] as? [String: Double] ?? [:]
        let names = ["main", "storage", "restore", "window", "firstFrame"]
        XCTAssertEqual(Set(phases.keys), Set(names))
        let times = names.compactMap { phases[$0] }
        XCTAssertEqual(times, times.sorted(), "the phases are not in order: \(phases)")
        XCTAssertGreaterThan(times.first ?? 0, 0)
        XCTAssertEqual(first.first?["total"] as? Double, phases["firstFrame"])
        XCTAssertEqual(first.first?["isFirstAfterStartUp"] as? Bool, true)

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app did not quit")
        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        let both = launchTimes(in: relaunched, count: 2)
        XCTAssertEqual(both.count, 2, "the second launch is not in the log: \(both)")
        XCTAssertEqual(both.map { $0["isFirstAfterStartUp"] as? Bool }, [false, true], "newest first")
    }

    /// Help > Launch Times… shows the report in an alert, with Copy, which puts the report on the pasteboard.
    func testHelpMenuShowsLaunchTimes() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "typical")
        // The report holds this launch once its record is written.
        XCTAssertEqual(launchTimes(in: app, count: 1).count, 1)

        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Launch Times…"].click()

        let copy = app.buttons["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10), "the Launch Times alert has no Copy button")
        XCTAssertTrue(app.buttons["OK"].exists)
        let report = app.descendants(matching: .any).matching(identifier: AccessibilityID.launchTimesReport).firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5), "the alert has no report")
        let text = report.value as? String ?? ""
        XCTAssertTrue(text.contains("launch times on this Mac"), "the report reads: \(text)")
        XCTAssertTrue(text.contains("first after start-up"), "the report reads: \(text)")

        NSPasteboard.general.clearContents()
        copy.click()
        XCTAssertTrue(copy.waitForNonExistence(timeout: 5), "the alert is still there after Copy")
        XCTAssertTrue(
            UITestSupport.wait(timeout: 5) {
                NSPasteboard.general.string(forType: .string)?.contains("launch times on this Mac") == true
            }, "Copy did not put the report on the pasteboard")
    }
}
