import AppKit
import ScratchCore

/// One sidebar row of a note, in two lines (mockup B): the title with the edit time on its right, and below it the
/// preview line when there is one. A pinned note has a small orange pin before its title.
///
/// A note with a title shows it in bold. A note without one shows its first line in the note font, as the spec asks
/// (§6.2). A note with no text at all, which the sidebar only shows when the owner emptied it, shows a dimmed
/// "Untitled", because an empty row could not be seen or clicked.
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
        previewField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
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

        pinView.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
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
            titleField.textColor = .labelColor
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
        pinView.isHidden = !isPinned
        pinWidth.constant = isPinned ? Self.pinSize : 0
        titleLeading.constant = isPinned ? 4 : 0
    }
}

/// The header of a group of rows: "Pinned", "Today", "Yesterday", "Earlier" or "Recently Deleted", in small bold grey
/// letters (mockup B). It is a full-width group row of the table, not a note.
final class GroupRowCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setAccessibilityIdentifier(AccessibilityID.sidebarGroup)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GroupRowCellView is created in code")
    }

    /// Shows `title`.
    func configure(title: String) {
        label.stringValue = title
    }
}
