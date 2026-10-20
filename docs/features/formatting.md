# Formatting

The plain-text markers a note already holds render as formatting: bullets, checkboxes, bold, inline code and links.
Spec: [§6.4 Editor and formatting](../superpowers/specs/2026-10-19-scratchpad-design.md) (the marker table, list
behaviour, marker rules) and §6.5 (copy-out keeps the markers), guarding the anti-goals "Mangled code" and "Lost text"
(§4). Plan: [Plan 3](../superpowers/plans/2026-10-20-plan-3-formatting.md).

Status: released in 0.3.0 (plan 3): styling, checkboxes, ⇧⌘L, the keyboard (Return, Tab, ⇧Tab and ⌘B) and ⌘-click on
links.

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
- The commands that change the text (this one, and ⌘B below) are in the **Format** menu, after Edit. Its items go to
  whoever has the keyboard: only the editor answers them.

## Behaviour: Return, Tab, ⇧Tab and ⌘B

The rules are the core's (`ListEditing.newline`, `indent` and `outdent`, `InlineEditing.toggleBold`). The editor gives
them the paragraphs under the selection, applies what they answer as one undo step (⌘Z takes back one Return, one Tab or
one ⌘B), leaves the caret where the rule puts it and scrolls to it. A list is a bullet or checkbox line; an indent is two
spaces.

- **Return on a list item with text** starts the next item below the caret, with the same indentation and an open
  marker: `- ` for a bullet, `[ ] ` for a checkbox, also after a ticked one. The text after the caret moves to the new
  item, so Return in the middle of an item splits it.
- **Return on an empty item** ends the list, or steps out of a level: an item that is indented loses one indent (it
  moves to the level of its parent), and one at the first level loses its marker and leaves an empty line.
- **Return is a plain line break** when the caret is in the indentation or inside the marker (before the item's text, so
  Return above an item inserts a plain line above it), when text is selected (it is replaced, as in any text view), on a
  line that is not a list item, anywhere in a fenced block, and in a note that cannot be edited.
