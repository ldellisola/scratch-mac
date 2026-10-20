import AppKit
import ScratchCore

/// The note list in the window's glass sidebar (spec §6.2): a search field, and under it the notes in groups (Pinned,
/// Today, Yesterday, Earlier and Recently Deleted), each row with its title, the edit time and a preview line. It knows
/// nothing about storage. `NoteListModel` hands it the sections to show, and it reports what the owner did: opened a
/// row, typed in the search field, or pinned a note.
///
/// A note is opened by a click on its row, or by Return on the highlighted row, and not by the highlight moving: the
/// arrow keys only move the highlight, and skip the group headers. A click with ⌘ held asks for a new tab (spec §6.2).
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    /// Called with the note's id and whether it should open in a new tab, when the user opens a row: a click (in a new
    /// tab with ⌘ held), or Return. Not called when `reload` changes the highlight itself.
    var onOpen: ((NoteID, Bool) -> Void)?

    /// Called with the whole text of the search field each time it changes, also when it is cleared.
    var onSearch: ((String) -> Void)?

    /// Called when the owner chooses Pin or Unpin in a row's context menu.
    var onTogglePin: ((NoteID) -> Void)?

    /// One line of the table: a group header, or the row of a note.
    private enum Line: Equatable {
        case header(SidebarGroup)
        case note(NoteSummary)
    }

    private static let noteCellIdentifier = NSUserInterfaceItemIdentifier("note")
    private static let groupCellIdentifier = NSUserInterfaceItemIdentifier("group")
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
            rows.append(.header(section.group))
            if section.group != .recentlyDeleted || recentlyDeletedExpanded {
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
        if case .header = rows[row] { return true }
        return false
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
        case .note(let summary):
            let cell =
                tableView.makeView(withIdentifier: Self.noteCellIdentifier, owner: nil) as? NoteRowCellView
                ?? NoteRowCellView()
            cell.identifier = Self.noteCellIdentifier
            cell.configure(with: summary, now: shownNow)
            return cell
        }
    }

    // MARK: Opening notes

    /// A click on a row. With ⌘ held the note opens in a new tab (or focuses its tab, when it has one). A click on a
    /// header does nothing.
    @objc private func rowClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard rows.indices.contains(row), case .note(let summary) = rows[row] else { return }
        let inNewTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        onOpen?(summary.id, inNewTab)
    }

    /// Return on the highlighted row opens it in the current tab.
    private func openHighlightedRow() {
        let row = tableView.selectedRow
        guard rows.indices.contains(row), case .note(let summary) = rows[row] else { return }
        onOpen?(summary.id, false)
    }

    // MARK: Context menu

    /// The menu of a right click on a row: Pin, or Unpin when the note is pinned. A header has none.
    private func menu(forRow row: Int) -> NSMenu? {
        guard rows.indices.contains(row), case .note(let summary) = rows[row], summary.deletedAt == nil else {
            return nil
        }
        let menu = NSMenu()
        let item = NSMenuItem(
            title: summary.pinnedAt == nil ? "Pin" : "Unpin", action: #selector(togglePinFromMenu(_:)),
            keyEquivalent: "")
        item.target = self
        item.representedObject = summary.id
        menu.addItem(item)
        return menu
    }

    @objc private func togglePinFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NoteID else { return }
        onTogglePin?(id)
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
