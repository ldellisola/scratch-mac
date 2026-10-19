import XCTest

/// THROWAWAY, branch spike/textkit only (plan 1 task 10, ADR 0001). Where does a keystroke's time go? The same typing
/// as `EditorPerfTests.testKeystroke`, with a metric for the whole keystroke and one for each step that has a signpost
/// (`NoteTextView.insertText`, `layout`, `draw` and the `textDidChange` callback). An interval that occurs several
/// times in one keystroke is reported however XCTest adds it up; read the numbers together with `keystroke`.
@MainActor
final class KeystrokeBreakdownSpikeTests: XCTestCase {
    func testKeystrokeBreakdown() throws {
        continueAfterFailure = false
        let app = PerfSupport.launch(fixture: "huge-note", dataDirectory: UITestSupport.makeDataDirectory())
        defer { app.terminate() }
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "the editor did not appear")
        for _ in 0..<120 { app.typeKey(.pageDown, modifierFlags: []) }
        editor.typeText("warm up ")

        let options = XCTMeasureOptions()
        options.iterationCount = 60
        let names = ["keystroke", "t-insertText", "t-layout", "t-draw", "t-didChange"]
        measure(metrics: names.map { PerfSupport.signpostMetric(named: $0) }, options: options) {
            editor.typeText("x")
        }
    }
}
