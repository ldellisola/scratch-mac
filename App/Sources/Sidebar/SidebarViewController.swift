import AppKit
import ScratchCore

/// The note list in the window's glass sidebar (spec §6.2): a search field, and under it the notes in groups (Pinned,
/// Today, Yesterday, Earlier and Recently Deleted), each row with its title, the edit time and a preview line. It knows
/// nothing about storage. `NoteListModel` hands it the sections to show, and it reports what the owner did: opened a
/// row, typed in the search field, pinned, deleted or restored a note, or clicked the header of Recently Deleted.
///
/// A note is opened by a click on its row, or by Return on the highlighted row, and not by the highlight moving: the
/// arrow keys only move the highlight, and skip the group headers. A click with ⌘ held asks for a new tab (spec §6.2).
/// ⌘⌫ deletes the highlighted note while the table has the keyboard (spec §6.7, `SidebarTableView`). A note in Recently
/// Deleted opens like any other, and the editor shows it read-only.
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    /// Called with the note's id and whether it should open in a new tab, when the user opens a row: a click (in a new
    /// tab with ⌘ held), or Return. Not called when `reload` changes the highlight itself.
    var onOpen: ((NoteID, Bool) -> Void)?

    /// Called with the whole text of the search field each time it changes, also when it is cleared.
    var onSearch: ((String) -> Void)?

    /// Called when the owner chooses Pin or Unpin in a row's context menu.
    var onTogglePin: ((NoteID) -> Void)?

    /// Called when the owner deletes a note that is not deleted yet: Delete in its row's context menu, or ⌘⌫ with the
    /// note highlighted.
    var onDelete: ((NoteID) -> Void)?

    /// Called when the owner chooses Restore in the context menu of a row in Recently Deleted.
    var onRestore: ((NoteID) -> Void)?

    /// Called when the owner has answered "Delete" to the question that Delete Permanently… in the context menu of a row
    /// in Recently Deleted asks.
    var onDeletePermanently: ((NoteID) -> Void)?

    /// Called when the owner clicks the header of Recently Deleted, which shows or hides the notes under it. The sidebar
    /// does not keep that state: it shows what the next `reload` says (`recentlyDeletedExpanded`).
    var onToggleRecentlyDeleted: (() -> Void)?

    /// One line of the table: a group header, the header of Recently Deleted (which is clicked, and counts its notes),
    /// or the row of a note.
    private enum Line: Equatable {
        case header(SidebarGroup)
        case recentlyDeletedHeader(count: Int, expanded: Bool)
        case note(NoteSummary)
    }

    private static let noteCellIdentifier = NSUserInterfaceItemIdentifier("note")
    private static let groupCellIdentifier = NSUserInterfaceItemIdentifier("group")
    /// The cell of the header of Recently Deleted, which is a button for VoiceOver: kept apart from the other headers' cells,
    /// so that none of them is ever made a button by being reused.
    private static let recentlyDeletedCellIdentifier = NSUserInterfaceItemIdentifier("recentlyDeleted")
    private static let noteRowHeight: CGFloat = 44
    private static let groupRowHeight: CGFloat = 28
    /// The space between the search field and the sides of the sidebar, and above it (below the toolbar).
    private static let sideMargin: CGFloat = 12
    private static let searchTopMargin: CGFloat = 8

    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = SidebarTableView()

    /// The table's lines, in order, and what they were made for.
    private var rows: [Line] = []
    private var shownDay: Date?
    private var shownNow = Date()
    /// The search text that `onSearch` was last called with.
    private var lastSearchText = ""

    init() {
        super.init(nibName: nil, bundle: nil)

        let column = NSTableColumn(identifier: Self.noteCellIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = Self.noteRowHeight
        // A header stays where it is, and scrolls away with its rows.
        tableView.floatsGroupRows = false
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        // A click sends the action, also on the row that is highlighted already: that is how a note is opened.
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))
        tableView.onReturn = { [weak self] in self?.openHighlightedRow() }
        tableView.onCommandDelete = { [weak self] in self?.deleteHighlightedRow() ?? false }
        tableView.takesClick = { [weak self] row in self?.takeClick(onRow: row) ?? false }
        tableView.menuForRow = { [weak self] row in self?.menu(forRow: row) }
        tableView.setAccessibilityIdentifier(AccessibilityID.sidebarTable)
        tableView.setAccessibilityLabel("Notes")

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        // The list starts below the search field, which is below the toolbar: there is no toolbar to make room for.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()

        searchField.placeholderString = "Search"
        // The list follows every keystroke, and the cancel button and Escape send an empty text.
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.delegate = self
        searchField.setAccessibilityIdentifier(AccessibilityID.sidebarSearch)
        searchField.setAccessibilityLabel("Search")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SidebarViewController is created in code")
    }

    override func loadView() {
        let container = NSView()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        container.addSubview(searchField)
        NSLayoutConstraint.activate([
            // Below the toolbar, which overlaps the top of the window (the window has a full-size content view).
            searchField.topAnchor.constraint(
                equalTo: container.safeAreaLayoutGuide.topAnchor, constant: Self.searchTopMargin),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.sideMargin),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.sideMargin),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    // MARK: Showing notes

    /// Shows `sections`, a header above the rows of each, and highlights the row of `selecting`, or no row when it is
    /// nil or not in the list. Does nothing visible when the list, the selection and the day are already what is shown.
    ///
    /// The Recently Deleted section shows its rows only when `recentlyDeletedExpanded`, and its header alone
    /// otherwise. `now` decides how a row's time reads, so a new day shows new labels.
    func reload(_ sections: [SidebarSection], selecting: NoteID?, recentlyDeletedExpanded: Bool, now: Date) {
        let newRows = Self.rows(for: sections, recentlyDeletedExpanded: recentlyDeletedExpanded)
        let day = Calendar.current.startOfDay(for: now)
        if newRows != rows || day != shownDay {
            rows = newRows
            shownDay = day
            shownNow = now
            tableView.reloadData()
        }
        if let id = selecting, let row = index(of: id) {
            if tableView.selectedRow != row {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        } else if tableView.selectedRow != -1 {
            tableView.deselectAll(nil)
        }
    }

    /// The two stops of the sidebar in the key view loop (`KeyViewLoop`), in order: the search field and the note list.
    var keyViews: [NSView] { [searchField, tableView] }

    /// Makes the search field the first field of the keyboard (⌥⌘F), and shows the sidebar when it is hidden.
    func focusSearch() {
        if let split = parent as? NSSplitViewController, let item = split.splitViewItem(for: self), item.isCollapsed {
            item.isCollapsed = false
        }
        view.window?.makeFirstResponder(searchField)
    }

    private static func rows(for sections: [SidebarSection], recentlyDeletedExpanded: Bool) -> [Line] {
        var rows: [Line] = []
        for section in sections {
            if section.group == .recentlyDeleted {
                rows.append(.recentlyDeletedHeader(count: section.notes.count, expanded: recentlyDeletedExpanded))
                if recentlyDeletedExpanded { rows.append(contentsOf: section.notes.map { Line.note($0) }) }
            } else {
                rows.append(.header(section.group))
                rows.append(contentsOf: section.notes.map { Line.note($0) })
            }
        }
        return rows
    }

    private static func title(of group: SidebarGroup) -> String {
        switch group {
        case .pinned: "Pinned"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .earlier: "Earlier"
        case .recentlyDeleted: "Recently Deleted"
        }
    }

    /// The index of the row of the note `id`, if it is shown.
    private func index(of id: NoteID) -> Int? {
        rows.firstIndex { row in
            if case .note(let summary) = row { return summary.id == id }
            return false
        }
    }

    private func isHeader(_ row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        if case .note = rows[row] { return false }
        return true
    }

    /// The note that a row shows, or nil for a header and for an index that is not a row.
    private func noteSummary(atRow row: Int) -> NoteSummary? {
        guard rows.indices.contains(row), case .note(let summary) = rows[row] else { return nil }
        return summary
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        isHeader(row)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        isHeader(row) ? Self.groupRowHeight : Self.noteRowHeight
    }

    /// Gives the row view of a note its label for VoiceOver (`NoteRowCellView.accessibilityLabel(for:now:)`): the row reads as one
    /// element, "<title>, <time>, <preview>", and its texts stay its children. A row view is reused for any row, so every row
    /// sets its label, and a header has none.
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        rowView.setAccessibilityLabel(
            noteSummary(atRow: row).map { NoteRowCellView.accessibilityLabel(for: $0, now: shownNow) })
    }

    /// A header is not a note: it cannot be highlighted, and the arrow keys step over it.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        !isHeader(row)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case .header(let group):
            let cell =
                tableView.makeView(withIdentifier: Self.groupCellIdentifier, owner: nil) as? GroupRowCellView
                ?? GroupRowCellView()
            cell.identifier = Self.groupCellIdentifier
            cell.configure(title: Self.title(of: group))
            return cell
        case .recentlyDeletedHeader(let count, let expanded):
            let cell =
                tableView.makeView(withIdentifier: Self.recentlyDeletedCellIdentifier, owner: nil) as? GroupRowCellView
                ?? GroupRowCellView()
            cell.identifier = Self.recentlyDeletedCellIdentifier
            cell.configureRecentlyDeleted(count: count, expanded: expanded)
            // A press from VoiceOver does what a click on the header does.
            cell.onPress = { [weak self] in self?.toggleRecentlyDeleted() }
            return cell
        case .note(let summary):
            let cell =
                tableView.makeView(withIdentifier: Self.noteCellIdentifier, owner: nil) as? NoteRowCellView
                ?? NoteRowCellView()
            cell.identifier = Self.noteCellIdentifier
            cell.configure(with: summary, now: shownNow)
            // A press from VoiceOver opens the note, as a click does (the arrow keys only move the highlight).
            cell.onPress = { [weak self] in self?.onOpen?(summary.id, false) }
            return cell
        }
    }

    // MARK: Opening notes

    /// A click on a row. With ⌘ held the note opens in a new tab (or focuses its tab, when it has one). A click on a
    /// header does nothing.
    @objc private func rowClicked(_ sender: Any?) {
        guard let summary = noteSummary(atRow: tableView.clickedRow) else { return }
        let inNewTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        onOpen?(summary.id, inNewTab)
    }

    /// Return on the highlighted row opens it in the current tab.
    private func openHighlightedRow() {
        guard let summary = noteSummary(atRow: tableView.selectedRow) else { return }
        onOpen?(summary.id, false)
    }

    // MARK: Recently Deleted

    /// The table asks before it handles a click. The header of Recently Deleted takes it: the notes under it are shown
    /// or hidden. A click on any other header is left to the table, which ignores it.
    private func takeClick(onRow row: Int) -> Bool {
        guard rows.indices.contains(row), case .recentlyDeletedHeader = rows[row] else { return false }
        toggleRecentlyDeleted()
        return true
    }

    /// Shows or hides the notes under the header of Recently Deleted: a click on it, or a press from VoiceOver.
    private func toggleRecentlyDeleted() {
        onToggleRecentlyDeleted?()
        // The notes appear below the header, at the bottom of the list: bring them into view.
        if let last = rows.indices.last, case .note = rows[last] { tableView.scrollRowToVisible(last) }
    }

    /// ⌘⌫ on the highlighted row deletes its note, unless the note is deleted already. Returns whether it did.
    private func deleteHighlightedRow() -> Bool {
        guard let summary = noteSummary(atRow: tableView.selectedRow), summary.deletedAt == nil else { return false }
        onDelete?(summary.id)
        return true
    }

    // MARK: Context menu

    /// The menu of a right click on a row. A note has Pin, or Unpin when it is pinned, and Delete. A note in Recently
    /// Deleted has Restore and Delete Permanently…. A header has none. Delete has no shortcut here: ⌘⌫ is handled by the
    /// table (`SidebarTableView`), and a key equivalent in a menu would be offered to the text view's ⌘⌫ too.
    private func menu(forRow row: Int) -> NSMenu? {
        guard let summary = noteSummary(atRow: row) else { return nil }
        let menu = NSMenu()
        if summary.deletedAt == nil {
            menu.addItem(
                menuItem(summary.pinnedAt == nil ? "Pin" : "Unpin", #selector(togglePinFromMenu(_:)), for: summary))
            menu.addItem(.separator())
            menu.addItem(menuItem("Delete", #selector(deleteFromMenu(_:)), for: summary))
        } else {
            menu.addItem(menuItem("Restore", #selector(restoreFromMenu(_:)), for: summary))
            menu.addItem(menuItem("Delete Permanently…", #selector(deletePermanentlyFromMenu(_:)), for: summary))
        }
        return menu
    }

    /// A context menu item that sends `action` to this controller, and remembers the note it is for.
    private func menuItem(_ title: String, _ action: Selector, for summary: NoteSummary) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = summary.id
        return item
    }

    @objc private func togglePinFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NoteID else { return }
        onTogglePin?(id)
    }

    @objc private func deleteFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NoteID else { return }
        onDelete?(id)
    }

    @objc private func restoreFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NoteID else { return }
        onRestore?(id)
    }

    /// Asks, in a sheet on the window, whether the note is to be deleted for good, and only a "Delete" calls
    /// `onDeletePermanently`. Nothing can bring the note back after that.
    @objc private func deletePermanentlyFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NoteID, let window = view.window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \(title(ofNote: id).map(Self.quoted) ?? "this note") permanently?"
        alert.informativeText = "This can't be undone."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                if response == .alertFirstButtonReturn { self?.onDeletePermanently?(id) }
            }
        }
    }

    /// The title of the row of the note `id` as the list shows it, which the question quotes. Nil when the note is not
    /// in the list any more.
    private func title(ofNote id: NoteID) -> String? {
        for case .note(let summary) in rows where summary.id == id {
            return summary.displayTitle.isEmpty ? "Untitled" : summary.displayTitle
        }
        return nil
    }

    /// `title` in typographic quotes, cut off after 60 characters so that a long first line does not make a huge sheet.
    private static func quoted(_ title: String) -> String {
        let shown = title.count > 60 ? String(title.prefix(60)) + "…" : title
        return "“\(shown)”"
    }

    // MARK: Search

    /// The search field sent its action: a new text, or an empty one after the cancel button.
    @objc private func searchFieldChanged(_ sender: Any?) {
        searchTextMayHaveChanged()
    }

    func controlTextDidChange(_ notification: Notification) {
        searchTextMayHaveChanged()
    }

    /// Escape clears the search field, and the full list comes back. With nothing typed it is left to AppKit.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)), !searchField.stringValue.isEmpty else {
            return false
        }
        searchField.stringValue = ""
        searchTextMayHaveChanged()
        return true
    }

    /// Reports the search text when it is not the one that was reported last. The action and the text change
    /// notification both come for a keystroke, and the list is read once.
    private func searchTextMayHaveChanged() {
        let text = searchField.stringValue
        guard text != lastSearchText else { return }
        lastSearchText = text
        onSearch?(text)
    }
}
