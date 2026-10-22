/// Accessibility identifiers that UI tests use to find elements. This file is compiled into the app and into every UI
/// test target, so both sides spell each identifier the same way. Keep it free of imports.
enum AccessibilityID {
    /// The editor's text view. Its accessibility value is the note's text.
    static let editorTextView = "editor.textView"
    /// The sidebar's note list (plan 1, task 8).
    static let sidebarTable = "sidebar.table"
    /// The toolbar's "new note" button (plan 1, task 8).
    static let newNoteButton = "toolbar.newNote"
    /// The title text of a sidebar row. Its value is the row's title.
    static let sidebarRowTitle = "sidebar.row.title"
    /// The preview text of a sidebar row. Its value is the row's preview line.
    static let sidebarRowPreview = "sidebar.row.preview"
    /// The edit time on the right of a sidebar row (plan 2, task 8). Its value is the label, such as "10:42" or "Oct 14".
    static let sidebarRowTime = "sidebar.row.time"
    /// The title of a group of sidebar rows (plan 2, task 8): "Pinned", "Today", "Yesterday" or "Earlier". Its value is
    /// the title. A group title is not a row, so it does not have `sidebarRowTitle`. The header of Recently Deleted has
    /// `recentlyDeletedHeader` instead.
    static let sidebarGroup = "sidebar.group"
    /// The header of Recently Deleted at the bottom of the sidebar (plan 2, task 9). Its value reads "Recently Deleted
    /// (N)" with the number of deleted notes, and a click on it shows or hides them. It is a group header like the
    /// others, but it has this identifier and not `sidebarGroup`, because it is the only one that does something.
    static let recentlyDeletedHeader = "sidebar.recentlyDeleted"
    /// The search field above the sidebar's note list (plan 2, task 8). Its value is the text typed in it.
    static let sidebarSearch = "sidebar.search"
    /// The toolbar's pin button (plan 2, task 8). Like the new note button it is a view-less toolbar item, so this is
    /// its item identifier, and UI tests also find it by its label, "Pin" or "Unpin".
    static let pinButton = "toolbar.pin"
    /// The toolbar's paperclip, which attaches files to the note (plan 5, task 5). Like the pin button it is a view-less
    /// toolbar item, so this is its item identifier, and UI tests also find it by its label, "Attach File".
    static let attachButton = "toolbar.attach"
    /// The title field above the editor's text (plan 2, task 6). Its value is the note's title.
    static let titleField = "editor.titleField"
    /// A 1 x 1 point element that exists only in an isolated data directory (`DebugStateElement`). Its value is JSON
    /// with the editor's `fontSize`, `scrollAnchor`, `readOnly` and `attachments`, which UI tests read because they cannot
    /// see them.
    static let debugState = "debug.state"
    /// A tab of the tab strip (plan 2, task 7): a button whose label is the tab's title and which is selected when the
    /// tab is the active one. There is one per open tab.
    static let tabItem = "tab.item"
    /// The close button inside a tab.
    static let tabClose = "tab.close"
    /// The "+" button at the end of the tab strip, which opens a new empty note in a new tab.
    static let tabNew = "tab.new"
}
