# Attachments

Images and files that a note holds, and how they are drawn. Spec:
[§6.4 Attachments](../superpowers/specs/2026-10-19-scratchpad-design.md), §6.5 (paste order and copy-out) and §6.2
(the purge "along with their attachments"). Plan: [Plan 5](../superpowers/plans/2026-10-22-plan-5-attachments.md).

Status: plan 5, in progress. Done so far: the token and the storage (`ScratchCore`: `AttachmentToken`,
`AttachmentStore`, schema version 3), titles that skip fence and attachment lines, and the display below (task 4).
Pasting, dropping and the paperclip (task 5), opening, dragging out and copying (task 6) are not there yet.

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

Tests: `AttachmentRenderingTests` (hosted).
