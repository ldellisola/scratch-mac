import AppKit
import ScratchCore

/// The note list in the window's glass sidebar: one row per note, showing its title and a preview line (spec §6.2).
/// It knows nothing about storage. The session coordinator hands it the rows to show and hears which one was chosen.
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    /// Called with the note's id when the user picks a row. Not called when `reload` changes the selection itself.
    var onSelect: ((NoteID) -> Void)?

    private static let cellIdentifier = NSUserInterfaceItemIdentifier("note")

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var summaries: [NoteSummary] = []
    /// True while `reload` runs, so that the selection it sets is not reported as a choice by the user.
    private var isReloading = false

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
        isReloading = true
        defer { isReloading = false }

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

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading else { return }
        let row = tableView.selectedRow
        guard summaries.indices.contains(row) else { return }
        onSelect?(summaries[row].id)
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
