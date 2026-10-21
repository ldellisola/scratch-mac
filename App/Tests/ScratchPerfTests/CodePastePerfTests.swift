import AppKit
import XCTest

/// Spec §7: "Highlight colours appearing after a 500-line code paste, 50 ms". On the `empty` fixture, one paste of 500
/// lines of Swift per iteration with ⌘V. The measured number is `paste_code_ms` (scripts/perf-extract.py): the
/// `paste-code` signpost interval, from `NoteTextView.paste` until the colours of the block that the paste made are on
/// screen (the plain paste, the detection of the language, the wrap in a fence, the highlighting on its queue and the
/// colours written back: `CodeBlockStyler.whenHighlighted`).
@MainActor
final class CodePastePerfTests: XCTestCase {
    private static let iterations = 10

    /// Counts the pastes, for the names in the code that each one pastes.
    private var seed = 0

    /// 500 lines of Swift (125 functions of four lines, about 11,500 characters) with `seed` in the names, so that every
    /// iteration pastes code that the app has not highlighted before: the app keeps the colours of what it has seen.
    private static func code(seed: Int) -> String {
        (0..<125).flatMap { index in
            [
                "func handler\(seed)x\(index)(_ value: Int) -> Int {",
                "    let doubled = value * 2",
                "    return doubled + \(index)",
                "}",
            ]
        }.joined(separator: "\n")
    }

    /// `paste_code_ms`: the median `paste-code` interval of ten pastes of 500 lines into an empty note. After each paste
    /// the test waits for the colours to be written (`debug.state`), and then empties the note for the next one. The
    /// first paste after the launch is the slowest (the grammars and their queries load then), and the median leaves it
    /// out.
    func testPasteFiveHundredLinesOfCode() throws {
        continueAfterFailure = false
        let app = PerfSupport.launch(fixture: "empty", dataDirectory: UITestSupport.makeDataDirectory())
        defer { app.terminate() }
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "the editor did not appear")

        let options = XCTMeasureOptions()
        options.iterationCount = Self.iterations
        measure(metrics: [PerfSupport.signpostMetric(named: "paste-code")], options: options) {
            self.seed += 1
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.code(seed: self.seed), forType: .string)
            app.typeKey("v", modifierFlags: .command)

            // The fence is in the note, and nothing is left to colour: the interval has ended or ends a moment later.
            let isDone = UITestSupport.wait(timeout: 30) {
                guard (editor.value as? String ?? "").hasPrefix("```swift\n") else { return false }
                let state = UITestSupport.debugState(in: app)
                return state["pendingPastes"] as? Int == 0 && state["pendingHighlights"] as? Int == 0
            }
            XCTAssertTrue(isDone, "the paste was not wrapped and coloured: \(UITestSupport.debugState(in: app))")
            Thread.sleep(forTimeInterval: 0.3)

            // An empty note for the next paste.
            app.typeKey("a", modifierFlags: .command)
            app.typeKey(.delete, modifierFlags: [])
            let isEmpty = UITestSupport.wait(timeout: 30) { (editor.value as? String ?? "").isEmpty }
            XCTAssertTrue(isEmpty, "the note was not emptied")
        }
        PerfSupport.attachScreenshot(of: app, named: "paste-code-after", to: self)
    }
}
