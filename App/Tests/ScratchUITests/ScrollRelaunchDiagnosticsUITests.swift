import XCTest

/// TEMPORARY diagnostics (plan 4, task 5): samples the scroll anchor of the huge note for a few seconds after a
/// relaunch, to see whether a difference from the one before the quit is a state that passes or one that stays.
@MainActor
final class ScrollRelaunchDiagnosticsUITests: XCTestCase {
    private func lineNumber(ofOffset offset: Int, in text: String) -> Int {
        text.utf16.prefix(offset).filter { $0 == 0x0A }.count + 1
    }

    private func quit(_ app: XCUIApplication) {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app did not quit")
    }

    private func iteration(_ number: Int) -> String {
        let app = UITestSupport.launch(fixture: "huge-note")
        let editor = UITestSupport.editor(in: app)
        guard editor.waitForExistence(timeout: 30) else { return "iteration \(number): no editor" }
        editor.scroll(byDeltaX: 0, deltaY: -20_000)
        let scrolled = UITestSupport.wait(timeout: 3) {
            (UITestSupport.debugState(in: app)["scrollAnchor"] as? Int ?? 0) > 0
        }
        if !scrolled { editor.scroll(byDeltaX: 0, deltaY: 20_000) }
        Thread.sleep(forTimeInterval: 1.5)
        let beforeState = UITestSupport.debugState(in: app)
        let before = beforeState["scrollAnchor"] as? Int ?? 0
        quit(app)

        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        let started = Date()
        guard UITestSupport.editor(in: relaunched).waitForExistence(timeout: 30) else {
            return "iteration \(number): no editor after relaunch"
        }
        var anchors: [Int] = []
        while Date().timeIntervalSince(started) < 9 {
            let state = UITestSupport.debugState(in: relaunched)
            anchors.append(state["scrollAnchor"] as? Int ?? -1)
            Thread.sleep(forTimeInterval: 0.5)
        }
        let finalState = UITestSupport.debugState(in: relaunched)
        let text = UITestSupport.editor(in: relaunched).value as? String ?? ""
        let lines = anchors.map { $0 < 0 ? "-" : String(lineNumber(ofOffset: $0, in: text)) }
        return "iteration \(number): before \(before) line \(lineNumber(ofOffset: before, in: text)); "
            + "after, lines over time: \(lines.joined(separator: " "))\n"
            + String(describing: finalState["trace"] ?? "no trace")
    }

    func testFirstTwo() throws {
        let report = [iteration(1)].joined(separator: "\n\n")
        XCTFail("SCROLL DIAGNOSTICS\n" + report)
    }

    func testSecondTwo() throws {
        let report = [iteration(2)].joined(separator: "\n\n")
        XCTFail("SCROLL DIAGNOSTICS\n" + report)
    }
}
