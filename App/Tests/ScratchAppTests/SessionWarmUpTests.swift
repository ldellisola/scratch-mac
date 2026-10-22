import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/code.md ("Late first colours"): after the first frame the coordinator hands the
/// texts of the notes that were open at launch to `CodeBlockStyler.warmUp`, which compiles the queries of the languages their
/// fences name on the highlight queue, so that the first block in such a language does not wait for its query (240 to 270 ms
/// for Swift, docs/decisions/0007). The coordinator runs on a real storage in a directory of its own.
@MainActor
final class SessionWarmUpTests: XCTestCase {
    private func note(_ body: String) -> Note {
        let earlier = Date(timeIntervalSinceNow: -3600)
        return Note(id: NoteID.make(), title: "", body: body, createdAt: earlier, modifiedAt: earlier)
    }

    private func spin(until condition: () -> Bool, seconds: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    func testWarmUpHighlightingNamesTheLanguagesOfTheOpenTabs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScratchWarmUpTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try ScratchStorage.open(LaunchOptions(dataDirectory: directory, isIsolated: true))
        let active = note("alpha")
        let rust = note("a note\n```rust\nfn main() {}\n```")
        let several = note("```Go\nx := 1\n```\n```ruby\nputs 1\n```\n```go\ny := 2\n```")
        let closed = note("```python\nx = 1\n```")
        try storage.notes.saveAll([active, rust, several, closed])
        let tabs = [active, rust, several].map { TabState(noteID: $0.id, selection: 0, scrollY: 0) }
        try storage.session.save(SessionState(tabs: tabs, activeTabIndex: 0))

        let editor = EditorViewController()
        let sidebar = SidebarViewController()
        let tabStrip = TabStripViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 800, height: 600))
        _ = sidebar.view
        _ = tabStrip.view
        defer { withExtendedLifetime(window) {} }
        let coordinator = SessionCoordinator(storage: storage, editor: editor, sidebar: sidebar, tabStrip: tabStrip)
        coordinator.restore()
        let styler = editor.textView.styler.codeBlockStyler
        XCTAssertEqual(styler.pendingWarmUps, 0, "nothing is compiled before the first frame is out")
        XCTAssertTrue(styler.warmedLanguages.isEmpty)

        coordinator.warmUpHighlighting()

        XCTAssertGreaterThan(styler.pendingWarmUps, 0, "asked for, on the highlight queue")
        spin(until: { styler.pendingWarmUps == 0 })
        XCTAssertEqual(styler.pendingWarmUps, 0)
        XCTAssertEqual(
            styler.warmedLanguages, [.rust, .go],
            "the languages in the open tabs: not Ruby (no grammar) and not Python (its note has no tab)")

        // The texts are handed over once: a second call has nothing to do.
        coordinator.warmUpHighlighting()
        XCTAssertEqual(styler.pendingWarmUps, 0)
    }
}
