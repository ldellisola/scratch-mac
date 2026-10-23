import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/accessibility.md ("The window") and docs/features/sidebar.md: what VoiceOver reads
/// for a sidebar row ("<title>, <time>, <preview>", with ", pinned"), that the header of Recently Deleted is a button with a
/// count and a state and that a press on it, or on a row, does what a click does (spec §6.2, plan 6 task 8). The row's label
/// is the cell's, which the UI tests read from outside (`AccessibilityUITests`).
@MainActor
final class SidebarRowViewsTests: XCTestCase {
    private func summary(
        title: String = "Groceries", hasTitle: Bool = true, preview: String = "milk, eggs, coffee beans",
        modifiedAt: Date = Date(), pinned: Bool = false, deleted: Bool = false
    ) -> NoteSummary {
        NoteSummary(
            id: NoteID.make(), displayTitle: title, hasTitle: hasTitle, preview: preview, modifiedAt: modifiedAt,
            pinnedAt: pinned ? Date() : nil, deletedAt: deleted ? Date() : nil)
    }

    // MARK: A note's row

    func testRowLabelReadsTitleTimeAndPreview() {
        let now = Date()
        let row = summary(modifiedAt: now)
        let time = NoteRowCellView.timeText(for: row, now: now)

        XCTAssertFalse(time.isEmpty)
        XCTAssertEqual(
            NoteRowCellView.accessibilityLabel(for: row, now: now), "Groceries, \(time), milk, eggs, coffee beans")
    }

    func testPinnedRowSaysSo() {
        let now = Date()
        let row = summary(pinned: true)
        let time = NoteRowCellView.timeText(for: row, now: now)

        XCTAssertEqual(
            NoteRowCellView.accessibilityLabel(for: row, now: now),
            "Groceries, \(time), milk, eggs, coffee beans, pinned")
        // A pin that a deleted note kept is not shown, and not said.
        XCTAssertFalse(
            NoteRowCellView.accessibilityLabel(for: summary(pinned: true, deleted: true), now: now).hasSuffix("pinned"))
    }

    func testRowWithoutPreviewHasNoEmptyPart() {
        let now = Date()
        let row = summary(preview: "")
        let time = NoteRowCellView.timeText(for: row, now: now)

        XCTAssertEqual(NoteRowCellView.accessibilityLabel(for: row, now: now), "Groceries, \(time)")
    }

    func testNoteWithNoTextIsUntitled() {
        let now = Date()
        let row = summary(title: "", hasTitle: false, preview: "")
        let time = NoteRowCellView.timeText(for: row, now: now)

        XCTAssertEqual(NoteRowCellView.accessibilityLabel(for: row, now: now), "Untitled, \(time)")
    }

    func testAPressOnARowOpensTheNote() {
        let cell = NoteRowCellView()
        XCTAssertFalse(cell.accessibilityPerformPress(), "nothing is wired yet")
        var opened = 0
        cell.onPress = { opened += 1 }

        XCTAssertTrue(cell.accessibilityPerformPress())
        XCTAssertEqual(opened, 1)
    }

    // MARK: The headers

    func testRecentlyDeletedHeaderIsAButtonWithItsCountAndState() {
        let cell = GroupRowCellView()

        cell.configureRecentlyDeleted(count: 2, expanded: false)
        XCTAssertEqual(cell.label.accessibilityRole(), .button)
        XCTAssertEqual(cell.label.accessibilityLabel(), "Recently Deleted, 2 notes")
        XCTAssertFalse(cell.label.isAccessibilityExpanded())
        XCTAssertEqual(cell.label.stringValue, "Recently Deleted (2)", "what is shown is as it was")
        XCTAssertEqual(cell.label.accessibilityIdentifier(), AccessibilityID.recentlyDeletedHeader)

        cell.configureRecentlyDeleted(count: 1, expanded: true)
        XCTAssertEqual(cell.label.accessibilityLabel(), "Recently Deleted, 1 note")
        XCTAssertTrue(cell.label.isAccessibilityExpanded())
    }

    func testAPressOnTheRecentlyDeletedHeaderShowsOrHidesItsNotes() {
        let cell = GroupRowCellView()
        cell.configureRecentlyDeleted(count: 3, expanded: false)
        XCTAssertFalse(cell.label.accessibilityPerformPress(), "nothing is wired yet")
        var toggles = 0
        cell.onPress = { toggles += 1 }

        XCTAssertTrue(cell.label.accessibilityPerformPress())
        XCTAssertEqual(toggles, 1)
    }

    func testAnOrdinaryHeaderIsPlainTextThatDoesNothing() {
        let cell = GroupRowCellView()
        cell.configure(title: "Today")

        XCTAssertNotEqual(cell.label.accessibilityRole(), .button)
        XCTAssertEqual(cell.label.accessibilityIdentifier(), AccessibilityID.sidebarGroup)
        XCTAssertFalse(cell.label.accessibilityPerformPress())
    }
}
