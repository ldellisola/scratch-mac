# 0008: Attachments are a token line, stored by reference, on lines of their own

Status: accepted, 2026-10-22 (Plan 5, Scratch 0.5.0). Settles what spec §8.2 left to the builder ("The attachment token
syntax, database schema and file layout") and records the [call]s of Plan 5 that the spec only outlines: the layout of an
attachment in the note, when a stored file is removed, and what Copy puts on the pasteboard. No new dependency: images
are decoded with ImageIO and files are copied with Foundation.

## Decision

1. **The token is a line of plain text.** An attachment is one line of the note, `[[attachment:<id>]]`, where `<id>` is a
   lowercase UUID (`AttachmentID`, like `NoteID`), with no other character on the line, not even a space before it
   (`AttachmentToken.id(inLine:)` accepts exactly that, and a line that has more is text). A token inside a fenced block is
   text and is drawn as typed. The stored note stays plain text: copy, search, the title and the sidebar's preview all
   see the token, and the title and the preview skip the line (as they skip fence lines), so a note that holds only
   attachments is titled "Untitled".
2. **Scratch keeps its own copy, in a folder of its own and a row.** A file is copied to
   `<data directory>/attachments/<id>/<file name>` (the name is made safe: `/` and `:` become `-`, an empty name or `.` or
   `..` becomes `file`) and described by a row of the new `attachments` table (schema version 3: id, note id, the name as
   the owner knows it, type identifier, size in bytes, pixel size of an image, creation time, and whether the copy is in
   place). The copy is made on the storage queue, never on the main thread, into a temporary file that is renamed onto the
   name, so the name is never a half-written file. The token and the row are made at once, and the line says "Copying…"
   until the copy is there. A token with no row, a row with no file and an image that cannot be decoded are drawn as
   "Missing attachment" and nothing removes them.
3. **A stored file goes by reference, never by count.** A file and its row are removed only when no stored note body, live
   or in Recently Deleted, has the token's text anywhere in it (`NoteStore.referencedAttachmentIDs`,
   `AttachmentToken.referencedIDs`, wider than the whole-line rule on purpose), and only at two moments: right after the
   note that held the token was deleted permanently or purged (`ScratchStorage.deletePermanently`, `purge`: only the ids
   that were in the removed bodies are asked about), and at the launch sweep, for a row created more than 24 hours earlier.
   Deleting a token never removes anything, so Backspace and then ⌘Z, in the same session or after an autosave, brings the
   attachment back with its file.
4. **An attachment sits on a line of its own, and is drawn over its token.** An inserted attachment gets a line break before
   it unless it starts a line, and one after it unless a line break follows, so the caret ends on the line below. Several
   attachments are several lines. The token's 51 characters are not shown (null glyphs, but the first: AGENTS.md), and the
   line is as high as what is drawn on it plus 6 pt above and below. An image is a preview as wide as the text up to its own
   width and at most 240 pt high, with rounded corners of 6 pt; any other file is a chip 44 pt high and up to 360 pt wide
   with the file's Finder icon, its name and its size. A selected attachment has a 2 pt accent outline. The caret never stops
   inside a token, a selection grows to hold a token it touches, and Backspace or Delete next to a token selects it first.
5. **Copy names the files, and one attachment also copies the file.** Copy and Cut write plain text in which each token is
   its file name (a token in a fenced block, as typed, and one that no row knows as "Missing attachment"). When the selection
   is exactly one token line they also write the stored file's URL and, for an image, its PNG and TIFF (promised, and made
   when an application asks). Pasting that later makes a new attachment with a copy of its own.
6. **Paste and drop read the pasteboard in the order of spec §6.5**: file URLs, then text (which wins over an image, so
   Excel, Word and browsers paste text), then an image with no text, stored as PNG. A read-only note takes nothing, and a
   paste or drop into a fenced block or inline code inserts file names as text.

## Why

- **A token line keeps the stored note plain text**, as every other marker does (spec §6.4): the text view's storage never
  holds an `NSTextAttachment`, so copy, search, undo, autosave and the TextKit 1 editor's styling stay what Plans 1 to 4
  built, and a note that is read with `sqlite3` or exported shows where each file was. The syntax is one that nobody types
  by accident (a Markdown image, `![](...)`, is something a note about Markdown holds), it names the attachment and not a
  path (the original can move), and it is matched as a whole line, so that text that merely mentions it is text.
- **Removing by reference is the one rule that cannot lose a file.** A reference count in the row would drift with every
  paste, undo, edit and crash, and a file lost to a wrong count cannot come back. The text of the stored notes is the only
  truth, so the removal reads it, inside one `Database` transaction with the removal, and counts a token anywhere in a body
  (even one the owner broke by hand and can fix again, or one in a code block) as a reference. The cost is a file that stays
  for a day or two, or for good when a stray token names it, which costs only disk, against the cost of an owner's image
  gone. Spec §6.2 says that a purge goes "along with their attachments": it does, once no other note names the file.
- **An own line is the layout that the text system can keep correct.** A preview is a paragraph as tall as the image, so the
  token line has the height the layout needs before the image is decoded (from the row's pixel size, never from the image),
  and a click, a selection and a deletion all act on a line, never on a place inside one. A token that shares a line with
  text would have to be drawn in the text, and Plan 3 and 4's hiding and block styling are built on whole lines.
- **Copying one attachment as a file is what the spec asks** (§6.5: "the file or image itself is also put on the
  pasteboard") and the text with the names is what it asks for the rest. An image is promised and not encoded on copy,
  because a full-size picture takes hundreds of milliseconds and Copy must not wait for them.

## Consequences

- The schema is version 3. A newer database is refused by older versions of Scratch (`SchemaError.newerThanSupported`), and
  a migration works the sidebar's derived columns out again for the new title and preview rule.
- A token that the owner types by hand is an attachment when it names a row and "Missing attachment" when not. Copy puts a
  token on the pasteboard only when it is inside a fenced block, where it is text like all the rest, so a note's tokens
  do not leave Scratch otherwise.
- Typing a character at either end of a token line puts it on the token's own line, and the line is then text again (⌘Z
  takes it back). A paste leaves the caret on the line below, so pasting and then typing is not affected.
- A rich copy-out, if it comes (spec §6.5: "for now"), extends one place, `NoteTextView.writeSelection(to:types:)`, with the
  rules in `AttachmentCopying`.
- Tests: ScratchCore's `AttachmentTokenTests`, `AttachmentStoreTests` (`sweepNeverRemovesAReferencedFile`),
  `ScratchStorageTests` (`deletePermanentlyRemovesUnsharedFiles`, `sharedTokenKeepsFile`), `AttachmentEditingTests` and
  `AttachmentCopyingTests`; the hosted `AttachmentRenderingTests`, `AttachmentPasteTests`, `AttachmentEditingTests` and
  `AttachmentCopyTests`; and `AttachmentUITests`. docs/features/attachments.md lists each behaviour with its test.
