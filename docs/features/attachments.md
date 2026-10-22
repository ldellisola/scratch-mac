# Attachments

Images and files that a note holds, and how they are drawn. Spec:
[§6.4 Attachments](../superpowers/specs/2026-10-19-scratchpad-design.md), §6.5 (paste order and copy-out) and §6.2
(the purge "along with their attachments"). Plan: [Plan 5](../superpowers/plans/2026-10-22-plan-5-attachments.md).

Status: plan 5, in progress. Done so far: the token and the storage (`ScratchCore`: `AttachmentToken`,
`AttachmentStore`, schema version 3), titles that skip fence and attachment lines, the display (task 4), and pasting,
dropping, the paperclip and keeping tokens whole when they are selected or deleted (task 5). Opening, dragging out and
copying (task 6) are not there yet.

## The token

An attachment is one line of the note's plain text, `[[attachment:<lowercase UUID>]]`, with nothing else on the line
(`AttachmentToken`). The stored note stays plain text, like every other marker: copy, search and storage see the token.
A line that holds anything more is text. A token inside a fenced block is text too, and is drawn as it is typed
(nothing in a block is formatting). The file itself is Scratch's own copy, `<data directory>/attachments/<id>/<file
name>`, and the row in the `attachments` table says what it is (`AttachmentStore`).

## Display

**The text never changes.** Like every marker, an attachment line is styled with attributes and glyphs and is drawn over
(`MarkupStyler`, `MarkupLayoutManager`, `AttachmentDrawing`). The 51 characters of the token are not shown: every one but
the first is a null glyph, and the first keeps a clear glyph, which is what gives the line a line fragment of its own
(null glyphs take none: AGENTS.md). The line is as high as what is drawn on it plus 6 pt above and below, a paragraph
style with the same minimum and maximum line height.

| What | Drawn as |
|---|---|
| An image | A preview with rounded corners (6 pt) and a hairline, as wide as the text up to the image's own width, at most 240 pt high, in the proportions of the image. |
| Any other file | A chip 44 pt high and up to 360 pt wide, on the `CodeBackground` tint, with the file's Finder icon (32 pt), its name and, under it, its size (`ByteCountFormatter`, file style). |
| A file that is being copied | The same chip, with "Copying…" where the size is. |
| An id with no row, a file that is gone or a corrupt image | A chip that says "Missing attachment", with the file's name under it when the row is there. Nothing removes the row, the file or the token. |
| A selected attachment | A 2 pt outline in `controlAccentColor` just outside the preview or chip, while the selection touches the token. |

- **Sizes come from the row.** An image is sized from the pixel size in its row (read from the image's header when it
  was attached), never from the image, so a line has its height before the image is decoded. The text width is the text
  container's less the padding on each side. Before the text view has a width (a note shown at launch is styled first)
  an image is sized for a very wide text and the height cap.
- **Previews are decoded off the main thread** (`AttachmentPreviews`: ImageIO thumbnails on a serial queue, a cache of the
  biggest thumbnail of each image, 100 MB). The images that are styled first, which are the visible ones, are asked for
  first. Until a preview is there a tint stands in for it, and when it arrives only the display of its line is
  invalidated: nothing is laid out again. A preview that cannot be decoded makes the line a "Missing attachment" chip.
- **Every token line above the window has its height before the note is scrolled.** The scroll position of a shown note
  is worked out from the layout of everything above it, and a line of text is 17 pt where a preview is up to 252, so a
  token line that the chunks styled after the scroll (they style the text above the window last) moved the note under the
  reader. `MarkupStyler.noteDidLoad` styles the token lines above the paragraphs it styles at once, in the same pass as the
  blocks above the window (`styleAttachmentLines`, like `styleBlocks` for code: docs/features/code.md), and the chunks
  find them done.
- **A change of the text width styles the lines again** (`MarkupStyler.refreshAttachmentLayout`, called by the editor's
  `viewDidLayout` before it applies the scroll anchor, and a turn after any change of the text view's frame), because the
  height of a preview depends on the width. A line whose size does not change is not written.
- **What a line shows comes from `AttachmentCatalog`:** the rows (read with one query for the tokens of the paragraphs
  that are styled), and which files are being copied (`markCopying`, `markCopied`) or are undecodable. It tells the
  editor which attachment changed (`onChange`), and the lines of that attachment are styled again.

## Pasting and dropping

A paste or a drop is read in the order of spec §6.5 (`NoteTextView.readSelection(from:)`, which Paste, Paste and Match
Style and a drop all end in; `attachmentSources(from:)` decides):

1. **File references become attachments**, one for each file, in the order they are on the pasteboard. A file that is not
   there any more is left out. A file the Finder copied has its name on the pasteboard as text too: the file wins.
2. **Any text wins**, even with an image next to it (Excel, Word and browsers put both there). The text is pasted as plain
   text and goes through the code classification of [code.md](code.md), as it always did.
3. **An image with no text becomes an image attachment**, stored as PNG: the pasteboard's PNG as it is, or its TIFF
   converted (a screenshot, a picture copied from Preview). It is named "Image 2026-10-22 at 10.42.13.png". The editor
   never decodes or encodes a picture: it hands over the bytes, the row is written from the header of the image, and a TIFF
   is made into the PNG that the row says it is on the storage queue, with the copy of a file.

What goes into the note, and how:

- **Each attachment is a line of its own** (`AttachmentEditing.insertion`). A line break goes in before the first token
  unless the paste is at the start of a line, and one after the last token unless a line break follows already, so that what
  is typed next is on a line of its own and can never join a token's line. The caret ends at the start of the line after the
  last token. A paste over a selection replaces it, and several attachments are several lines. All of it is one undo step:
  ⌘Z takes every token of the paste away.
- **The token is in the note at once**, and the line says "Copying…" until the copy is there. The row is written on the main
  thread (`AttachmentImporter`: the file's size from its attributes, an image's pixel size from the header of the image, both
  quick), and the copy runs on the storage queue (`AttachmentStore.copyIn`, `writeIn`). So inserting a 50 MB file returns to
  the run loop in a few milliseconds, and `persistNow()` and quitting wait for a copy that is under way.
- **A note that cannot be edited takes nothing**: not a file, not an image, not text (a note in Recently Deleted).
- **Inside code a block is literal.** A paste or drop of files into a fenced block or into inline code inserts the file names
  as text, one on each line, and an image, which has no name, goes in nowhere. No attachment is made.
- **A drop** puts the attachments where it landed (`performDrop(of:atViewPoint:)`): the caret goes to the drop point first.
  The drag is accepted when it holds files, or an image and no text, and the note can be edited. Any other drop is the text
  view's own. A drag is judged by the types on its pasteboard (`wouldMakeAttachments(from:)`), never by its data, because it
  is asked on every move of the mouse; the data is read once, when the drop happens.
- **A paste is never classified as code when it made attachments**: its text is token lines.

## The paperclip

The paperclip in the toolbar (`toolbar.attach`, the SF Symbol `paperclip`) and File > Attach File… (⇧⌘A) show an open panel
as a sheet of the window, with several files allowed, and put the chosen files in at the caret as a paste of them would
(`NoteTextView.attachFiles()`). Both are off for a note in Recently Deleted, and cancelling the panel inserts nothing.

## Selecting and deleting a token

The rules are `AttachmentEditing` in ScratchCore (tested on Linux), carried out by `NoteTextView` and the editor's
selection delegate. A token inside a fenced block is text, and none of this applies to it.

- **The caret never stops inside a token.** A caret that lands inside one (an arrow key, a word move, a click, code) goes to
  the token's end, or to its start when it came from further on in the text, so the arrow keys step over a token. At the two
  ends of the token line the caret is allowed. (`EditorViewController`'s
  `textView(_:willChangeSelectionFromCharacterRange:toCharacterRange:)` asks `NoteTextView.snappedSelection(from:to:)`.)
- **A selection that covers part of a token covers all of it**, whichever end is inside. So cut, copy, deleting and typing
  over a selection act on whole tokens, and typing over a selected token replaces the whole token.
- **A selection can be made smaller again.** ⇧→ over a token takes it into the selection whole and ⇧← takes it out whole
  (and the mirror from below): an end that is moved back over a token, with the other end where it was, goes to the side of
  the token it came from. Only that case: a selection whose two ends both changed is a new one, and a part of a token in it
  is the whole of it.
- **Backspace right after a token selects it**, and the next press deletes it. Right after is at the end of the token line, or
  at the start of the line below it. **Delete right before a token** (at the start of the token line, or at the end of the
  line above it) selects it the same way. With the token selected, either key deletes the token and its line break, so no
  empty line is left (the line break before it when it is the last line), as one undo step.
- **A key that would join a line of text and a token line only moves the caret.** Backspace at the start of a token line
  below a line of text, and Delete at the end of a token line above one, would leave the token half a line and it would be
  text, so the caret goes over the line break and nothing is deleted. Where the other line is empty the key removes the
  empty line as it always did.

Known limit: typing a character at either end of a token line puts it on the token's own line, which then holds more than
the token and is text again (⌘Z takes it back). A paste leaves the caret on the line after the token, so pasting and then
typing is not affected.

## Tests

| Behaviour | Test |
|---|---|
| A file reference is an attachment line, with its row and its copy | `AttachmentPasteTests.testFileURLPastesAsAttachmentLine` |
| An image file's row has its pixel size and type | `AttachmentPasteTests.testImageFileRowHasPixelSizeAndType` |
| The file wins over its name as text; a file that is gone is left out | `testFileWinsOverItsNameAsText`, `testMissingFileIsLeftOut` |
| Two files are two lines, in order; a paste mid-line or over a selection gets lines of its own | `testTwoFilesTwoLines`, `testPasteMidLineGetsOwnLine`, `testPasteReplacesTheSelection` |
| An image with no text is a PNG attachment; a TIFF is converted | `testImageOnlyPastesAsPNGAttachment`, `testTIFFOnlyIsStoredAsPNG` |
| A TIFF is handed over unconverted and made into a PNG on the copy queue, not by the paste | `testTIFFPasteHandsTheImporterTheBytesUnconverted`, `testTIFFIsConvertedOnTheCopyQueue` |
| Text and an image paste the text (Review Focus 3) | `testTextAndImagePastesText` |
| A paste into code inserts the names; a read-only note takes nothing; no importer pastes text | `testPasteIntoCodeBlockPastesNames`, `testImageIntoCodeBlockInsertsNothing`, `testReadOnlyIgnoresFiles`, `testPasteWithoutImporterPastesText` |
| A 50 MB file returns in under 100 ms | `testFiftyMegabyteFileReturnsQuickly` |
| One paste is one undo step | `testOneUndoStepRemovesInsertedTokens` |
| A drop goes in at the point | `testDropOfAFileInsertsItAtThePoint`, `testDropOfTextIsNotAnAttachmentDrop` |
| A drag is judged by its types and never by its data | `testDragIsJudgedByItsTypesAndNotByItsData`, `testDragOfFilesAndImagesIsAnAttachmentDragAndTextWins` |
| The caret steps over a token; a partial selection grows (Review Focus 4) | `AttachmentEditingTests.testCaretSkipsOverToken`, `testCaretPutInsideATokenGoesToItsEdge`, `testPartialSelectionGrowsToWholeToken`, `testTokenInACodeBlockIsTextAndIsNotSnapped` |
| Backspace and Delete select, then delete (Review Focus 4) | `testBackspaceSelectsThenDeletes`, `testBackspaceAtTheEndOfTheTokenLineSelectsThenDeletes`, `testDeleteForwardSelectsThenDeletes`, `testBackspaceBelowTextDoesNotJoinTheTokenToIt`, `testDeletingOrdinaryTextIsUnchanged`, `testBackspaceInATokenInACodeBlockIsPlain`, `testReadOnlyNoteKeepsItsTokens` |
| ⇧-arrow takes a token into the selection whole and out again whole | `testShiftRightOverATokenAndShiftLeftShrinksBackOutOfIt`, `testShiftLeftOverATokenAndShiftRightShrinksBackOutOfIt` |
| Typing over a selected token replaces it whole | `testTypingOverSelectedTokenReplacesWholeToken` |
| The paperclip inserts the chosen files, and nothing when cancelled or read-only | `testPaperclipInsertsChosenFiles`, `testPaperclipCancelledOrReadOnlyInsertsNothing` |
| The rules themselves (Linux) | `AttachmentEditingTests.swift` in ScratchCoreTests |
| ⌘V of an image, the token and its copy survive a relaunch | `AttachmentUITests.testPastedImageShowsAndSurvivesRelaunch` |
| Backspace twice, an autosave, ⌘Z: the token and its file are back (Review Focus 1) | `AttachmentUITests.testUndoAfterDeletingAnAttachmentBringsItBack` |

The display is `AttachmentRenderingTests` (hosted).
