import XCTest

@testable import Scratch

/// Hosted in the app, on its real window. Spec §6.1: the toolbar floats over the editor and there is no other chrome.
/// The editor's scroll view starts below the toolbar, and macOS 26 then draws a hard scroll pocket in the titlebar,
/// with a one point line across the editor at its bottom. `TitlebarPocket` hides the pocket. These tests fail when the
/// pocket is visible, and also when it cannot be found any more (a later macOS may rename its classes), because then
/// nothing hides the line.
@MainActor
final class TitlebarPocketTests: XCTestCase {
    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func mainWindow() throws -> (window: NSWindow, controller: MainSplitViewController) {
        let window = try XCTUnwrap(NSApp.windows.first { $0.contentViewController is MainSplitViewController })
        let controller = try XCTUnwrap(window.contentViewController as? MainSplitViewController)
        return (window, controller)
    }

    /// The views of every titlebar background directly in the split view, one per line, for a failure message.
    private func titlebarBackgrounds(of controller: MainSplitViewController) -> String {
        func lines(_ view: NSView, depth: Int) -> [String] {
            let name = NSStringFromClass(type(of: view))
            let line = String(repeating: "  ", count: depth) + "\(name) hidden=\(view.isHidden) frame=\(view.frame)"
            return [line] + view.subviews.flatMap { lines($0, depth: depth + 1) }
        }
        return controller.splitView.subviews
            .filter { NSStringFromClass(type(of: $0)).contains("Titlebar") }
            .flatMap { lines($0, depth: 0) }
            .joined(separator: "\n")
    }

    private func assertPocketIsHidden(
        _ controller: MainSplitViewController, _ moment: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let pockets = TitlebarPocket.pockets(in: controller.splitView)
        let views = titlebarBackgrounds(of: controller)
        XCTAssertFalse(
            pockets.isEmpty, "\(moment): no scroll pocket in the titlebar. Its views:\n\(views)", file: file, line: line
        )
        XCTAssertTrue(
            pockets.allSatisfy { $0.isHidden },
            "\(moment): a scroll pocket is visible. The titlebar's views:\n\(views)",
            file: file, line: line)
    }

    func testTheTitlebarPocketIsHiddenOnceTheWindowIsShown() throws {
        let (_, controller) = try mainWindow()
        spin(1)

        assertPocketIsHidden(controller, "after launch")
    }

    func testTheTitlebarPocketStaysHiddenAfterAResize() throws {
        let (window, controller) = try mainWindow()
        let size = try XCTUnwrap(window.contentView).frame.size
        defer { window.setContentSize(size) }
        spin(0.5)

        window.setContentSize(NSSize(width: 900, height: 560))
        controller.view.layoutSubtreeIfNeeded()
        spin(0.5)

        assertPocketIsHidden(controller, "after a resize")
    }

    func testTheTitlebarPocketStaysHiddenWhenTheSidebarIsCollapsedAndShownAgain() throws {
        let (_, controller) = try mainWindow()
        let sidebar = controller.splitViewItems[0]
        defer { sidebar.isCollapsed = false }
        spin(0.5)

        sidebar.isCollapsed = true
        spin(0.5)
        assertPocketIsHidden(controller, "with the sidebar collapsed")

        sidebar.isCollapsed = false
        spin(0.5)
        assertPocketIsHidden(controller, "with the sidebar shown again")
    }
}
