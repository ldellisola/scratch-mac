import AppKit
import ScratchCore

/// One sidebar row of a note, in two lines (mockup B): the title with the edit time on its right, and below it the
/// preview line when there is one. A pinned note has a small orange pin before its title.
///
/// A note with a title shows it in bold. A note without one shows its first line in the note font, as the spec asks
/// (§6.2). A note with no text at all, which the sidebar only shows when the owner emptied it, shows a dimmed
/// "Untitled", because an empty row could not be seen or clicked. A note in Recently Deleted has its title in grey.
final class NoteRowCellView: NSTableCellView {
    private let pinView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let timeField = NSTextField(labelWithString: "")
    private let previewField = NSTextField(labelWithString: "")

    /// The pin is 0 points wide, and the title starts at the row's edge, while the note is not pinned. Made in `init`
    /// once `self` exists: a constraint to the row's own anchors needs it.
    private var pinWidth: NSLayoutConstraint!
    private var titleLeading: NSLayoutConstraint!
    /// A title with a preview under it is at the top of the row, and a title alone is centred. Exactly one of the two
    /// constraints is active.
    private var titleTop: NSLayoutConstraint!
    private var titleCenter: NSLayoutConstraint!

    private static let pinSize: CGFloat = 10
    private static let sideMargin: CGFloat = 8
    /// The pin before a pinned note's title. One image for every row: looking a symbol up costs more than a row.
    private static let pinImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pinWidth = pinView.widthAnchor.constraint(equalToConstant: 0)
        titleLeading = titleField.leadingAnchor.constraint(equalTo: pinView.trailingAnchor)
        titleTop = titleField.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        titleCenter = titleField.centerYAnchor.constraint(equalTo: centerYAnchor)

        titleField.setAccessibilityIdentifier(AccessibilityID.sidebarRowTitle)
        timeField.setAccessibilityIdentifier(AccessibilityID.sidebarRowTime)
        previewField.setAccessibilityIdentifier(AccessibilityID.sidebarRowPreview)
        timeField.font = NSFont.systemFont(ofSize: 11)
        timeField.textColor = .secondaryLabelColor
        // The preview is in the system font, like the time (mockup B). Only a title that is a first line is in the
        // note font.
        previewField.font = NSFont.systemFont(ofSize: 12)
        previewField.textColor = .secondaryLabelColor
        for field in [titleField, previewField] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            // Long lines are cut off with an ellipsis instead of widening the sidebar.
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        // The time is never cut off: the title gives way to it.
        timeField.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeField.setContentHuggingPriority(.required, for: .horizontal)

        pinView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        pinView.contentTintColor = .systemOrange
        pinView.imageScaling = .scaleProportionallyDown
        // The group header already says "Pinned", and the title's value is only the title.
        pinView.setAccessibilityElement(false)

        for subview in [pinView, titleField, timeField, previewField] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            pinView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.sideMargin),
            pinView.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
            pinView.heightAnchor.constraint(equalToConstant: Self.pinSize),
            pinWidth,
            titleLeading,
            titleTop,
            timeField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.sideMargin),
            timeField.firstBaselineAnchor.constraint(equalTo: titleField.firstBaselineAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: timeField.leadingAnchor, constant: -6),
            previewField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.sideMargin),
            previewField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.sideMargin),
            previewField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteRowCellView is created in code")
    }

    /// Shows `summary`. `now` decides how the edit time reads (the time of day for today and yesterday, otherwise the
    /// date, `NoteTimeLabel`).
    func configure(with summary: NoteSummary, now: Date) {
        if summary.displayTitle.isEmpty {
            titleField.stringValue = "Untitled"
            titleField.font = NoteTextView.noteFont
            titleField.textColor = .secondaryLabelColor
        } else {
            titleField.stringValue = summary.displayTitle
            titleField.font = summary.hasTitle ? NSFont.boldSystemFont(ofSize: 13) : NoteTextView.noteFont
            // A note in Recently Deleted is greyed out: it can be read, and not changed.
            titleField.textColor = summary.deletedAt == nil ? .labelColor : .secondaryLabelColor
        }
        timeField.stringValue = NoteTimeLabel.text(
            for: summary.modifiedAt, now: now, calendar: .current, locale: .current)
        previewField.stringValue = summary.preview
        let hasPreview = !summary.preview.isEmpty
        previewField.isHidden = !hasPreview
        // Switch off the constraint that is not wanted before the other is switched on: both at once would conflict.
        if hasPreview {
            titleCenter.isActive = false
            titleTop.isActive = true
        } else {
            titleTop.isActive = false
            titleCenter.isActive = true
        }

        let isPinned = summary.pinnedAt != nil && summary.deletedAt == nil
        if isPinned && pinView.image == nil { pinView.image = Self.pinImage }
        pinView.isHidden = !isPinned
        pinWidth.constant = isPinned ? Self.pinSize : 0
        titleLeading.constant = isPinned ? 4 : 0
    }
}

/// The header of a group of rows: "Pinned", "Today", "Yesterday", "Earlier" or "Recently Deleted (N)", in small bold grey
/// letters (mockup B). It is a full-width group row of the table, not a note.
///
/// The header of Recently Deleted is the one that does something: a click shows or hides the deleted notes under it
/// (`SidebarViewController`). It has a small arrow before its title, pointing right while the notes are hidden and down
/// while they are shown, and its title has the accessibility identifier `recentlyDeletedHeader`. The other headers'
/// titles have `sidebarGroup`.
final class GroupRowCellView: NSTableCellView {
    private let chevronView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    /// The arrow is 0 points wide, and the title starts at the row's edge, in every header but Recently Deleted's.
    private var chevronWidth: NSLayoutConstraint!
    private var labelLeading: NSLayoutConstraint!

    private static let chevronSize: CGFloat = 10
    /// A header's title starts where a note's title does (mockup B): a group row sits 8 points further left in the
    /// table than the row of a note, whose cell has a side margin of 8.
    private static let sideMargin: CGFloat = 16

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setAccessibilityIdentifier(AccessibilityID.sidebarGroup)

        chevronView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        chevronView.contentTintColor = .secondaryLabelColor
        chevronView.imageScaling = .scaleProportionallyDown
        // The title says what the header is, and the arrow only repeats whether it is open.
        chevronView.setAccessibilityElement(false)

        for subview in [chevronView, label] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        chevronWidth = chevronView.widthAnchor.constraint(equalToConstant: 0)
        labelLeading = label.leadingAnchor.constraint(equalTo: chevronView.trailingAnchor)
        NSLayoutConstraint.activate([
            chevronView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.sideMargin),
            chevronView.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            chevronView.heightAnchor.constraint(equalToConstant: Self.chevronSize),
            chevronWidth,
            labelLeading,
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GroupRowCellView is created in code")
    }

    /// Shows the header of an ordinary group, with `title`.
    func configure(title: String) {
        label.stringValue = title
        label.setAccessibilityIdentifier(AccessibilityID.sidebarGroup)
        chevronView.image = nil
        chevronView.isHidden = true
        chevronWidth.constant = 0
        labelLeading.constant = 0
    }

    /// Shows the header of Recently Deleted: "Recently Deleted (`count`)", with an arrow that says whether its notes are
    /// `expanded` (shown under the header).
    func configureRecentlyDeleted(count: Int, expanded: Bool) {
        label.stringValue = "Recently Deleted (\(count))"
        label.setAccessibilityIdentifier(AccessibilityID.recentlyDeletedHeader)
        chevronView.image = NSImage(
            systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        chevronView.isHidden = false
        chevronWidth.constant = Self.chevronSize
        labelLeading.constant = 4
    }
}
