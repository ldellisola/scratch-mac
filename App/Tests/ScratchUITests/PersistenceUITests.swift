import AppKit
import XCTest

/// Covers docs/features/autosave-and-restore.md: typed text survives a quit or a force-kill, and the cursor comes back
/// where it was (spec §6.6, plan 1 "Review Focus" 1 and 2). Each test types into the editor without clicking it
/// first, which also proves that the editor is ready to type when the app launches.
@MainActor
final class PersistenceUITests: XCTestCase {
    /// Types into a new note, waits long enough for the autosave, then kills the app the hard way. Nothing runs in the
    /// app after that, so only what the autosave already wrote can come back.
    func testTypedTextSurvivesForceKill() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")

        editor.typeText("hello scratch")
        Thread.sleep(forTimeInterval: 1.5)

        // `XCUIApplication.terminate()` may quit gracefully. `forceTerminate()` sends SIGKILL.
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: UITestSupport.bundleIdentifier)
        XCTAssertFalse(running.isEmpty, "no running Scratch process to kill")
        for process in running {
            XCTAssertTrue(process.forceTerminate(), "the kill was not sent to process \(process.processIdentifier)")
        }
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app is still running after the kill")

        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        let restored = UITestSupport.editor(in: relaunched)
        XCTAssertTrue(restored.waitForExistence(timeout: 10), "the editor text view did not appear after relaunch")
        XCTAssertEqual(restored.value as? String, "hello scratch")
    }

    /// ⌘Q right after the last keystroke, before the autosave timer fires: quitting writes synchronously.
    func testQuitImmediatelyAfterTypingKeepsText() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")

        editor.typeText("quick")
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app did not quit")

        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        let restored = UITestSupport.editor(in: relaunched)
        XCTAssertTrue(restored.waitForExistence(timeout: 10), "the editor text view did not appear after relaunch")
        XCTAssertEqual(restored.value as? String, "quick")
    }

    /// The saved cursor offset is restored: after relaunch a typed character lands where the cursor was left.
    func testCursorRestoredAfterRelaunch() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")

        editor.typeText("abc def")
        for _ in 0..<4 { app.typeKey(.leftArrow, modifierFlags: []) }
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app did not quit")

        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        let restored = UITestSupport.editor(in: relaunched)
        XCTAssertTrue(restored.waitForExistence(timeout: 10), "the editor text view did not appear after relaunch")
        restored.typeText("X")
        XCTAssertEqual(restored.value as? String, "abcX def")
    }
}
