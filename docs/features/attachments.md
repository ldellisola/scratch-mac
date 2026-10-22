# Attachments

Images and files that a note holds, and how they are drawn. Spec:
[§6.4 Attachments](../superpowers/specs/2026-10-19-scratchpad-design.md), §6.5 (paste order and copy-out) and §6.2
(the purge "along with their attachments"). Plan: [Plan 5](../superpowers/plans/2026-10-22-plan-5-attachments.md).

Status: done, released in 0.5.0 (plan 5): the token and the storage (`ScratchCore`: `AttachmentToken`, `AttachmentStore`,
schema version 3), titles that skip fence and attachment lines, the display, pasting, dropping, the paperclip and keeping
tokens whole when they are selected or deleted, opening, dragging out and copying, and the screenshots below. The decisions
(the token, files kept by reference, a line of its own, what Copy writes) are in
[docs/decisions/0008-attachments.md](../decisions/0008-attachments.md).

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

## Format commands

An attachment is one line with nothing else on it (the token), so a command that edits whole lines or puts markers around
the selection must leave the token line alone: `**[[attachment:…]]**` and `[ ] [[attachment:…]]` are text, the picture is
gone and the raw token shows. (⌘Z brings it back, and the file is kept: a stored file goes only when no note names it.)

- **⇧⌘L (Checklist) skips token lines** (`ListEditing.toggleChecklist`). A token line gets no box, and it is not a line with
  text: it does not count when the command works out whether every line is a checkbox, and it keeps the blank lines around
  it empty like a line of text does. Select All over a note of text and pictures gives the text lines boxes and leaves the
  pictures; a second press takes the boxes away. With the caret on a token line, or an attachment selected (a click), or a
  selection of nothing else, there is no line to change, so nothing is changed and it beeps.
- **⌘B (Bold) does nothing, with a beep, when the selection touches a token line** (`InlineEditing.touchesAttachment`,
  `NoteTextView.toggleBoldMarkers`): an attachment that a click selected, a selection that holds one or part of one, or a
  caret at either end of the token line (where a click beside a chip puts it, and where Backspace next to a token leaves
  it). A caret on the line below a token (where a paste leaves it) and a selection that only ends where a token starts are
  not on it, and ⌘B works there as it always did.
- **A line that holds more than the token is text** (a space before it, any character after it), judged as typed
  (`AttachmentToken.id(inLine:)`): the commands treat it as any text.
- **Return, Tab and ⇧Tab need nothing of this**: they act on bullet and checkbox lines only, and a token line is neither.
- A token inside a fenced block is text, and the commands do nothing in a block at all (formatting.md).

## Opening and dragging out

Spec §6.4: "Double-click opens the file with its default app. Dragging out of the note gives the file itself." All of it is
a click on the rectangle that is drawn (`NoteTextView.attachmentHit(atViewPoint:)`: the preview, or the chip, and not the
6 pt above and below it or the room beside a chip). It works in a note that cannot be edited too (Recently Deleted): nothing
here changes the note.

- **A single click selects the attachment**, whole, which outlines it, and the view takes the keyboard. No caret is placed
  in the token.
- **A double-click opens the stored file** (Scratch's own copy, never the original, which may be gone) with its default
  application. A third click of the series opens nothing more.
- **A missing attachment opens nothing and beeps.** So does one that is still being copied ("Copying…"), one that is a
  "Missing attachment" because its image cannot be decoded, and one whose file went from the disk after the line was drawn.
  A click on it still selects it.
- **A drag from the attachment takes the file out.** Once the mouse has moved 3 points from where it went down, a drag
  session begins whose one item is the stored file's URL, and whose picture is the preview or the chip as they are drawn
  (without the outline). It is a copy and only a copy: a drop in Finder, Mail or Slack gets the file, and Scratch's own
  copy is never moved out of its storage. A drop on a note of Scratch makes another attachment, with a copy of its own. A
  missing or copying attachment cannot be dragged.
- **Any other click is the text view's own**: one beside a chip or in the padding of a preview puts the caret at the end of
  the token line (a click never stops inside a token), and so does a click with ⇧, ⌘, ⌥ or ⌃ held (⇧ extends the selection
  over the token whole).

## Copying

Spec §6.5: Copy and Cut put plain text on the pasteboard, and "if the selection includes an attachment, its file name
appears in the text. If the selection is exactly one attachment, the file or image itself is also put on the pasteboard".
`NoteTextView.writeSelection(to:types:)` is the one place (the rules are `AttachmentCopying` in ScratchCore, tested on
Linux).

- **The text has the file's name where a token line was**: the name the owner knows (the row's), and "Missing attachment" for
  an id that no row knows. The text around it is exactly as stored, and a token inside a fenced block is copied as it was
  typed, because a block is literal. Several lines and several attachments are several names.
