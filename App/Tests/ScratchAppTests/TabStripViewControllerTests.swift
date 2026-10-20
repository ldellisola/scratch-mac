import AppKit
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/tabs.md, "The tab strip": one button per tab with the title as its label and
/// the active tab selected, tabs of 120 to 200 pt that share a crowded strip, and the strip's place above the editor.
@MainActor
final class TabStripViewControllerTests: XCTestCase {
    private func item(_ title: String, hasTitle: Bool = true, isDeleted: Bool = false) -> TabStripItem {
        TabStripItem(title: title, hasTitle: hasTitle, isDeleted: isDeleted)
    }

    /// Every `TabItemView` in `view`, left to right.
    private func tabViews(in view: NSView) -> [TabItemView] {
        func collect(_ view: NSView) -> [TabItemView] {
            let own = (view as? TabItemView).map { [$0] } ?? []
            return own + view.subviews.flatMap(collect)
        }
        return collect(view).sorted { $0.frame.minX < $1.frame.minX }
    }

    /// A tab strip in an editor area in an 800 x 600 window that is never shown. Keep `window` alive for as long as the
    /// area is used.
    private func makeHostedArea() -> (
        area: EditorAreaViewController, strip: TabStripViewController, editor: EditorViewController, window: NSWindow
    ) {
        let strip = TabStripViewController()
        let editor = EditorViewController()
        let area = EditorAreaViewController(tabStrip: strip, editor: editor)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = area
        // Assigning the content view controller resizes the window to the controller's view, so size it afterwards.
        window.setContentSize(NSSize(width: 800, height: 600))
        return (area, strip, editor, window)
    }

    // MARK: The tabs

