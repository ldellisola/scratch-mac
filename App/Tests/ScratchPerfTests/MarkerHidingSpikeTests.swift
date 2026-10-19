import XCTest

/// THROWAWAY, branch spike/textkit only (plan 1 task 10, ADR 0001). One screenshot per TextKit and marker-hiding
/// technique, of the `typical` fixture, whose "Deploy checklist" note has one bold run (`**don't deploy ...**`).
@MainActor
final class MarkerHidingSpikeTests: XCTestCase {
    func testPlainTextKit1() { capture("tk1-plain", textKit: "1", technique: nil) }
    func testGlyphsTextKit1() { capture("tk1-glyphs", textKit: "1", technique: "glyphs") }
    func testTinyTextKit1() { capture("tk1-tiny", textKit: "1", technique: "tiny") }
    func testPlainTextKit2() { capture("tk2-plain", textKit: "2", technique: nil) }
    func testParagraphTextKit2() { capture("tk2-paragraph", textKit: "2", technique: "paragraph") }
    func testTinyTextKit2() { capture("tk2-tiny", textKit: "2", technique: "tiny") }

    private func capture(_ name: String, textKit: String, technique: String?) {
        continueAfterFailure = false
        let app = XCUIApplication()
        var arguments = [
            "-ScratchDataDir", UITestSupport.makeDataDirectory().path,
            "-ScratchFixture", "typical",
            "-ScratchAppearance", "light",
            "-ScratchTextKit", textKit,
        ]
        if let technique { arguments += ["-ScratchSpikeHide", technique] }
        app.launchArguments = arguments
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(UITestSupport.editor(in: app).waitForExistence(timeout: 30), "the editor did not appear")
        XCTAssertTrue(
            UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app).count == 6 },
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        Thread.sleep(forTimeInterval: 1.5)
        PerfSupport.attachScreenshot(of: app, named: name, to: self)
    }
}