- **A selection that is exactly one token line** (a click selects exactly that, and so does Backspace next to one) also puts
  the file itself on the pasteboard, as one item: the name as text, the file's URL (`public.file-url`, the stored copy), and
  for an image its PNG and its TIFF. A file that is not an image has no image. An attachment whose copy is not done yet, or
  whose file is gone, has no file to put there, and only its name is copied.
- **The image is made when it is asked for, not when it is copied.** Decoding and encoding a full-size picture takes
  hundreds of milliseconds, which Copy never waits for: the PNG and the TIFF are promised and an
  `NSPasteboardItemDataProvider` (`AttachmentImageProvider`) reads the stored file and runs ImageIO when an application pastes
  them. A PNG file is its own PNG, byte for byte.
- **Cut** is Copy and then the deletion of the selection, as for text: the pasteboard is the same, and the file stays in
  Scratch's storage (nothing removes a file when a token leaves the text).
- **Pasting what was copied makes a new attachment.** The file URL comes first in the paste order (§6.5), so the paste makes
  an attachment of the stored file: a new id, a copy of its own, the same bytes. Text that holds names is pasted as those
  names.

Known limit: typing a character at either end of a token line puts it on the token's own line, which then holds more than
the token and is text again (⌘Z takes it back). A paste leaves the caret on the line after the token, so pasting and then
typing is not affected.

## Screenshots

`ScreenshotTests` takes two of the `attachments` fixture, `attachments-light` and `attachments-dark` (`make screenshots`,
published by CI in `ci-results/<sha>/macos/screenshots/`). The fixture is the note "Screenshots": a line of text, an image
(`dashboard.png`, 64 x 40 pixels), a line of text and a text file (`rollback-plan.txt`, 233 bytes). A person (or an agent that
opens the PNGs) checks, in both appearances:

- the image is a preview with rounded corners and a hairline, as the rules say: as wide as the text up to the image's own
  width, so a 64 pixel picture is 64 pt wide and 40 pt high and is never blown up (a picture that is bigger is scaled down to
  the text width and 240 pt high: `AttachmentRenderingTests`), with the text line above and below it;
- the file is a chip, 360 pt wide and 44 pt high, on the tint of the code blocks, with the file's Finder icon on the left, the
  name "rollback-plan.txt" in bold and its size, "233 bytes", under it;
- no text of a token (`[[attachment:...]]`) is visible anywhere, and no attachment is outlined (the caret is at the top of
  the note, so the selection touches none);
- the sidebar row says "Screenshots", with a preview line that begins "The dashboard after the dep…" and has no token.

