import XCTest

/// Launches Scratch for a UI test, always in a data directory of its own, so no UI test ever touches real data
/// (spec §9.4, AGENTS.md section 3).
enum UITestSupport {
    /// The app's bundle identifier, to find its running process.
    static let bundleIdentifier = "io.github.ldellisola.Scratch"

    /// Launches the app with a new, empty data directory seeded with `fixture` (a `Fixture` raw value such as
    /// `typical`), in the given appearance (`light` or `dark`, the `-ScratchAppearance` values). Returns the running
    /// app.
    @MainActor
    static func launch(fixture: String, appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ScratchDataDir", makeDataDirectory().path,
            "-ScratchFixture", fixture,
            "-ScratchAppearance", appearance,
        ]
        app.launch()
        return app
    }

    /// Launches the app again on the data directory that `app` was launched with, and without a fixture, so what the
    /// first run saved is restored. `app` must have quit or been killed. Returns the new running app.
    @MainActor
    static func relaunch(sameDataAs app: XCUIApplication) -> XCUIApplication {
        let arguments = app.launchArguments
        guard let flag = arguments.firstIndex(of: "-ScratchDataDir"), flag + 1 < arguments.count else {
            preconditionFailure("relaunch(sameDataAs:) needs an app that was launched with -ScratchDataDir")
        }
        let relaunched = XCUIApplication()
        relaunched.launchArguments = [
            "-ScratchDataDir", arguments[flag + 1],
            "-ScratchAppearance", "light",
        ]
        relaunched.launch()
        return relaunched
    }

    /// The editor's text view. Its `value` is the note's text.
    @MainActor
    static func editor(in app: XCUIApplication) -> XCUIElement {
        app.textViews.matching(identifier: AccessibilityID.editorTextView).firstMatch
    }

    /// The title field above the editor. Its `value` is the note's title.
    @MainActor
    static func titleField(in app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(identifier: AccessibilityID.titleField).firstMatch
    }

    /// What the app publishes about its editor in the `debug.state` element (`DebugStateElement`, only in an isolated
    /// data directory): `fontSize` (points), `scrollAnchor` (the UTF-16 offset of the first visible character),
    /// `readOnly`, `scrollY` (the clip view's origin y, in points) and `topInset` (the scroll view's top content
    /// inset: a note at its top has `scrollY == -topInset`), `pendingHighlights` (code colours that are asked for and not
    /// written yet) and `pendingPastes` (pastes that are not classified yet): both are zero when a paste is done,
    /// `pendingPreviews` (images that are waiting to be decoded or being decoded: zero when every preview is made), and
    /// `attachments`, a list with one `{"id": ..., "copied": ..., "fileExists": ...}` for each token in the note's text,
    /// where `copied` says that the row has the copy in place and `fileExists` that Scratch's own copy is on disk. The app computes it when asked, so it is as current as the app.
    /// Empty when the element is missing.
    @MainActor
    static func debugState(in app: XCUIApplication) -> [String: Any] {
        let element = app.descendants(matching: .any).matching(identifier: AccessibilityID.debugState).firstMatch
        guard element.waitForExistence(timeout: 5), let json = element.value as? String,
            let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        else { return [:] }
        return object
    }

    /// The tabs of the tab strip, from left to right: the buttons with the identifier `AccessibilityID.tabItem`. Each
    /// one's `label` is the tab's title, and `isSelected` is true for the active tab.
    @MainActor
    static func tabs(in app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(identifier: AccessibilityID.tabItem).allElementsBoundByIndex
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// The close buttons of the tab strip, from left to right: the buttons with the identifier `AccessibilityID.tabClose`.
    /// Each one's `label` is "Close" and the title of its tab (plan 6 task 8).
    @MainActor
    static func closeButtons(in app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(identifier: AccessibilityID.tabClose).allElementsBoundByIndex
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Which part of the window has the keyboard, from `debug.state`'s `firstResponder`: `editor`, `title`, `search`,
    /// `sidebar` (the note list) or `other`. Empty when the element is missing.
    @MainActor
    static func firstResponder(in app: XCUIApplication) -> String {
        debugState(in: app)["firstResponder"] as? String ?? ""
    }

    /// The titles of the tabs from left to right.
    @MainActor
    static func tabTitles(in app: XCUIApplication) -> [String] {
        tabs(in: app).map { $0.label.isEmpty ? $0.title : $0.label }
    }

    /// The title of the active tab, or nil when no tab is selected.
    @MainActor
    static func activeTabTitle(in app: XCUIApplication) -> String? {
        tabs(in: app).first { $0.isSelected }.map { $0.label.isEmpty ? $0.title : $0.label }
    }

    /// The index of the active tab (0 is the leftmost), or nil when no tab is selected.
    @MainActor
    static func activeTabIndex(in app: XCUIApplication) -> Int? {
        tabs(in: app).firstIndex { $0.isSelected }
    }

    /// The toolbar's "new note" button. A toolbar item without a view has no accessibility identifier of its own: AppKit
    /// reports its item identifier (`AccessibilityID.newNoteButton`) as the identifier, and its label as the title or
    /// label, so any of the three finds it.
    @MainActor
    static func newNoteButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@ OR title == %@", AccessibilityID.newNoteButton, "New Note",
                "New Note")
        ).firstMatch
    }

    /// The toolbar's pin button, which pins the note of the active tab or unpins it. A toolbar item without a view has no
    /// accessibility identifier of its own (see `newNoteButton(in:)`), so it is found by its item identifier or by its
    /// label, which is "Pin" while the note is not pinned and "Unpin" while it is.
    @MainActor
    static func pinButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@ OR label == %@ OR title == %@ OR title == %@",
                AccessibilityID.pinButton, "Pin", "Unpin", "Pin", "Unpin")
        ).firstMatch
    }

    /// The toolbar's paperclip, which attaches files. A view-less toolbar item like the others: found by its item
    /// identifier or its label, "Attach File".
    @MainActor
    static func attachButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@ OR title == %@", AccessibilityID.attachButton, "Attach File",
                "Attach File")
        ).firstMatch
    }

    /// The search field at the top of the sidebar. Its `value` is the text typed in it.
    @MainActor
    static func searchField(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.sidebarSearch).firstMatch
    }

    /// The titles of the sidebar's groups from top to bottom: "Pinned", "Today", "Yesterday" and "Earlier", as far as
    /// they are shown. The header of Recently Deleted is not among them: it has its own identifier, see
    /// `recentlyDeletedHeader(in:)`.
    @MainActor
    static func sidebarGroupTitles(in app: XCUIApplication) -> [String] {
        app.staticTexts.matching(identifier: AccessibilityID.sidebarGroup).allElementsBoundByIndex
            .sorted { $0.frame.minY < $1.frame.minY }
            .map { text(of: $0) }
    }

    /// The header of Recently Deleted at the bottom of the sidebar, which exists only while a note is deleted. Its text
    /// reads "Recently Deleted (N)" (`text(of:)`), and a click on it shows or hides the deleted notes.
    @MainActor
    static func recentlyDeletedHeader(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(identifier: AccessibilityID.recentlyDeletedHeader).firstMatch
    }

    /// The edit time that the sidebar shows on the row of `title`, a title element from `sidebarRow(titled:in:)`: the
    /// time label on the same line. Nil when no label is there.
    @MainActor
    static func sidebarRowTime(besides title: XCUIElement, in app: XCUIApplication) -> String? {
        let line = title.frame.midY
        return app.staticTexts.matching(identifier: AccessibilityID.sidebarRowTime).allElementsBoundByIndex
            .first { abs($0.frame.midY - line) < 8 }
            .map { text(of: $0) }
    }

    /// The title texts of the sidebar rows, in the order the accessibility tree lists them.
    @MainActor
    static func sidebarTitles(in app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(identifier: AccessibilityID.sidebarRowTitle)
    }

    /// The sidebar rows' preview lines from top to bottom.
    @MainActor
    static func sidebarPreviewTexts(in app: XCUIApplication) -> [String] {
        app.staticTexts.matching(identifier: AccessibilityID.sidebarRowPreview).allElementsBoundByIndex
            .sorted { $0.frame.minY < $1.frame.minY }
            .map { text(of: $0) }
    }

    /// The sidebar rows' titles from top to bottom.
    @MainActor
    static func sidebarTitleTexts(in app: XCUIApplication) -> [String] {
        sidebarTitles(in: app).allElementsBoundByIndex
            .sorted { $0.frame.minY < $1.frame.minY }
            .map { text(of: $0) }
    }

    /// The sidebar row whose title is exactly `title`.
    @MainActor
    static func sidebarRow(titled title: String, in app: XCUIApplication) -> XCUIElement {
        sidebarTitles(in: app).matching(NSPredicate(format: "value == %@ OR label == %@", title, title)).firstMatch
    }

    /// The sidebar row whose title contains `fragment`.
    @MainActor
    static func sidebarRow(titleContaining fragment: String, in app: XCUIApplication) -> XCUIElement {
        sidebarTitles(in: app)
            .matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", fragment, fragment)).firstMatch
    }

    /// What an element shows as text: its value, or else its label.
    @MainActor
    static func text(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    /// Polls `condition` every 0.1 s until it is true or `timeout` seconds have passed. Returns whether it became
    /// true.
    @MainActor
    static func wait(timeout: TimeInterval = 10, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }

    /// Waits up to five seconds until the editor's text is `expected`, then asserts that it is, so that a failure says
    /// what the text was. Typing and the editing commands are applied by the app a moment after the test sends the key.
    @MainActor
    static func expectText(
        _ expected: String, in editor: XCUIElement, _ message: String, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(5)
        while (editor.value as? String) != expected, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(editor.value as? String, expected, message, file: file, line: line)
    }

    /// A new directory under the temporary directory (not created yet: the app creates it). A sandboxed test runner's
    /// own temporary directory lives inside its container, which the app is not allowed to write to, so that case uses
    /// /tmp instead. The performance tests use it too.
    static func makeDataDirectory() -> URL {
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let base = sandboxed ? URL(fileURLWithPath: "/tmp", isDirectory: true) : FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ScratchUITests-\(UUID().uuidString)", isDirectory: true)
    }
}
