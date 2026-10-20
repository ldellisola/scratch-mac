import AppKit
import ScratchCore

/// The note list in the window's glass sidebar: one row per note, showing its title and a preview line (spec §6.2).
/// It knows nothing about storage. The session coordinator hands it the rows to show and hears which one was chosen.
///
/// A note is opened by a click on its row, or by Return on the highlighted row, and not by the highlight moving: the
/// arrow keys only move the highlight. A click with ⌘ held asks for a new tab (spec §6.2).
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    /// Called with the note's id and whether it should open in a new tab, when the user opens a row: a click (in a new
    /// tab with ⌘ held), or Return. Not called when `reload` changes the highlight itself.
    var onOpen: ((NoteID, Bool) -> Void)?

    private static let cellIdentifier = NSUserInterfaceItemIdentifier("note")

    private let scrollView = NSScrollView()
    private let tableView = SidebarList()
    private var summaries: [NoteSummary] = []

    init() {
        super.init(nibName: nil, bundle: nil)

        let column = NSTableColumn(identifier: Self.cellIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 44
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        // A click sends the action, also on the row that is highlighted already: that is how a note is opened.
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))
        tableView.onReturn = { [weak self] in self?.openHighlightedRow() }
        tableView.setAccessibilityIdentifier(AccessibilityID.sidebarTable)
        tableView.setAccessibilityLabel("Notes")

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SidebarViewController is created in code")
    }

    override func loadView() {
        view = scrollView
    }

    // MARK: Showing notes

    /// Shows `summaries`, in this order, and highlights the row of `selecting`, or no row when it is nil or not in the
    /// list. Does nothing visible when the list and the selection are already what is shown.
    func reload(_ summaries: [NoteSummary], selecting: NoteID?) {
        if summaries != self.summaries {
            self.summaries = summaries
            tableView.reloadData()
        }
        if let id = selecting, let row = summaries.firstIndex(where: { $0.id == id }) {
            if tableView.selectedRow != row {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        } else if tableView.selectedRow != -1 {
            tableView.deselectAll(nil)
        }
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        summaries.count
    }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell =
            tableView.makeView(withIdentifier: Self.cellIdentifier, owner: nil) as? NoteRowCellView
            ?? NoteRowCellView()
        cell.identifier = Self.cellIdentifier
        cell.configure(with: summaries[row])
        return cell
    }

    // MARK: Opening notes

    /// A click on a row. With ⌘ held the note opens in a new tab (or focuses its tab, when it has one).
    @objc private func rowClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard summaries.indices.contains(row) else { return }
        let inNewTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        onOpen?(summaries[row].id, inNewTab)
    }

    /// Return on the highlighted row opens it in the current tab.
    private func openHighlightedRow() {
        let row = tableView.selectedRow
        guard summaries.indices.contains(row) else { return }
        onOpen?(summaries[row].id, false)
    }
}

/// The sidebar's table. It adds one key: Return (and the keypad's Enter) calls `onReturn` instead of beeping, so that
/// the arrow keys and Return open a note without the mouse. Every other key is the table's own.
private final class SidebarList: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 36 is Return and 76 the keypad's Enter (kVK_Return, kVK_ANSI_KeypadEnter).
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if (event.keyCode == 36 || event.keyCode == 76) && modifiers.isEmpty {
            onReturn?()
            return
        }
        super.keyDown(with: event)
    }
}

/// One sidebar row: the title, and below it the preview line when there is one.
///
/// A note with a title shows it in bold. A note without one shows its first line in the note font, as the spec asks
/// (§6.2). A note with no text at all, which the sidebar only shows when the owner emptied it, shows a dimmed
/// "Untitled", because an empty row could not be seen or clicked.
private final class NoteRowCellView: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let previewField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleField.setAccessibilityIdentifier(AccessibilityID.sidebarRowTitle)
        previewField.setAccessibilityIdentifier(AccessibilityID.sidebarRowPreview)
        previewField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        previewField.textColor = .secondaryLabelColor
        for field in [titleField, previewField] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            // Long lines are cut off with an ellipsis instead of widening the sidebar.
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let stack = NSStackView(views: [titleField, previewField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteRowCellView is created in code")
    }

    func configure(with summary: NoteSummary) {
        if summary.displayTitle.isEmpty {
            titleField.stringValue = "Untitled"
            titleField.font = NoteTextView.noteFont
            titleField.textColor = .secondaryLabelColor
        } else {
            titleField.stringValue = summary.displayTitle
            titleField.font = summary.hasTitle ? NSFont.boldSystemFont(ofSize: 13) : NoteTextView.noteFont
            titleField.textColor = .labelColor
        }
        previewField.stringValue = summary.preview
        previewField.isHidden = summary.preview.isEmpty
    }
}
