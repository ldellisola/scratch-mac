import XCTest

/// Spec §7, on the `huge-note` fixture: a note of 10,000 lines (half of it code) and a small one. The measured numbers
/// are `keystroke_ms`, `scroll_frame_ms`, `switch_small_ms` and `switch_huge_ms` (scripts/perf-extract.py).
///
/// Each test is one launch of the app on a data directory of its own.
@MainActor
final class EditorPerfTests: XCTestCase {
    /// Launches on `huge-note` and waits until the editor and both notes of the sidebar are there.
    private func launchHugeNote(dataDirectory: URL = UITestSupport.makeDataDirectory(), extraArguments: [String] = [])
        -> XCUIApplication
    {
        let app = PerfSupport.launch(fixture: "huge-note", dataDirectory: dataDirectory, extraArguments: extraArguments)
        XCTAssertTrue(UITestSupport.editor(in: app).waitForExistence(timeout: 30), "the editor did not appear")
        XCTAssertTrue(
            UITestSupport.wait(timeout: 30) { UITestSupport.sidebarTitleTexts(in: app).count == 2 },
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        return app
    }

    /// Page Down presses that move the cursor and the view about a third of the way into the huge note (about 36
    /// lines each, so line 4,000 or so).
    private static let pageDownPresses = 120

    /// `keystroke_ms`: the `keystroke` signpost interval, from `NoteTextView.keyDown` until the character is on screen.
    /// One character per iteration, so that every iteration holds one interval, typed about a third of the way into
    /// the huge note. A few characters are typed first, outside the measurement, to warm up the text system; the
    /// screenshots before and after show where the characters went.
    func testKeystroke() throws {
        continueAfterFailure = false
        let app = launchHugeNote()
        defer { app.terminate() }
        let editor = UITestSupport.editor(in: app)
        for _ in 0..<Self.pageDownPresses { app.typeKey(.pageDown, modifierFlags: []) }
        editor.typeText("warm up ")
        PerfSupport.attachScreenshot(of: app, named: "keystroke-before", to: self)

        let options = XCTMeasureOptions()
        options.iterationCount = 100
        measure(metrics: [PerfSupport.signpostMetric(named: "keystroke")], options: options) {
            editor.typeText("x")
        }
        PerfSupport.attachScreenshot(of: app, named: "keystroke-after", to: self)
    }

    /// Down arrow presses of the scroll test. The cursor starts at the top and moves down one line per press. The
    /// first presses (about 36) stay inside the window, and every press after that scrolls the note by one line.
    private static let scrollPresses = 250

    /// `scroll_frame_ms`: the longest frame the app's `FrameMonitor` saw while the test scrolled through the huge note
    /// one line at a time, like a slow scroll, where each frame lays out and draws one new line. (Page Down jumps a
    /// whole window of new text per press: the first runs measured that, and a frame of 16 to 33 ms is the cost of a
    /// full-window redraw, not of scrolling.) The monitor writes its report to a file, and the test attaches it as
    /// `scroll_frame_ms` for perf-extract.py.
    func testScrollHugeNote() throws {
        continueAfterFailure = false
        let dataDirectory = UITestSupport.makeDataDirectory()
        let report = dataDirectory.appendingPathComponent("frame-monitor.json")
        let app = launchHugeNote(dataDirectory: dataDirectory, extraArguments: ["-ScratchFrameMonitor", report.path])
        defer { app.terminate() }

        // The monitor ignores the first seconds after launch.
        Thread.sleep(forTimeInterval: 4)
        for _ in 0..<Self.scrollPresses { app.typeKey(.downArrow, modifierFlags: []) }

        let written = UITestSupport.wait(timeout: 20) { FileManager.default.fileExists(atPath: report.path) }
        XCTAssertTrue(written, "the frame monitor wrote nothing to \(report.path)")
        // The file is rewritten after any later frame, so wait for the paging to be over before reading it.
        Thread.sleep(forTimeInterval: 2)
        let data = try Data(contentsOf: report)
        let numbers = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Double])
        XCTAssertGreaterThan(numbers["frames"] ?? 0, 100, "the frame report: \(numbers)")

        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        attachment.name = "scroll_frame_ms"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// `switch_small_ms`: the `switch-note` interval of a click on "Small" while "Huge" is open, from the click until
    /// the note is on screen. Going back to "Huge" is not measured.
    func testSwitchToSmallNote() throws {
        continueAfterFailure = false
        let app = launchHugeNote()
        defer { app.terminate() }
        let small = UITestSupport.sidebarRow(titled: "Small", in: app)
        let huge = UITestSupport.sidebarRow(titled: "Huge", in: app)
        XCTAssertTrue(small.waitForExistence(timeout: 10) && huge.waitForExistence(timeout: 10), "no sidebar rows")

        // Switch back and forth twice first, outside the measurement, to warm up the text system.
        for _ in 0..<2 {
            small.click()
            huge.click()
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 15
        options.invocationOptions = [.manuallyStart]
        measure(metrics: [PerfSupport.signpostMetric(named: "switch-note")], options: options) {
            huge.click()
            startMeasuring()
            small.click()
        }
        XCTAssertTrue(
            UITestSupport.wait { (UITestSupport.editor(in: app).value as? String ?? "").hasPrefix("Line 1 of") },
            "the small note is not shown")
    }

    /// `switch_huge_ms`: the `switch-note` interval of a click on "Huge" while "Small" is open. Going back to "Small"
    /// is not measured.
    func testSwitchToHugeNote() throws {
        continueAfterFailure = false
        let app = launchHugeNote()
        defer { app.terminate() }
        let small = UITestSupport.sidebarRow(titled: "Small", in: app)
        let huge = UITestSupport.sidebarRow(titled: "Huge", in: app)
        XCTAssertTrue(small.waitForExistence(timeout: 10) && huge.waitForExistence(timeout: 10), "no sidebar rows")

        for _ in 0..<2 {
            small.click()
            huge.click()
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 15
        options.invocationOptions = [.manuallyStart]
        measure(metrics: [PerfSupport.signpostMetric(named: "switch-note")], options: options) {
            small.click()
            startMeasuring()
            huge.click()
        }
        XCTAssertTrue(
            UITestSupport.wait { (UITestSupport.editor(in: app).value as? String ?? "").hasPrefix("Paragraph 1,") },
            "the huge note is not shown")
    }
}
