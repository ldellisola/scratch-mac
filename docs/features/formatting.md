# Formatting

The plain-text markers a note already holds render as formatting: bullets, checkboxes, bold, inline code and links.
Spec: [§6.4 Editor and formatting](../superpowers/specs/2026-10-19-scratchpad-design.md) (the marker table, list
behaviour, marker rules) and §6.5 (copy-out keeps the markers), guarding the anti-goals "Mangled code" and "Lost text"
(§4). Plan: [Plan 3](../superpowers/plans/2026-10-20-plan-3-formatting.md).

Status: plan 3, task 4 (styling, checkboxes and ⇧⌘L). The keyboard (Return, Tab, ⇧Tab, ⌘B) comes in task 5 and ⌘-click
on links in task 6, and each adds its section here.

## Behaviour: what renders

**The stored text never changes.** Styling sets attributes and glyphs only. Copy and Cut put the markers on the
pasteboard exactly as stored (`- `, `[ ] `, `[x] `, `**`, the backticks), and a paste is plain text in the note font
that then renders like typed text.

| Marker | Syntax | What the owner sees |
|---|---|---|
| Bullet | spaces, then `- ` (two spaces per level) | the `-` is transparent and a `•` in the accent colour is drawn over it. Wrapped lines hang under the text of the item. |
| Checkbox | spaces, then `[ ] `, `[x] ` or `[X] ` (`- [ ] ` is a bullet) | the `[?]` is transparent and a box is drawn over it: the symbol `square`, or `checkmark.square.fill` when ticked, in the accent colour. The text of a ticked item is struck through and dimmed (`secondaryLabelColor`). |
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

## Behaviour: checkboxes and the checklist command

- **A click on the box ticks or unticks it.** The box is the rectangle of the three characters `[?]`. A plain click there
  changes `[ ]` to `[x]` or back, and does nothing else: the caret and the selection stay where they were, so a box can
  be clicked while typing somewhere else, and the editor takes the keyboard. It is one undo step (⌘Z unticks it again).
  `[X]` counts as ticked. The edit is a single character, so nothing of the stored text changes but that one.
- **A click anywhere else is a normal click.** To the right of the box (the space and the text of the item) it places the
  caret. So does a click with ⇧, ⌘, ⌥ or ⌃ held, on a box too, and any click in a note that is read-only (a note in
  Recently Deleted): it never ticks a box. In a fenced block nothing is a checkbox.
- **⇧⌘L (Format > Checklist) toggles a checklist** on the lines of the selection, or on the caret's line when there is
  none. When every line with text in it is a checkbox, the `[?] ` markers go. Otherwise each line that is not a
  checkbox becomes one: a bullet's `- ` is replaced with `[ ] `, and any other line gets `[ ] ` after its indentation.
  Blank lines between lines with text stay empty. The selection moves with its text, and the whole command is one undo
  step.
- **It does nothing, with a beep,** in a read-only note and when a fenced block is among the lines (the selection holds
  one, or starts or ends in it): no marker is put into code. A line next to a block is fine.
- The commands that change the text (this one, and the keyboard rules of task 5) are in the **Format** menu, after Edit.
  Its items go to whoever has the keyboard: only the editor answers them.

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
- `MarkupLayoutManager.swift`: null glyphs for `hidden` markers, the bullets and the boxes. `MarkupAppearance.swift`: the fonts,
  colours and paragraph styles. `MarkupAttributes.swift`: the `scratchMarker` and `scratchLink` attributes, `MarkerRole`
  and `MarkupColors`. `ParagraphBatch.swift`: whole paragraphs read in one call.
- `NoteTextView`: `mouseDown` (a click on a box), `checkboxMarker(atViewPoint:)`, `toggleCheckbox(atViewPoint:)`,
  `toggleChecklist(_:)` (⇧⌘L) and `apply(_:)`, which makes the core's `TextEdit` one undo step. `MainMenu.formatMenu`
  is the Format menu. The core rules are `ListEditing.toggleCheckmark` and `ListEditing.toggleChecklist`.
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
| A click on a box ticks or unticks it, keeps the caret and the keyboard, and changes only that box | `CheckboxTests.testClickingCheckboxTogglesWithoutMovingCaret`, `testClickingATickedUppercaseBoxUnticksIt`, `testClickingOneBoxChangesOnlyThatBox`, `testClickingABoxMovesTheKeyboardToTheEditor` |
| A click is one undo step | `testUndoAfterCheckboxClick` |
| Only the box is a toggle: not the space after it, the item's text, a read-only note or a code block | `testClickRightOfBoxIsNotAToggle`, `testReadOnlyCheckboxIgnoresClick`, `testNothingInACodeBlockIsACheckbox` |
| ⇧⌘L makes a checklist and takes it away again, from a selection, a caret or bullets, as one undo step | `testToggleChecklistOnSelection`, `testToggleChecklistWithoutSelectionUsesTheCaretsLine`, `testToggleChecklistTurnsABulletIntoABox`, `testChecklistCommandIsOneUndoStep` |
| ⇧⌘L from the keyboard goes through the Format menu, and ⌘Z after it takes back the checklist and not the typing before it | `ChecklistUITests.testChecklistShortcutTurnsTheLineIntoACheckbox`, `testCommandZAfterTheChecklistShortcutTakesBackOnlyTheChecklist` |
| ⇧⌘L does nothing in a code block or a read-only note | `testToggleChecklistInACodeBlockDoesNothing`, `testToggleChecklistInAReadOnlyNoteDoesNothing`, ScratchCore `CodeBlockIndexTests.intersects…` |
| The box is drawn, open as an outline and ticked filled | `testCheckboxSymbolIsDrawn` |
| The Format menu follows Edit and has Checklist on ⇧⌘L | `testFormatMenuHasTheChecklistShortcut` |
| Markers in a fenced block and in inline code are literal | `testFencedBlockIsNotStyled`, `testMarkersInsideInlineCodeAreLiteral` |
| Unclosed markers are plain | `testUnclosedMarkersArePlain` |
| A closing fence turns the lines between into code, and removing it turns them back | `testTypingAClosingFenceTurnsTheLinesBetweenIntoCode`, `testTypingInsideABlockKeepsTheBlock` |
| Styling registers no undo | `testStylingDoesNotRegisterUndo`, `testTypingInStyledTextIsOneUndoStepThatStylesTheTextAgain` |
| Copy keeps the markers, and pasted text renders like typed text | `testCopyKeepsMarkers`, `testPastedTextRendersLikeTypedText` |
| A note of 10,000 lines is styled in chunks, an edit while it is pending is carried over, a big paste too | `testHugeNoteIsFullyStyledSoon`, `testAnEditWhileTheRestOfANoteIsStyledKeepsTheRestRight`, `testABigPasteIsStyledAfterwards` |
| ScratchCore: the blocks of a note, carried over edits; the position mapping; the prefilter | `CodeBlockIndexTests`, `EditMappingTests`, `MarkupPrefilterTests` |
