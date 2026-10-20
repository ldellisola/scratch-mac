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
}
