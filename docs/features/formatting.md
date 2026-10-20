# Formatting

The plain-text markers a note already holds render as formatting: bullets, checkboxes, bold, inline code and links.
Spec: [§6.4 Editor and formatting](../superpowers/specs/2026-10-19-scratchpad-design.md) (the marker table, list
behaviour, marker rules) and §6.5 (copy-out keeps the markers), guarding the anti-goals "Mangled code" and "Lost text"
(§4). Plan: [Plan 3](../superpowers/plans/2026-10-20-plan-3-formatting.md).

Status: plan 3, task 3 (styling). Checkboxes get their symbol and clicks in task 4, the keyboard (Return, Tab, ⇧Tab,
⌘B, ⇧⌘L) in task 5 and ⌘-click on links in task 6, and each adds its section here.

## Behaviour: what renders

**The stored text never changes.** Styling sets attributes and glyphs only. Copy and Cut put the markers on the
pasteboard exactly as stored (`- `, `[ ] `, `[x] `, `**`, the backticks), and a paste is plain text in the note font
that then renders like typed text.

| Marker | Syntax | What the owner sees |
|---|---|---|
| Bullet | spaces, then `- ` (two spaces per level) | the `-` is transparent and a `•` in the accent colour is drawn over it. Wrapped lines hang under the text of the item. |
| Checkbox | spaces, then `[ ] `, `[x] ` or `[X] ` (`- [ ] ` is a bullet) | the `[?]` is transparent (the box is drawn in plan 3, task 4). The text of a ticked item is struck through and dimmed (`secondaryLabelColor`). |
| Bold | `**text**` on one line, no spaces at its edges | the text between the stars in the bold weight of the note font |
| Inline code | `` `text` `` on one line | the text in the colour `CodeText` on the tint `CodeBackground` (the asset catalog, light and dark) |
| Link | `http://` or `https://` and then non-space characters | `linkColor`, underlined. Trailing `.,;:!?'"` and an unmatched `)` are not part of it. |

- **Inside a fenced block** (a pair of lines that start with three backticks) and **inside inline code**, every
  character is literal: `- ` and `**` in a pasted shell script render as typed. A fence without a partner is not a
  block, so typing three backticks never un-renders the rest of the note. A new fence line, or a changed one, restyles
  the paragraphs that moved in or out of a block.
- **An unclosed `**` or backtick is plain text.** Typing `**x` shows the stars; typing the second `**` closes the run.
- **Hidden markers.** The `**` of a closed bold run and the backticks of inline code are hidden: they have no glyph and
  no width. While the caret or the selection **touches** the run, the positions at its two ends included, they show
  dimmed (`tertiaryLabelColor`). The caret never stops on a character that cannot be seen, so Backspace right behind a
  bold run deletes one visible star. A selection of more than 20,000 characters shows none.
- **One font.** The bold weight is the only change to the font. The note font size changes everything together, bold
  runs and indents included.
- **Undo.** Styling is never an undo step.

## Behaviour: when it is styled

- A keystroke, a paste or an undo restyles only the paragraphs it edited.
- A note that is shown is styled around its top line first (±200 paragraphs, before the first layout), and the rest in
  chunks of 1,000 paragraphs, one per main run loop turn after the frame. A note of 10,000 lines is on screen at once
  and fully styled a few turns later.
- A paste of more than 20,000 characters is styled in the same chunks.

## Where it lives

- ScratchCore `Markup/`: `MarkupParser` (the spans of a line), `LinkScanner`, `FenceScanner`, `CodeBlockIndex` (the
  blocks of a note, carried over edits), `EditMapping` (where positions go when text is replaced) and
  `MarkupParser.mayHaveSpans` (skips the parse of a line that cannot hold a span).
- `App/Sources/Editor/MarkupStyler.swift`: the text storage's delegate. Styles paragraphs, reveals and hides markers when
  the selection changes (`selectionDidChange`, called by `EditorViewController`), styles a shown note
  (`noteDidLoad(visibleRange:)`), answers `isInCodeBlock`, `checkboxMarker(at:)` and `link(at:)`.
- `MarkupLayoutManager.swift`: null glyphs for `hidden` markers, the bullets. `MarkupAppearance.swift`: the fonts,
  colours and paragraph styles. `MarkupAttributes.swift`: the `scratchMarker` and `scratchLink` attributes, `MarkerRole`
  and `MarkupColors`. `ParagraphBatch.swift`: whole paragraphs read in one call.
- `NoteTextView.load` and `applyFontSize` go through the styler. `TextViewFactory` builds the stack with the styler
  and the layout manager.

## Tests

| Behaviour | Test |
|---|---|
| A bold run is bold and its stars are null glyphs while the caret is away | `MarkupStylerTests.testBoldContentIsBoldAndMarkersAreNullGlyphs` |
| The markers show while the caret touches the run, at both edges, and for a selection | `testMarkersRevealedWhenCaretTouchesRun`, `testMarkersAreRevealedAtBothEdgesOfTheRun`, `testASelectionThatTouchesTheRunRevealsItsMarkers` |
| Backspace behind a bold run deletes one visible star | `testBackspaceAfterBoldDeletesOneVisibleStar` |
| Typing the closing `**` makes the run, and the markers hide when the caret leaves | `testTypingClosesBoldRun` |
| The font size changes bold runs too | `testFontSizeChangeKeepsBold` |
| Inline code has the asset colours, and the colours are the specified ones | `testInlineCodeColours`, `testTheCodeColoursComeFromTheAssets` |
| A link is coloured and underlined and keeps its URL | `testLinkIsColouredAndUnderlined` |
| A bullet or checkbox line hangs its wrapped lines under the text | `testBulletParagraphHasHangingIndent` |
| A ticked item is struck through and dimmed, and the box is the `[?]` only | `testCheckedLineIsStruckThrough` |
| Markers in a fenced block and in inline code are literal | `testFencedBlockIsNotStyled`, `testMarkersInsideInlineCodeAreLiteral` |
| Unclosed markers are plain | `testUnclosedMarkersArePlain` |
| A closing fence turns the lines between into code, and removing it turns them back | `testTypingAClosingFenceTurnsTheLinesBetweenIntoCode`, `testTypingInsideABlockKeepsTheBlock` |
| Styling registers no undo | `testStylingDoesNotRegisterUndo`, `testTypingInStyledTextIsOneUndoStepThatStylesTheTextAgain` |
| Copy keeps the markers, and pasted text renders like typed text | `testCopyKeepsMarkers`, `testPastedTextRendersLikeTypedText` |
| A note of 10,000 lines is styled in chunks, an edit while it is pending is carried over, a big paste too | `testHugeNoteIsFullyStyledSoon`, `testAnEditWhileTheRestOfANoteIsStyledKeepsTheRestRight`, `testABigPasteIsStyledAfterwards` |
| ScratchCore: the blocks of a note, carried over edits; the position mapping; the prefilter | `CodeBlockIndexTests`, `EditMappingTests`, `MarkupPrefilterTests` |