- **Tab indents the list lines of the selection** (the caret's line when there is none) by one unit, and ⇧Tab takes up to
  one unit away. Lines of the selection that are not list lines stay as they are, and the selection moves with its
  text. A selection of several lines is one undo step.
- **Tab elsewhere inserts a tab,** the same as in any text view: on a line that is not a list line, with no list line in
  the selection, and anywhere a fenced block is under the selection. A selection that holds a fenced block is not
  indented, because a block is code: Tab then replaces the selection with a tab, as it does in any text view.
- **⇧Tab on a list line that is not indented does nothing.** On a line that is not a list line it is AppKit's own.
- **⌘B (Format > Bold)** puts `**` around the selection, and the selection then covers the text between the stars. A
  selection that is exactly the text of a bold run, or the whole run with its stars, loses the stars instead. White space
  at the ends of the selection (a triple click takes the line break) stays outside the stars, because a run that starts
  or ends with white space is not bold. With no selection `****` goes in and the caret between the pairs, so what is
  typed next is bold. The stored text is the only thing that changes: bold is not a font setting.
- **⌘B does nothing, with a beep,** in a note that cannot be edited, when a fenced block is under the selection, and for
  a rectangular selection (several selections, which no key rule handles either).
- **Copy still keeps the stars:** after ⌘B and a select-all, ⌘C puts `**word**` on the pasteboard.

## Behaviour: links open with ⌘-click

A link is the `http://` or `https://` text that the table above colours and underlines. Clicking it is a click in the
text like any other, so that placing the caret in a link never opens a browser.

- **A ⌘-click on a link opens it** in the default browser (`NSWorkspace`), and does nothing else: the caret and the
  selection stay where they were. It works in a note that cannot be edited (a note in Recently Deleted) too, since opening
  a link changes nothing. The URL is the link as the parser found it, so the period or the unmatched `)` after a link
  at the end of a sentence is not part of it.
- **A plain click on a link only places the caret.** So does a click with ⇧ or ⌥ and no ⌘. A ⌘-click anywhere that is
  not on a link is the text view's own click.
- **The click has to be on a character of the link.** The space to the right of a link that ends its line, the margin and
  the space below the last line are not the link.
- **Inline code and fenced blocks have no links.** A URL in `` `inline code` `` or in a block is literal text, so a
  ⌘-click there opens nothing (the styler gives such a URL no link attribute).
- **The cursor shows it.** While ⌘ is held over a link the cursor is the pointing hand, and it is the I-beam again when
  the mouse moves off the link or ⌘ is let go. The view hears the moves of the mouse through a tracking area
  (`mouseMoved`) and the keys through `flagsChanged`, which only the view that has the keyboard receives: with the
  keyboard somewhere else (in the title field, say) the pointing hand shows with the next move of the mouse. The view
  puts the I-beam back only after it has set the pointing hand itself, and never changes the cursor otherwise.

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
- `NoteTextView`: `mouseDown` (a click on a box, a ⌘-click on a link), `checkboxMarker(atViewPoint:)`,
  `toggleCheckbox(atViewPoint:)`, `toggleChecklist(_:)` (⇧⌘L) and `apply(_:)`, which makes the core's `TextEdit` one undo
  step; `insertNewline(_:)`, `insertTab(_:)` and `insertBacktab(_:)` (Return, Tab, ⇧Tab, through `listEdit`, which asks
  the core's rule unless a block is under the selection) and `toggleBoldMarkers(_:)` (⌘B); `openURL` (what a ⌘-click on
  a link does: it opens the browser, and tests replace it), `link(atViewPoint:)` (the URL under a point, only on a
  character of the link) and `updateLinkCursor(atViewPoint:modifiers:)`, which `mouseMoved(with:)` and
  `flagsChanged(with:)` call, with the tracking area of `updateTrackingAreas()` (the pointing hand).
  `MainMenu.formatMenu` is the Format menu. The core rules are `ListEditing` (`newline`, `indent`, `outdent`,
  `toggleChecklist`, `toggleCheckmark`) and `InlineEditing.toggleBold`.
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
| A ⌘-click on a link opens its URL (without the period after it), the link under the click, at its edges, on a wrapped line and in a read-only note, and places no caret | `LinkTests.testCommandClickOpensLink`, `testCommandClickOpensALinkAfterHiddenMarkers`, `testCommandClickOpensTheLinkUnderTheClick`, `testCommandClickOnTheEdgesOfALinkOpensIt`, `testCommandClickOnTheWrappedPartOfALinkOpensIt`, `testCommandClickOpensLinkInAReadOnlyNote` |
| A plain click, or a click with ⇧ or ⌥, opens nothing; nor does a ⌘-click off a link, in inline code or in a fenced block | `testPlainClickDoesNotOpen`, `testClickWithOtherModifiersDoesNotOpen`, `testCommandClickOutsideLinkDoesNothing`, `testLinkInsideInlineCodeIsNotOpened`, `testLinkInsideAFencedBlockIsNotOpened` |
| A link is found only over its own characters | `testLinkIsFoundOnlyOverItsOwnText` |
| The pointing hand shows only while ⌘ is held over a link, and the view asks for the mouse moves | `testPointingHandShowsOnlyWhileCommandIsHeldOverALink`, `testTheViewTracksMouseMoves` |
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
| Return continues a bullet or a checkbox (an open box after a ticked one), keeps the indentation and splits an item | `ListKeyTests.testReturnContinuesBullet`, `testReturnSplitsTheItemAtTheCaret`, `testReturnOnATickedItemAddsAnOpenBox`, `testReturnKeepsTheIndentation`, `FormattingUITests.testTypingAListByKeyboard`, `testChecklistShortcutThenReturn` |
| Return on an empty item ends the list, or outdents a nested item | `testReturnOnEmptyItemEndsList`, `testReturnOnEmptyNestedItemOutdentsIt` |
| Return is a plain line break before the marker, on a plain line, with a selection, in a block and in a read-only note | `testReturnBeforeTheMarkerInsertsAPlainLine`, `testReturnOnAPlainLineIsPlain`, `testReturnWithASelectionReplacesIt`, `testReturnInsideCodeBlockIsPlain`, `testReturnOnAListLineBesideABlockStillContinuesTheList`, `testReturnInAReadOnlyNoteChangesNothing` |
| Tab indents the list lines of the selection and ⇧Tab outdents them | `testTabIndentsListLine`, `testTabIndentsEveryListLineOfTheSelection`, `testShiftTabOutdents`, `testShiftTabOnATopLevelListLineChangesNothing`, `FormattingUITests.testTabIndentsNestedBullet` |
| Tab is a tab on a plain line and in a block, and nothing in a read-only note | `testTabOnAPlainLineInsertsATab`, `testTabInsideCodeBlockInsertsATab`, `testTabInAReadOnlyNoteChangesNothing`, `testShiftTabOnAPlainLineChangesNoText` |
| ⌘B wraps the selection, takes the stars off a bold run, or puts the caret between a pair | `testCommandBWrapsSelection`, `testCommandBOnABoldRunTakesTheStarsAway`, `testCommandBWithoutSelectionPutsTheCaretBetweenTheStars` |
| ⌘B does nothing in a block or a read-only note | `testCommandBInsideCodeBlockDoesNothing`, `testCommandBInAReadOnlyNoteDoesNothing` |
| ⌘B is Format > Bold, and copy after it keeps the stars | `testFormatMenuHasBoldOnCommandB`, `FormattingUITests.testCommandBThenCopyKeepsMarkers` |
| Each of these edits is one undo step | `testEachEditIsOneUndoStep` |
| Markers in a fenced block and in inline code are literal | `testFencedBlockIsNotStyled`, `testMarkersInsideInlineCodeAreLiteral` |
| Unclosed markers are plain | `testUnclosedMarkersArePlain` |
| A closing fence turns the lines between into code, and removing it turns them back | `testTypingAClosingFenceTurnsTheLinesBetweenIntoCode`, `testTypingInsideABlockKeepsTheBlock` |
| Styling registers no undo | `testStylingDoesNotRegisterUndo`, `testTypingInStyledTextIsOneUndoStepThatStylesTheTextAgain` |
| Copy keeps the markers, and pasted text renders like typed text | `testCopyKeepsMarkers`, `testPastedTextRendersLikeTypedText` |
| A note of 10,000 lines is styled in chunks, an edit while it is pending is carried over, a big paste too | `testHugeNoteIsFullyStyledSoon`, `testAnEditWhileTheRestOfANoteIsStyledKeepsTheRestRight`, `testABigPasteIsStyledAfterwards` |
| The whole table renders in light and dark: hanging bullets, boxes, a struck-through ticked item, hidden stars, tinted code, a coloured link and a fenced block as typed (the `formatting` fixture; a person looks at the PNGs in `ci-results`) | `ScreenshotTests.testFormattingLight`, `testFormattingDark` |
| ScratchCore: the blocks of a note, carried over edits; the position mapping; the prefilter | `CodeBlockIndexTests`, `EditMappingTests`, `MarkupPrefilterTests` |
