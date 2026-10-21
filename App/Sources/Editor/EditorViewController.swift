import AppKit
import ScratchCore

/// Shows one note in the editor: the title field above, the plain-text editor below. It reports what the user types
/// and knows nothing about storage: the session coordinator decides which note to show and when to save it.
///
/// The view is a container with the title field on top, which does not scroll with the text (spec §6.4), and the
/// scroll view with the text under it.
final class EditorViewController: NSViewController, NSTextViewDelegate, NSTextFieldDelegate {
    /// Called with the whole text after each edit by the user. Not called when `show` loads a note.
    var onTextChange: ((String) -> Void)?

    /// Called with the whole title after each edit of the title field by the user. Not called when `show` loads a
    /// note.
    var onTitleChange: ((String) -> Void)?

    /// Called when the cursor or the scroll position changed, by the user or because of typing. Not called when `show`
    /// loads a note. The new values are in `currentSelection`, `currentScrollY` and `currentScrollAnchor`. The session
    /// coordinator saves them with the session (spec §6.6: cursor and scroll position are persisted like text).
    var onViewStateChange: (() -> Void)?

    private let scrollView: NSScrollView
    /// The text view of the note, internal for the tests.
    let textView: NoteTextView
    /// The title field above the text, internal for the tests.
    let titleField = TitleField(frame: .zero)

    /// The font size of the text and of the title: the size of every note (`setFontSize(_:)`).
    private(set) var fontSize: Double = FontSize.standard
    /// True while the note shown is read-only, because it is in Recently Deleted (`show`).
    private(set) var isReadOnly = false

    private var isLoadingNote = false
    /// True while the editor scrolls itself, so that the scroll does not count as one by the user.
    private var isApplyingScroll = false
    /// The scroll offset last reported through `onViewStateChange` or set by `show`, so that a resize of the window,
    /// which also changes the clip view's bounds, does not count as scrolling.
    private var lastScrollY: Double = 0
    /// The anchor of the shown note that the editor still has to scroll to, or may have to scroll to again. It waits
    /// for a layout, because text can only be positioned at a width (`isLaidOut`), and it is applied again whenever the
    /// text view's width changes in the `anchorSettleTime` after it was last applied: the window and the scroll view
    /// settle at launch (a first size, the window's, a scroller style), and each change of the width lays the text out
    /// again, with the height of what is above the anchor only estimated until it is laid out. The user's own scrolling,
    /// typing or moving the cursor ends the wait.
    private var scrollAnchorToApply: Int?
    /// True once `scrollAnchorToApply` has been applied at least once, which is when the editor may take a change of
    /// the scroll position for the user's.
    private var anchorWasApplied = false
    /// The width of the text view when the anchor was last applied. A different width means that the text was laid out
    /// again since, and that the line at the top may not be the anchor's any more.
    private var widthAtApply: CGFloat = 0
    /// When the wait for the settling of the layout ends, `anchorSettleTime` after the anchor was last applied.
    private var anchorDeadline = ContinuousClock.now
    private var isReapplyScheduled = false
    private static let anchorSettleTime: Duration = .seconds(5)
    private var debugStateElement: DebugStateElement?
    private var traceAnchor = 0
    private var traceTimer: Timer?
    private var traceLast = ""

