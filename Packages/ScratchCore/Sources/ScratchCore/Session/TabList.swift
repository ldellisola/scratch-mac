/// What ``TabList/open(_:inNewTab:)`` did.
public enum TabOpening: Equatable, Sendable {
    /// The note was already open, and its tab is now active.
    case focused(index: Int)
    /// The active tab now shows the note, and `previous` is the note it showed. The caller may have to discard
    /// `previous` if it is an empty note nobody used (spec §6.3).
    case replaced(index: Int, previous: NoteID)
    /// A new tab showing the note was added after the active tab and is now active.
    case inserted(index: Int)
}

/// What ``TabList/close(at:)`` did.
public enum TabClosing: Equatable, Sendable {
    /// The tab was removed. The caller may have to discard `noteID` if it is an empty note nobody used (spec §6.3).
    case closed(noteID: NoteID)
    /// The tab is the only one, so nothing changed. The caller replaces its note with a new empty one
    /// (``TabList/replaceNote(at:with:)``) and may have to discard `noteID` in the same way.
    case lastTab(noteID: NoteID)
}

/// The open tabs and which one is active: the rules of spec §6.3, with no AppKit in them.
///
/// - There is always at least one tab.
/// - A note is open in at most one tab. ``open(_:inNewTab:)`` keeps it so. A caller that passes a note to
///   ``replaceNote(at:with:)`` or builds a list with ``init(tabs:activeIndex:)`` makes sure the notes are different.
/// - A tab is a view onto a note, so closing one never says anything about deleting the note.
///
/// Methods that take a tab index trap when it is not in `tabs.indices`, like `Array` does, except ``select(_:)``,
/// which ignores such an index.
public struct TabList: Equatable, Sendable {
    /// The open tabs, left to right. Never empty.
    public private(set) var tabs: [TabState]
    /// The position of the active tab in ``tabs``. Always a valid index.
    public private(set) var activeIndex: Int

    /// Traps when `tabs` is empty. An `activeIndex` outside `tabs` is moved to the nearest tab.
    public init(tabs: [TabState], activeIndex: Int) {
        precondition(!tabs.isEmpty, "A TabList always has at least one tab")
        self.tabs = tabs
        self.activeIndex = min(max(activeIndex, 0), tabs.count - 1)
    }

    /// The active tab.
    public var active: TabState { tabs[activeIndex] }

    /// The position of the tab that shows `id`, if there is one.
    public func index(of id: NoteID) -> Int? {
        tabs.firstIndex { $0.noteID == id }
    }

    // MARK: Selecting

    /// Makes the tab at `index` active. An `index` that is not a tab changes nothing.
    public mutating func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
    }

    /// Makes the tab to the right active, or the first tab after the last (⌃Tab).
    public mutating func selectNext() {
        activeIndex = (activeIndex + 1) % tabs.count
    }

    /// Makes the tab to the left active, or the last tab before the first (⌃⇧Tab).
    public mutating func selectPrevious() {
        activeIndex = (activeIndex + tabs.count - 1) % tabs.count
    }

    /// ⌘1 to ⌘8 select that tab, counting from 1, and ⌘9 selects the last tab, however many there are. Another
    /// number, or one past the last tab, changes nothing.
    public mutating func select(number: Int) {
        switch number {
        case 1...8: select(number - 1)
        case 9: activeIndex = tabs.count - 1
        default: break
        }
    }

    // MARK: Opening and closing

    /// Shows the note `id` and says how.
    ///
    /// - A note that is already open is focused, whatever `inNewTab` says.
    /// - Otherwise, with `inNewTab`, a tab for it is inserted right after the active one and becomes active.
    /// - Otherwise it replaces the note in the active tab.
    ///
    /// A note that gets its own tab, or replaces another, starts with the cursor and the scroll position at the top.
    public mutating func open(_ id: NoteID, inNewTab: Bool) -> TabOpening {
        if let existing = index(of: id) {
            activeIndex = existing
            return .focused(index: existing)
        }
        if inNewTab {
            let position = activeIndex + 1
            tabs.insert(Self.freshTab(for: id), at: position)
            activeIndex = position
            return .inserted(index: position)
        }
        let previous = tabs[activeIndex].noteID
        replaceNote(at: activeIndex, with: id)
        return .replaced(index: activeIndex, previous: previous)
    }

    /// Removes the tab at `index`, unless it is the only one.
    ///
    /// When the closed tab was the active one, the tab that moves into its place becomes active, or the new last tab
    /// when it was the last. When it was left of the active tab, the active tab stays the same note.
    public mutating func close(at index: Int) -> TabClosing {
        precondition(tabs.indices.contains(index), "No tab at index \(index)")
        guard tabs.count > 1 else { return .lastTab(noteID: tabs[index].noteID) }
        let removed = tabs.remove(at: index)
        if index < activeIndex {
            activeIndex -= 1
        } else if index == activeIndex {
            activeIndex = min(index, tabs.count - 1)
        }
        return .closed(noteID: removed.noteID)
    }

    /// Makes the tab at `index` show the note `id`, at the top with the cursor at the start. The active tab stays
    /// the same. `id` must not be open in another tab: use ``open(_:inNewTab:)`` for a note that may be.
    public mutating func replaceNote(at index: Int, with id: NoteID) {
        precondition(tabs.indices.contains(index), "No tab at index \(index)")
        tabs[index] = Self.freshTab(for: id)
    }

    // MARK: View state and persistence

    /// Records where the cursor is and how far the tab is scrolled, as the UTF-16 offset of the first visible
    /// character. The anchor takes the place of the tab's `scrollY` when the session is restored.
    public mutating func updateViewState(at index: Int, selection: Int, scrollAnchor: Int) {
        precondition(tabs.indices.contains(index), "No tab at index \(index)")
        tabs[index].selection = selection
        tabs[index].scrollAnchor = scrollAnchor
    }

    /// What a relaunch restores: these tabs, the active one and the font size.
    public func session(fontSize: Double) -> SessionState {
        SessionState(tabs: tabs, activeTabIndex: activeIndex, fontSize: fontSize)
    }

    private static func freshTab(for id: NoteID) -> TabState {
        TabState(noteID: id, selection: 0, scrollY: 0, scrollAnchor: nil)
    }
}
