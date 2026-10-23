import AppKit
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/tabs.md, "The tab strip": one button per tab with the title as its label and
/// the active tab selected, tabs of 120 to 200 pt that share a crowded strip, and the strip's place in the toolbar row
/// (plan 6 task 7: a toolbar item as wide as its tabs and never wider than the room the toolbar leaves).
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

    /// The strip's view in a 800 x 60 window, placed as a toolbar item's view is: by its own width and height constraints
    /// and nothing else. Keep `window` alive for as long as the strip is used.
    private func makeHostedStrip() -> (strip: TabStripViewController, container: NSView, window: NSWindow) {
        let strip = TabStripViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 60))
        let view = strip.view
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 60), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.setContentSize(NSSize(width: 800, height: 60))
        container.layoutSubtreeIfNeeded()
        return (strip, container, window)
    }

    /// What a failure message needs to say about the strip's width: the sizes and the constraints that decide it.
    private func describeStrip(_ strip: TabStripViewController) -> String {
        guard let stripView = strip.view as? TabStripView else { return "the strip's view is not a TabStripView" }
        let glass = stripView.glassView
        let content = glass.contentView
        let horizontal = stripView.constraintsAffectingLayout(for: .horizontal).map { String(describing: $0) }
        return """
            strip frame \(stripView.frame), intrinsic \(stripView.intrinsicContentSize), fitting \(stripView.fittingSize)
            glass frame \(glass.frame), intrinsic \(glass.intrinsicContentSize), \
            hugging \(glass.contentHuggingPriority(for: .horizontal).rawValue), \
            translates \(glass.translatesAutoresizingMaskIntoConstraints)
            content frame \(content?.frame ?? .zero), translates \(content?.translatesAutoresizingMaskIntoConstraints ?? false)
            horizontal constraints: \(horizontal.joined(separator: "; "))
            """
    }

    private func mainWindow() throws -> NSWindow {
        try XCTUnwrap(NSApp.windows.first { $0.contentViewController is MainSplitViewController })
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

    /// A tab is sized to its title with room to spare: the label is wider than the text it draws plus the 2 pt that a
    /// text field keeps free at each side (the first screenshots showed "Deploy check..." in a tab with room).
    func testTitleFitsItsTab() {
        for (title, hasTitle) in [("Deploy checklist", true), ("curl -X POST", false)] {
            let tab = TabItemView(frame: .zero)
            tab.configure(item(title, hasTitle: hasTitle), isActive: true)
            tab.frame = NSRect(x: 0, y: 0, width: tab.idealWidth, height: 26)
            tab.layoutSubtreeIfNeeded()

            let font = tab.titleField.font ?? NSFont.systemFont(ofSize: 12)
            let needed = NSAttributedString(string: title, attributes: [.font: font]).size().width
            XCTAssertGreaterThanOrEqual(tab.titleField.frame.width, needed + 4, "the label of \(title)")
        }
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

    // MARK: The strip in the toolbar row

    /// The strip is 34 pt tall, as wide as its tabs, and its tabs fill it but for 3 pt above and below them and 3 pt at the
    /// left: the glass gives its content the whole strip. Nothing but its two constraints places it (a toolbar item's view).
    func testStripIsAsWideAsItsTabs() throws {
        let host = makeHostedStrip()
        defer { withExtendedLifetime(host.window) {} }
        host.strip.show([item("Deploy checklist"), item("curl -X POST", hasTitle: false)], activeIndex: 0)
        host.container.layoutSubtreeIfNeeded()

        let strip = host.strip.view.frame
        let expectedWidth = try XCTUnwrap(host.strip.view as? TabStripView).preferredWidth
        XCTAssertGreaterThan(expectedWidth, 200, "the strip wants a width for its tabs")
        XCTAssertEqual(TabStripViewController.height, 34)
        XCTAssertEqual(strip.height, 34, accuracy: 0.5)
        XCTAssertEqual(strip.minX, 12, accuracy: 0.5)
        XCTAssertEqual(
            strip.width, expectedWidth, accuracy: 0.5, "the strip hugs its tabs. \(describeStrip(host.strip))")

        let tabs = tabViews(in: host.strip.view)
        XCTAssertEqual(tabs.count, 2)
        let tab = tabs[0]
        let inStrip = tab.superview?.convert(tab.frame, to: host.strip.view) ?? .zero
        XCTAssertEqual(inStrip.minX, 3, accuracy: 0.5, "the first tab's left edge in the strip")
        XCTAssertEqual(inStrip.minY, 3, accuracy: 0.5, "the first tab's bottom edge in the strip")
        XCTAssertEqual(inStrip.height, 28, accuracy: 0.5, "the first tab's height")
    }

    /// The strip is never wider than the room that the toolbar leaves it (`maximumWidth`), and the tabs share what it has.
    func testStripIsNeverWiderThanItsMaximum() {
        let host = makeHostedStrip()
        defer { withExtendedLifetime(host.window) {} }
        let items = (1...12).map { item("Note number \($0) has a title") }
        host.strip.show(items, activeIndex: 0)
        host.container.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.strip.view.frame.width, 1_000, "twelve tabs want more than the window has")

        host.strip.maximumWidth = 700
        host.container.layoutSubtreeIfNeeded()

        let strip = host.strip.view.frame
        XCTAssertEqual(strip.width, 700, accuracy: 0.5, describeStrip(host.strip))
        let tabs = tabViews(in: host.strip.view)
        XCTAssertEqual(tabs.count, 12)
        XCTAssertTrue(tabs.allSatisfy { $0.frame.width >= TabStripLayout.minimumWidth - 0.5 })
        XCTAssertLessThanOrEqual(
            tabs.last?.frame.maxX ?? .infinity, strip.width + 0.5, "the last tab is inside the strip")

        // A narrower window gives a narrower strip, and a wider one gives the width back, up to what the tabs want.
        host.strip.maximumWidth = 400
        host.container.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.strip.view.frame.width, 400, accuracy: 0.5)
        host.strip.show([item("A"), item("B")], activeIndex: 0)
        host.container.layoutSubtreeIfNeeded()
        XCTAssertLessThan(host.strip.view.frame.width, 400, "two tabs do not fill a strip that has room for more")
    }

    /// Whatever the room, the strip keeps a width that shows a tab and the "+" button.
    func testStripKeepsAFloorOfWidth() {
        let host = makeHostedStrip()
        defer { withExtendedLifetime(host.window) {} }
        host.strip.show([item("A"), item("B"), item("C")], activeIndex: 0)

        host.strip.maximumWidth = 10
        host.container.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.strip.view.frame.width, TabStripLayout.minimumStripWidth, accuracy: 0.5)
    }

    /// What the toolbar keeps for its buttons: the window's width less where the strip starts and less the room of the pin,
    /// the paperclip and the "new note" capsules, with a floor.
    func testMaximumWidthLeavesRoomForTheButtons() {
        XCTAssertEqual(
            TabStripLayout.maximumWidth(windowWidth: 1_024, leading: 252), 1_024 - 252 - TabStripLayout.trailingReserve)
        XCTAssertEqual(TabStripLayout.maximumWidth(windowWidth: 300, leading: 252), TabStripLayout.minimumStripWidth)
        XCTAssertGreaterThanOrEqual(
            TabStripLayout.trailingReserve, 150, "the two button capsules, the space between them and the margins")
    }

    /// The toolbar's items are, from the left, the sidebar button, the tracking separator, the strip, the flexible space, the
    /// pin and the paperclip, a space and the "new note" button (the two glass groups of the toolbar).
    func testToolbarItemOrder() {
        let controller = ToolbarController(tabStrip: TabStripViewController())
        // Not `makeToolbar()`: toolbars with one identifier share their configuration, and the window has the real one.
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("TabStripViewControllerTests"))

        XCTAssertEqual(
            controller.toolbarDefaultItemIdentifiers(toolbar).map(\.rawValue),
            [
                NSToolbarItem.Identifier.toggleSidebar.rawValue,
                NSToolbarItem.Identifier.sidebarTrackingSeparator.rawValue, AccessibilityID.tabStrip,
                NSToolbarItem.Identifier.flexibleSpace.rawValue, AccessibilityID.pinButton,
                AccessibilityID.attachButton, NSToolbarItem.Identifier.space.rawValue, AccessibilityID.newNoteButton,
            ])
    }

    /// The strip is a toolbar item whose view is the strip: no border and no shared glass of the toolbar's (the strip has its
    /// own glass capsule), kept visible longest of the items it shares the toolbar with, and the buttons are never moved into
    /// the overflow menu.
    func testTabStripIsAToolbarItem() throws {
        let strip = TabStripViewController()
        let controller = ToolbarController(tabStrip: strip)
        // Not `makeToolbar()`: toolbars with one identifier share their configuration, and the window has the real one.
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("TabStripViewControllerTests"))

        let item = try XCTUnwrap(
            controller.toolbar(
                toolbar, itemForItemIdentifier: NSToolbarItem.Identifier(AccessibilityID.tabStrip),
                willBeInsertedIntoToolbar: true))

        XCTAssertTrue(item.view === strip.view, "the item's view is the strip's")
        XCTAssertTrue(item.view is TabStripView)
        XCTAssertFalse(item.isBordered, "one glass capsule round the tabs: the strip's own")
        XCTAssertEqual(item.visibilityPriority, .high)
        for identifier in [AccessibilityID.pinButton, AccessibilityID.attachButton, AccessibilityID.newNoteButton] {
            let button = try XCTUnwrap(
                controller.toolbar(
                    toolbar, itemForItemIdentifier: NSToolbarItem.Identifier(identifier),
                    willBeInsertedIntoToolbar: true
                ), identifier)
            XCTAssertEqual(button.visibilityPriority, .user, "\(identifier) is never moved into the overflow menu")
        }
    }

    /// The real window's toolbar has the strip, outside the editor area: the editor starts at the top of the area.
    func testTheWindowsToolbarHoldsTheStrip() throws {
        let window = try mainWindow()
        let toolbar = try XCTUnwrap(window.toolbar)
        let split = try XCTUnwrap(window.contentViewController as? MainSplitViewController)

        let item = try XCTUnwrap(
            toolbar.items.first { $0.view is TabStripView },
            "the toolbar's items: \(toolbar.items.map(\.itemIdentifier.rawValue))")

        XCTAssertFalse(
            try XCTUnwrap(item.view).isDescendant(of: split.splitViewItems[1].viewController.view),
            "the strip is no longer in the editor area")
        let identifiers = toolbar.items.map(\.itemIdentifier.rawValue)
        let order = [AccessibilityID.tabStrip, AccessibilityID.pinButton, AccessibilityID.attachButton]
        let indices = order.compactMap { identifiers.firstIndex(of: $0) }
        XCTAssertEqual(indices.count, 3, "the toolbar's items: \(identifiers)")
        XCTAssertEqual(indices, indices.sorted(), "the strip, then the pin and the paperclip: \(identifiers)")
        XCTAssertNotNil(identifiers.firstIndex(of: AccessibilityID.newNoteButton))
    }

    /// The editor area is the editor and nothing else: the editor fills it, from its very top, and has the toolbar in its own
    /// safe area (its title field sits 10 pt below that).
    func testEditorAreaIsTheEditorAlone() {
        let editor = EditorViewController()
        let area = EditorAreaViewController(editor: editor)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = area
        window.setContentSize(NSSize(width: 800, height: 600))
        defer { withExtendedLifetime(window) {} }

        area.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(editor.view.frame, area.view.bounds, "the editor fills the area")
        XCTAssertEqual(area.children.count, 1)
    }
}