    init() {
        let editor = TextViewFactory.makeEditor()
        scrollView = editor.0
        textView = editor.1
        super.init(nibName: nil, bundle: nil)
        textView.delegate = self
        textView.setAccessibilityIdentifier(AccessibilityID.editorTextView)
        textView.setAccessibilityLabel("Note")
        titleField.delegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewBoundsDidChange(_:)), name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(textViewFrameDidChange(_:)), name: NSView.frameDidChangeNotification,
            object: textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorViewController is created in code")
    }

    override func loadView() {
        let container = NSView()
        titleField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        container.addSubview(titleField)

        // The title starts where the text does: at the text view's inset, plus the 5 pt padding of a line of text,
        // less the 2 pt that a text field keeps free at its own edge.
        let titleLeading = NoteTextView.horizontalInset + 3
        NSLayoutConstraint.activate([
            // Below the toolbar, which overlaps the top of the window (the window has a full-size content view).
            titleField.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 10),
            titleField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: titleLeading),
            titleField.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -NoteTextView.horizontalInset),
            scrollView.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // The text view is at least as tall as the visible area, so that a click below a short note still lands in it.
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        AnchorTrace.log("viewDidLayout \(describeState())")
        applyPendingScrollAnchor()
    }

    // MARK: Showing a note

    /// Replaces what the editor shows with `note`: its title, its text, the cursor and the scroll position of `tab`.
    ///
    /// - `tab.selection` is a saved UTF-16 cursor offset and may be stale: it is clamped to a valid position.
    /// - `tab.scrollAnchor` is the UTF-16 offset of the first visible character, and the line that holds it is scrolled
    ///   to the top, below the content insets. It is applied at once when the editor has been laid out, and by the next
    ///   layout otherwise (as at launch, before the window has its size). A tab without an anchor (a session saved by
    ///   Scratch 0.1.0) uses `tab.scrollY` instead, a scroll offset in points (the clip view's origin y, 0 for the top).
    /// - `undoManager` is the undo history of this note. The history lives for the session and is the coordinator's:
    ///   this method keeps it, and never clears the history of the note that was shown before. Loading the note is not
    ///   an edit and is not recorded in it.
    /// - `isReadOnly` makes the text and the title uneditable.
    func show(_ note: Note, tab: TabState, undoManager: UndoManager, isReadOnly: Bool) {
        isLoadingNote = true
        defer { isLoadingNote = false }

        // End the typing run of the note that is left, so that it does not take in the next typing.
        textView.breakUndoCoalescing()
        textView.noteUndoManager = undoManager

        undoManager.disableUndoRegistration()
        textView.load(note.body)
        undoManager.enableUndoRegistration()
        // Style the text before anything lays it out or scrolls to it: around the line that will be on top first, so
        // that the first frame is right, and the rest of a long note in the turns after it. The saved anchor says
        // where the note will be; a tab without one shows its top.
        let anchor = tab.scrollAnchor.map { TextOffset.clamp($0, in: note.body) } ?? 0
        textView.styler.noteDidLoad(visibleRange: NSRange(location: anchor, length: 0))

        titleField.stringValue = note.title
        setReadOnly(isReadOnly)

        let offset = TextOffset.clamp(tab.selection, in: note.body)
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        // The delegate ignores the selection change above (the note is loading), so the markers at the cursor are
        // shown here.
        textView.styler.selectionDidChange(textView.selectedRange())
        showScrollPosition(of: tab, in: note)
    }

    /// Makes the text and the title uneditable (`true`, the note is in Recently Deleted) or editable again (`false`, the
    /// note was restored: the editor keeps showing it, with its cursor, scroll position and undo history). `show` does
    /// this for the note it shows.
    func setReadOnly(_ readOnly: Bool) {
        isReadOnly = readOnly
        textView.isEditable = !readOnly
        titleField.isEditable = !readOnly
    }

    /// Makes the text view the first responder, so typing goes into the note.
    func focusBody() {
        view.window?.makeFirstResponder(textView)
    }

    /// The same as `focusBody()`, which is where a new note and a launch put the cursor.
    func focus() {
        focusBody()
    }

    /// Makes the title field the first responder, so typing goes into the title.
    func focusTitle() {
        view.window?.makeFirstResponder(titleField)
    }

    /// The scroll view's clip view, whose bounds change when the editor scrolls (`FrameMonitor` watches it).
    var clipView: NSClipView { scrollView.contentView }

    /// The editor's whole text.
    var currentText: String { textView.string }

    /// The cursor position as a UTF-16 offset.
    var currentSelection: Int { textView.selectedRange().location }

    /// The scroll offset in points: the clip view's origin y. Plan 1 saved it. A restore prefers
    /// `currentScrollAnchor`, which keeps its meaning when the window or the font size changes.
    var currentScrollY: Double { Double(scrollView.contentView.bounds.origin.y) }

    /// The UTF-16 offset of the first character of the line at the top of the visible text. Until the editor has been
    /// laid out, which is when a note shown at launch cannot be positioned yet, it is the anchor that `show` was given.
    var currentScrollAnchor: Int {
        guard isLaidOut else { return scrollAnchorToApply ?? 0 }
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer,
            let length = textView.textStorage?.length, length > 0
        else { return 0 }
        // One point below the top edge, so that a line that starts exactly at the edge counts as the top line however
        // the numbers round.
        let top = scrollView.contentView.bounds.origin.y + scrollView.contentInsets.top
        let point = NSPoint(x: 0, y: top - textView.textContainerOrigin.y + 1)
        let glyph = layoutManager.glyphIndex(for: point, in: container)
        var line = NSRange(location: 0, length: 0)
        _ = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &line)
        guard line.location != NSNotFound else { return 0 }
        return layoutManager.characterIndexForGlyph(at: line.location)
    }

    // MARK: Font size

    /// Sets the font size of every character, of what is typed or pasted next and, three points larger and bold, of the
    /// title (spec §6.4). A size outside `FontSize.minimum`...`FontSize.maximum` is moved into it. The line at the top
    /// of the text stays at the top.
    func setFontSize(_ size: Double) {
        let size = FontSize.clamped(size)
        guard size != fontSize else { return }
        userDidMoveView()
        let anchor = isLaidOut ? currentScrollAnchor : nil
        fontSize = size
        textView.applyFontSize(size)
        titleField.applyFontSize(size)
        if let anchor { scrollToAnchor(anchor) }
    }

    // MARK: Undo

    /// The undo manager of the note shown, which the window hands to the Edit menu (`AppDelegate`). Nil for a note that
    /// is read-only: its history, if it has one, is not offered, because undoing would change a note that cannot be
    /// changed (`NoteTextView.undoManager` says the same to the text view).
    var activeUndoManager: UndoManager? { isReadOnly ? nil : textView.noteUndoManager }

    // MARK: Debug state

    /// Adds the invisible `debug.state` element to the editor's view, for UI tests (`DebugStateElement`). The app does
    /// this only in an isolated data directory.
    func installDebugStateElement() {
        guard debugStateElement == nil else { return }
        AnchorTrace.isOn = true
        let element = DebugStateElement(frame: .zero)
        element.state = { [weak self] in
            guard let self else { return [:] }
            return [
                "fontSize": self.fontSize, "scrollAnchor": self.currentScrollAnchor, "readOnly": self.isReadOnly,
                // How far the clip view is scrolled and the scroll view's top inset, so a test can tell that a note at
                // its top has the text view's own top inset on screen: `scrollY` is `-topInset` there.
                "scrollY": self.currentScrollY, "topInset": Double(self.scrollView.contentInsets.top),
                "trace": AnchorTrace.lines.joined(separator: "\n"),
            ]
        }
        view.addSubview(element)
        debugStateElement = element
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !isLoadingNote else { return }
        userDidMoveView()
        onTextChange?(textView.string)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isLoadingNote else { return }
        // The markers of the bold run or inline code the cursor is at are shown, and the others are hidden.
        textView.styler.selectionDidChange(textView.selectedRange())
        userDidMoveView()
        onViewStateChange?()
    }

    /// The undo history of the note shown, not the window's (spec §6.6).
    func undoManager(for view: NSTextView) -> UndoManager? {
        activeUndoManager
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard !isLoadingNote else { return }
        onTitleChange?(titleField.stringValue)
    }

    /// Return and Tab in the title move the cursor to the text (spec §6.4). ⇧Tab and the rest are left to AppKit.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            focusBody()
            return true
        default:
            return false
        }
    }

    // MARK: Scrolling

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        guard !isLoadingNote, !isApplyingScroll else { return }
        let scrollY = currentScrollY
        guard scrollY != lastScrollY else { return }
        lastScrollY = scrollY
        AnchorTrace.log("bounds y=\(scrollY) stale=\(isAnchorStale) \(describeState())")
        if isAnchorStale {
            // The text was laid out again at another width under the position that the editor put the note in, and
            // AppKit moved the clip view with the new height: that is not the user scrolling, and it says nothing
            // about the line at the top. The anchor is applied again.
            scheduleAnchorReapply()
            return
        }
        userDidMoveView()
        onViewStateChange?()
    }

    @objc private func textViewFrameDidChange(_ notification: Notification) {
        if isAnchorStale { scheduleAnchorReapply() }
    }

    /// True while the editor keeps the note at its anchor: it has been applied and the text has not been laid out at
    /// another width since, or has been and that is not yet corrected (`applyPendingScrollAnchor`).
    private var isAnchorStale: Bool {
        isAnchorPending && anchorWasApplied && textView.frame.width != widthAtApply
    }

    /// True while there is an anchor that the editor applies again when the layout changes: until it has been applied
    /// for the first time, and then for `anchorSettleTime` after the last time.
    private var isAnchorPending: Bool {
        guard scrollAnchorToApply != nil else { return false }
        return !anchorWasApplied || ContinuousClock.now < anchorDeadline
    }

    /// Applies the anchor again after what is on the call stack, which is AppKit tiling the scroll view or laying out the
    /// text view and is no place to lay out and scroll. Once is enough for however many changes come before it runs.
    private func scheduleAnchorReapply() {
        guard !isReapplyScheduled else { return }
        isReapplyScheduled = true
        AnchorTrace.log("reapply scheduled \(describeState())")
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isReapplyScheduled = false
                self.applyPendingScrollAnchor()
            }
        }
    }

    /// The user scrolled, typed or moved the cursor, so the anchor that waited for a layout is out of date. Before
    /// the anchor has been applied this cannot be the user's doing: the text has not even been positioned.
    private func userDidMoveView() {
        if anchorWasApplied { scrollAnchorToApply = nil }
    }

    /// True when the text can be positioned: the editor is in a window, and the layout has given the scroll view and
    /// the text view a size. Text laid out before that would be laid out for a width of 0.
    private var isLaidOut: Bool {
        view.window != nil && scrollView.contentSize.width > 0 && scrollView.contentSize.height > 0
            && textView.frame.width > 0
    }

    /// Puts the note at the position that `tab` saved: at its anchor, or else at its scroll offset.
    private func showScrollPosition(of tab: TabState, in note: Note) {
        anchorWasApplied = false
        scrollAnchorToApply = nil
        startTrace(anchor: tab.scrollAnchor ?? 0)
        if let anchor = tab.scrollAnchor {
            scrollAnchorToApply = TextOffset.clamp(anchor, in: note.body)
            applyPendingScrollAnchor()
            return
        }

        // 0 means the top, which lies above y = 0 when the toolbar overlaps the scroll view (content insets).
        let topY = -scrollView.contentInsets.top
        let clipView = scrollView.contentView
        isApplyingScroll = true
        clipView.scroll(to: NSPoint(x: 0, y: tab.scrollY == 0 ? topY : max(tab.scrollY, topY)))
        scrollView.reflectScrolledClipView(clipView)
        isApplyingScroll = false
        lastScrollY = currentScrollY
    }

    /// Scrolls to `scrollAnchorToApply` when the editor can position text. Called by `show` and by every layout.
    private func applyPendingScrollAnchor() {
        guard scrollAnchorToApply != nil else { return }
        guard isAnchorPending else {
            scrollAnchorToApply = nil
            return
        }
        guard let anchor = scrollAnchorToApply, isLaidOut else { return }
        scrollToAnchor(anchor)
        anchorWasApplied = true
        widthAtApply = textView.frame.width
        anchorDeadline = ContinuousClock.now + Self.anchorSettleTime
    }

    /// Scrolls so that the line holding the character at `anchor` is at the top of the visible text, below the content
    /// insets. Call it only when `isLaidOut`.
    private func scrollToAnchor(_ anchor: Int) {
        guard let layoutManager = textView.layoutManager, let length = textView.textStorage?.length else { return }
        let insetTop = scrollView.contentInsets.top
        var y = -insetTop
        if length > 0, anchor > 0 {
            let location = min(anchor, length - 1)
            // TextKit lays out only what is needed to draw. The text above the anchor is laid out here, so that the
            // position of its line is the real one and not an estimate.
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: location + 1))
            let glyph = layoutManager.glyphIndexForCharacter(at: location)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            y = max(y, line.minY + textView.textContainerOrigin.y - insetTop)
        }
        let clipView = scrollView.contentView
        isApplyingScroll = true
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clipView)
        isApplyingScroll = false
        lastScrollY = currentScrollY
        AnchorTrace.log("scrollToAnchor \(anchor) y=\(y) \(describeState())")
    }

    // MARK: TEMPORARY trace

    private func describeState() -> String {
        guard let layoutManager = textView.layoutManager, let length = textView.textStorage?.length, length > 0 else {
            return "empty"
        }
        let location = min(traceAnchor, length - 1)
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
        let top = scrollView.contentView.bounds.origin.y + scrollView.contentInsets.top
        let drift = rect.minY + textView.textContainerOrigin.y - top
        let visible = view.window?.isVisible == true ? "vis" : "hidden"
        return String(
            format: "drift=%.1f anchorLineY=%.1f clipY=%.1f frame=%.0fx%.0f %@", drift, rect.minY,
            scrollView.contentView.bounds.origin.y, textView.frame.width, textView.frame.height, visible)
    }

    private func startTrace(anchor: Int) {
        guard AnchorTrace.isOn else { return }
        traceAnchor = anchor
        traceTimer?.invalidate()
        AnchorTrace.log("show anchor=\(anchor)")
        var ticks = 0
        traceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                ticks += 1
                let state = self.describeState()
                if state != self.traceLast {
                    self.traceLast = state
                    AnchorTrace.log("poll \(state)")
                }
                if ticks > 160 { self.traceTimer?.invalidate() }
            }
        }
    }
}