The previews are decoded on a background queue after the window is up, so both tests wait for `debug.state` to report both
attachments in place (`attachments`: each one `copied`, its file on disk) and no preview left to decode (`pendingPreviews` is
zero) before the picture is taken, and they assert the sidebar's title and preview. They were looked at on CI for the
release: the preview, the chip and the sidebar are as above in light and dark. The README's `attachments.png` is
`attachments-light`, and its window pictures (`window-light`, `window-dark`, `formatting`, `code`, `search`,
`recently-deleted`) are copies of the other screenshots of the same run, taken again for the paperclip in the toolbar.

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
| ⇧⌘L leaves a token line alone: boxes on the text lines of Select All and no box in front of the token; nothing to change on an attachment | `AttachmentEditingTests.testChecklistCommandLeavesTheTokenAlone`, `testChecklistCommandOnAnAttachmentChangesNothing` |
| ⌘B on an attachment, a selection that holds one or a caret at the end of its line changes nothing; below a token it still works; in a block nothing | `testBoldCommandLeavesAnAttachmentAlone`, `testBoldCommandBelowAnAttachmentStillWorks`, `testFormatCommandsInATokenInACodeBlockDoNothing` |
| The rules (Linux): the checklist skips token lines and the blank lines around them, judges a line as typed, and the list keys never touch one; ⌘B's test of the selection | ScratchCore `ListEditingTests.toggleChecklistSkipsTokenLines`, `toggleChecklistOnlyOnATokenChangesNothing`, `toggleChecklistLeavesTheBlankLinesAroundATokenEmpty`, `toggleChecklistDoesNotCountATokenLineAsText`, `toggleChecklistJudgesATokenLineAsTyped`, `theOtherListRulesLeaveTokenLinesAlone`; `InlineEditingTests.aSelectedAttachmentIsTouched`, `aSelectionThatHoldsATokenLineIsTouched`, `aCaretAtEitherEndOfATokenLineTouchesIt`, `aCaretOrSelectionNextToATokenLineButNotOnItIsNotTouched`, `boldTreatsALineThatHoldsMoreThanTheTokenAsText` |
| The rules themselves (Linux) | `AttachmentEditingTests.swift` in ScratchCoreTests |
| The text of a copy has names for tokens, a token in a block as typed, one token alone is an attachment (Linux) | `AttachmentCopyingTests.swift` in ScratchCoreTests |
| Copy names the file in place of the token, and no more than text | `AttachmentCopyTests.testCopyOfTextAndAttachmentNamesTheFile`, `testUnknownTokenAndTokenInCodeBlockAreCopiedAsTheyAre` |
| One attachment also writes its file URL, and an image its PNG and TIFF; a file writes no image | `testCopyOfOneAttachmentWritesFileURLAndImage`, `testCopyOfOneFileWritesFileURLOnly`, `testCopyOfAnAttachmentThatIsStillBeingCopiedWritesTheNameOnly` |
| Pasting what was copied makes a new attachment | `testPastingCopiedAttachmentMakesANewOne`, `testPastingACopiedImageMakesANewImageAttachment` |
| A click hits the drawn rectangle and nothing else | `testAttachmentHitIsTheDrawnRectangle`, `testAttachmentHitOfAnImageIsItsPreview`, `testAttachmentHitInANoteWithoutAttachments` |
| A click selects; a double-click opens the stored file; a missing one opens nothing | `testSingleClickSelectsTheToken`, `testDoubleClickOpensStoredFile`, `testTripleClickDoesNotOpenTwice`, `testDoubleClickOnAnImageOpensItsStoredFile`, `testDoubleClickOnAMissingAttachmentOpensNothing`, `testDoubleClickWhenTheFileIsGoneOpensNothing`, `testReadOnlyNoteStillOpensItsAttachments` |
| A drag past 3 points takes the stored file out | `testDragWriterIsTheStoredFile`, `testDragStartsPastThreePoints`, `testNothingIsDraggedOutOfAMissingAttachment` |
| ⌘V of an image, the token and its copy survive a relaunch | `AttachmentUITests.testPastedImageShowsAndSurvivesRelaunch` |
| Backspace twice, an autosave, ⌘Z: the token and its file are back (Review Focus 1) | `AttachmentUITests.testUndoAfterDeletingAnAttachmentBringsItBack` |
| The fixture's note on screen: the preview, the chip, no token text, the sidebar's title and preview (the "Screenshots" section) | `ScreenshotTests.testAttachmentsLight`, `testAttachmentsDark` |

The display is `AttachmentRenderingTests` (hosted).