    /// Each tab is one button that says its title, and the active one is the selected one.
    func testShowMakesOneAccessibleButtonPerTab() {
        let strip = TabStripViewController()
        strip.show([item("Deploy checklist"), item("curl -X POST", hasTitle: false)], activeIndex: 1)

        let tabs = tabViews(in: strip.view)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs.map { $0.accessibilityLabel() }, ["Deploy checklist", "curl -X POST"])
        XCTAssertEqual(tabs.map { $0.isAccessibilitySelected() }, [false, true])
        for tab in tabs {
            XCTAssertTrue(tab.isAccessibilityElement())
            XCTAssertEqual(tab.accessibilityRole(), .button)
            XCTAssertEqual(tab.accessibilityIdentifier(), AccessibilityID.tabItem)
        }
    }

    /// A change of a title does not rebuild the tabs, and a change of the active tab moves the selection.
    func testShowReusesTheTabViews() {
        let strip = TabStripViewController()
        strip.show([item("A"), item("B")], activeIndex: 0)
        let before = tabViews(in: strip.view)

        strip.show([item("A2"), item("B")], activeIndex: 1)
        let after = tabViews(in: strip.view)

        XCTAssertEqual(before.count, 2)
        XCTAssertTrue(zip(before, after).allSatisfy { $0 === $1 }, "the tab views were replaced")
        XCTAssertEqual(after.map { $0.accessibilityLabel() }, ["A2", "B"])
        XCTAssertEqual(after.map { $0.isAccessibilitySelected() }, [false, true])
    }

    func testShowAddsAndRemovesTabs() {
        let strip = TabStripViewController()
        strip.show([item("A"), item("B"), item("C")], activeIndex: 2)
        XCTAssertEqual(tabViews(in: strip.view).count, 3)

        strip.show([item("A")], activeIndex: 0)

        XCTAssertEqual(tabViews(in: strip.view).count, 1)
    }

    func testClickingATabReportsItsIndex() {
        let strip = TabStripViewController()
        strip.show([item("A"), item("B")], activeIndex: 0)
        var selected: [Int] = []
        strip.onSelect = { selected.append($0) }

        XCTAssertTrue(tabViews(in: strip.view)[1].accessibilityPerformPress())

        XCTAssertEqual(selected, [1])
    }

    /// A short title still gets 120 pt, a long one is cut at 200 pt.
    func testTabWidthsStayBetween120And200() {
        let strip = TabStripViewController()
        strip.show([item("a"), item(String(repeating: "long title ", count: 40))], activeIndex: 0)

        let widths = tabViews(in: strip.view).map(\.idealWidth)

        XCTAssertEqual(widths, [120, 200])
    }

    // MARK: The widths of crowded tabs

    func testTabsKeepTheirWidthWhenTheyFit() {
        XCTAssertEqual(TabStripLayout.widths(ideal: [140, 200], available: 400), [140, 200])
        XCTAssertEqual(TabStripLayout.widths(ideal: [], available: 0), [])
    }

    /// The widest tab gives up width first: the tabs that are wider than the common width are cut to it.
    func testWidestTabsAreCutBackFirst() throws {
        let widths = TabStripLayout.widths(ideal: [140, 200], available: 300)

        XCTAssertEqual(widths.count, 2)
        XCTAssertEqual(widths[0], 140, accuracy: 0.01)
        XCTAssertEqual(widths[1], 160, accuracy: 0.01)
    }

    func testTabsNeverGetNarrowerThanTheMinimum() {
        let widths = TabStripLayout.widths(ideal: [120, 120, 120], available: 90)

        XCTAssertEqual(widths, [TabStripLayout.minimumWidth, TabStripLayout.minimumWidth, TabStripLayout.minimumWidth])
    }

    // MARK: The strip above the editor

    /// The strip is 32 pt tall, 12 pt from the left and 8 pt from the top, as wide as its tabs, and the editor is
    /// below it.
    func testStripSitsAboveTheEditor() {
        let host = makeHostedArea()
        defer { withExtendedLifetime(host.window) {} }
        host.strip.show([item("Deploy checklist"), item("curl -X POST", hasTitle: false)], activeIndex: 0)
        host.area.view.layoutSubtreeIfNeeded()

        let container = host.area.view.bounds
        let strip = host.strip.view.frame
        let editor = host.editor.view.frame
        let expectedWidth = host.strip.view.intrinsicContentSize.width
        XCTAssertGreaterThan(expectedWidth, 200, "the strip wants a width for its tabs")
        XCTAssertEqual(strip.height, 32, accuracy: 0.5)
        XCTAssertEqual(strip.minX, 12, accuracy: 0.5)
        XCTAssertEqual(container.maxY - strip.maxY, 8, accuracy: 0.5, "the space above the strip")
        XCTAssertEqual(strip.width, expectedWidth, accuracy: 0.5, "the strip hugs its tabs")
        XCTAssertEqual(editor.maxY, strip.minY - 4, accuracy: 0.5, "the editor starts below the strip")
        XCTAssertEqual(editor.minY, 0, accuracy: 0.5)
        XCTAssertEqual(editor.width, container.width, accuracy: 0.5)

        // The tabs fill the strip's height but for 3 pt above and below them, and start 3 pt from its left edge: the glass
        // gives its content the whole strip.
        let tabs = tabViews(in: host.strip.view)
        XCTAssertEqual(tabs.count, 2)
        let tab = tabs[0]
        let inStrip = tab.superview?.convert(tab.frame, to: host.strip.view) ?? .zero
        XCTAssertEqual(inStrip.minX, 3, accuracy: 0.5, "the first tab's left edge in the strip")
        XCTAssertEqual(inStrip.minY, 3, accuracy: 0.5, "the first tab's bottom edge in the strip")
        XCTAssertEqual(inStrip.height, 26, accuracy: 0.5, "the first tab's height")
    }

    /// Twelve tabs do not fit in 800 pt: the strip stops 12 pt short of the right edge and the tabs share it.
    func testManyTabsShareTheStrip() {
        let host = makeHostedArea()
        defer { withExtendedLifetime(host.window) {} }
        let items = (1...12).map { item("Note number \($0) has a title") }
        host.strip.show(items, activeIndex: 0)
        host.area.view.layoutSubtreeIfNeeded()

        let container = host.area.view.bounds
        let strip = host.strip.view.frame
        XCTAssertEqual(strip.maxX, container.maxX - 12, accuracy: 0.5, "the strip stops short of the right edge")
        let tabs = tabViews(in: host.strip.view)
        XCTAssertEqual(tabs.count, 12)
        XCTAssertTrue(tabs.allSatisfy { $0.frame.width >= TabStripLayout.minimumWidth - 0.5 })
        XCTAssertLessThanOrEqual(
            tabs.last?.frame.maxX ?? .infinity, strip.width + 0.5, "the last tab is inside the strip")
    }
}
