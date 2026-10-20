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
}
