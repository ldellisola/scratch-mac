# Code

Code blocks, their colours and the detection of code in a paste. Spec:
[§6.4 Code block and Code highlighting](../superpowers/specs/2026-10-19-scratchpad-design.md), §6.5 (paste order), §7
(the highlight budget) and §8.1 (tree-sitter, "Code detection"). The pieces live in `ScratchCode`
(`Packages/ScratchCode`, no AppKit).

Status: plan 4, done and released as 0.4.0: the languages, the highlighter, the detection, the rendering, the paste wrap,
the label menu, the blocks typed by hand, and the screenshots and the performance numbers below.

## Rendering

A fenced block (a line of three backticks, lines of code, a line of three backticks) is drawn as a block. Nothing is
changed in the note's text: the characters, copy, search and storage stay as they are, and every look below is an
attribute or a drawing (`MarkupStyler`, `CodeBlockStyler`, `MarkupLayoutManager`). A fence that has no partner is not a
block (docs/features/formatting.md).

- **The tint.** A rounded block (6 pt radius) in the `CodeBackground` colour, black at 6% in light mode and white at 10%
  in dark mode, as wide as the text (the width of the editor less its margins). It is drawn from the opening fence line
  to the closing one, behind the lines.
- **The lines.** Each line of the block is 10 pt in from both sides of the tint (head and tail indent), in the note font,
  and nothing in it is formatting (no bullet, bold or link).
- **The fence lines are padding.** Each is a line of exactly 6 pt with nothing drawn on it, so the top and the bottom of a
  block have a little space and no text. While the caret or the selection touches a fence line (its two ends included, so the
  caret just below the opening fence or just above the closing one does not) the line is shown in full, in
  `tertiaryLabelColor`, and is as high as any line. A selection of more than 20,000 characters shows none.
- **The label.** At the top right of the block, 2 pt smaller than the note font, in `secondaryLabelColor`: the language
  (`Swift`, `Shell`, `C#`), or the name as written for a fence name that is not one of the 17 (`ruby`). A language that
  was detected, which is when the fence has no name, is in italics: it means "automatic". A fence with no name whose
  code is not code, or of a language Scratch does not know, has no label. A block that is too long to colour shows its
  name only.
- **The colours** are Xcode's default themes (spec §6.4, plan 4 "Colours"), assets named `Code<Kind>` with a light and a
  dark variant: keyword `#9B2393` / `#FC5FA3`, string `#C41A16` / `#FC6A5D`, comment `#5D6C79` / `#7F8C98`, number
  `#1C00CF` / `#D0BF69`, type `#0B4F79` / `#5DD8FF`, function `#326D74` / `#67B7A4`, attribute `#815F03` / `#BF8555`,
  preprocessor `#643820` / `#FD8F3F`. Everything else has the text colour.
- **Which language.** The name on the opening fence, by its fence name or an alias in any case (`py`, `JS`, `c#`). An
  empty name is detected from the code between the fences (`CodeDetector`, below), and the fence is never edited. A
  name that is not one of the 17 gives an uncoloured block, with the name as its label.
- **Too long to colour.** A block of more than 5,000 lines or 300,000 UTF-16 units (spec §7) stays tinted and is not
  coloured; nothing is copied out of the text for a block over the length, and the text is pasted as fast as any other.

### How the colours get on the page

- **Never on the main thread.** `CodeBlockStyler` sends the code of a block to a private serial queue, one request at a
  time, the blocks on screen first. `MarkupStyler` asks for the blocks of what it styles first (the paragraphs around
  the visible ones when a note is shown), then for the rest in the idle chunks that style a long note.
- **A result is for a text.** It is applied only to a block that holds the same fence name and the same code, compared
  by hash and then as text. A result for text that has been edited since is dropped (`droppedResults`), and the edit has
  already asked for the block again. So a block that only moved is coloured from a cache of results, and so is a note
  that is shown again.
- **The main thread only writes colours,** when the run loop is next about to wait, after the observers that end a
  performance signpost, at most 8 ms at a time. A block with thousands of tokens is written over several turns.
- **The colours are temporary attributes of the layout manager,** not attributes of the text (a deviation from the
  plan, which says "colours"). They are for display only, so writing them lays nothing out again and adds no run to the
  text storage. As attributes of the text they were several times slower: the macOS CI measured the huge note (10,000
  lines, 100 blocks) at 37 ms per scroll frame and 37 ms per keystroke, where it had been 0.3 and 3 ms, because every colour was
  an edit that invalidated the layout of its block and the layout manager laid the note out again in the background, on
  the main thread, a slice of tens of milliseconds at a time.
- **Every block above the window has its final look before the note is laid out.** The position of a shown note is worked
  out from the layout of what is above it, and the chunks that style a long note run after that. A fence line is 6 pt
  and a line of code wraps sooner for its indent, so a block that was styled by a chunk moved the note under the reader
  (the CI: the top line of the huge note after a relaunch was three lines off). `MarkupStyler.styleBlocks` styles every
  block that starts above the end of the window in one pass for each block, and the chunks find that done.
- **A keystroke in a block keeps the colours of its line** until the new result replaces them, so that the line being
  typed does not flash to the text colour (the layout manager carries a temporary attribute along with the text). A
  block whose fences changed (a fence typed or deleted, so that the pairs of fences are not what they were) is styled
  again whole, and a paragraph that leaves a block loses the colours of its code.
- **A fence line is hidden by its role.** The characters of the line (not its line break) have the marker role `fence`,
  which `MarkupLayoutManager` makes null glyphs, as for a hidden `**`, and a clear colour. The line's paragraph style
  gives it a height of 6 pt (`MarkupAppearance.codeFenceStyle`); while it is shown it has the style of the lines of code.
  **The first character of the line keeps its glyph** (clear, so nothing is drawn). A null glyph is zero wide and TextKit
  puts it at the end of the line above, so a line of null glyphs only has no line fragment of its own: the macOS CI
  measured the first character of a fence line in the fragment of the line above (16 pt), and a closing fence that ends
  the note, with no line break after it, had no padding at all. With one glyph the line is a fragment of its own, 6 pt
  high, which is also where a click on the padding puts the caret (and shows the fence).

### What it costs (the macOS CI, the huge note: 10,000 lines, 100 `swift` blocks)

`keystroke_ms` 3.2 to 5.7 (baseline 6.3), `switch_huge_ms` 25 to 31 (baseline 65.9), `scroll_frame_ms` 0.3 to 7.1 (baseline
5.8). The CI runners differ so much in the time they take for a frame (0.3 ms on a fast one, 4.5 ms in the prose and 7 ms
in the blocks on a slow one, for the same build) that the scroll number is the one to read against the baseline of the same
kind of runner: a run over 6.96 ms on a slow runner is a rerun before it is a regression (AGENTS.md section 4).

### Tests

- `CodeBlockStylerTests` (hosted, `testExistingFencesRenderAsBlocks`, `testBlockIsColoured`,
  `testFenceRevealedWhenCaretOnIt`, `testStaleHighlightIsNotApplied`, `testUnnamedFenceUsesDetectedLanguage`,
  `testNothingAboveTheWindowChangesHeightWhenTheRestOfTheNoteIsStyled`,
  `testUnknownFenceNameIsUncoloured`, `testHugeBlockIsNotHighlighted`, `testDarkModeUsesDarkColours` and more): the
  blocks of the `typical` fixture, the `code` fixture's JavaScript block, a 6,000-line block, the colour assets.
- `CodeBlockPartsTests` (hosted): the name, the code and the fence lines of a block, found from its range.
- `MarkupStylerTests.testFencedBlockIsNotStyled`: nothing in a block is formatting, and its lines are indented.
- ScratchCore's `FixtureTests` (`codeFixtureHasABlockForEachLanguageAndOneWithoutAName`): the `code` fixture.

### The language label menu

Spec §6.4 "Code highlighting": the label on a block is also a small menu for changing the language or turning the block
back into plain text (`CodeBlockMenu`, `NoteTextView`).

- **Opening it.** A plain click on the label (its rectangle, with a margin of 3 pt: `NoteTextView.labelHit`, which asks
  `MarkupLayoutManager.labelRect(forBlockAt:)` for the rectangle the label is drawn in) opens the menu under it and does
  nothing else: no caret is placed, and the selection stays where it was. A click with ⇧, ⌘, ⌥ or ⌃ held is the text
  view's own. A note that cannot be edited (Recently Deleted) shows no menu, and the click is the text view's own too.
- **What is in it.** The 17 languages in the order of their names (C, C#, C++, CSS, Go, HTML, Java, JavaScript, JSON,
  PowerShell, Python, Rust, Shell, SQL, Swift, TypeScript, YAML), with a tick on the block's current language (a detected
  one too); a separator; "Plain Text", ticked when the fence is named `text`; and "Not Code".
- **Each choice is an edit of the fence lines, and one undo step** (`CodeBlockMenu.edit`, applied through
  `NoteTextView.apply(_:)`, and ⌘Z gives the fence back):
  - a language replaces the name on the opening fence and nothing else: `bash` becomes `python`, a fence with no name gets
    one (an automatic block becomes the owner's, so its label is no longer in italics), and spaces before the backticks
    and the number of backticks are kept. Choosing the language the fence names already changes nothing, and is no undo
    step;
  - "Plain Text" names the block `text`: it stays a tinted block with no colours, and its label says `text`;
  - "Not Code" takes both fence lines away and keeps the lines between them exactly as they are (line breaks as they
    were, an empty line stays one). Two fences with nothing between them are taken away with one line break, so that no
    empty line is left.
- **The caret stays where it was in the text.** A caret in the code stays in the same place of the code, one in the
  opening fence goes to the end of the new name (or to the start of the code, for "Not Code"), and one in the closing
  fence to the end of the code that is left. The view takes the keyboard, as a click in it does.
- **No label, no menu.** A fence with no name whose code is not code, or is a language Scratch does not know, shows no
  label (see "The label" above), so it has nothing to click. Typing a name on its fence gives it one.

### Blocks typed by hand

Spec §6.4: a block started by typing the fence gets its language from what is in it, as the owner types. A block typed
by hand has no name on its fence, so every highlight request of it (the first one, and the one that each edit of the
block makes) finds the language again from the code between the fences (`CodeDetector`, on the highlight queue), and
sets the label, in italics: it means "automatic". Until the closing fence is typed there is no block, and nothing is
detected; when it is typed the block is looked at as any other. The fence is never edited by detection: the owner's text
stays as it was typed, and only the label menu (or typing a name) writes a language on it. While the detection has no
language yet (one line, or code that is not code) there is no label, and one appears when there is.

Tests: `CodeBlockMenuTests` (hosted: `testSetLanguageRewritesFence`, `testPlainTextKeepsBlockUncoloured`,
`testNotCodeRemovesFencesOnly`, `testMenuListsEveryLanguageWithCurrentTicked`, `testLabelHitTest`,
`testTypedBlockGetsDetectedLabel`, `testReadOnlyShowsNoMenu`, and the edits, the caret, the click and a note with no label).
No hosted test opens the menu on screen (`NSMenu.popUp` runs a tracking loop) or sends a click that is not on a label.

## Pasting code

Spec §6.4 "Code highlighting" and §6.5 (paste order). A paste is the plain paste first: the pasteboard's text goes in as
it always did (docs/features/paste-and-copy.md). When it turns out to be code, it is wrapped in a fence in a second edit
(`NoteTextView`, `PasteClassifier`).

- **Candidates.** A paste of two lines or more (the line break that ends the last line does not start another: `"a\n"` is
  one line). A single line stays plain, and so does everything that `CodeDetector` calls prose (Review Focus 1: an email
  with a signature, a numbered list, meeting notes with times, a log excerpt, a CSV row, a list of URLs).
- **Never into code.** A paste into a fenced block (the fence lines included), or between the backticks of inline code,
  stays plain: the owner pasted into code, there is nothing to wrap. This is decided before the paste, because a paste
  of several lines splits the line that inline code was on.
- **Never with a fence of its own.** A paste that has a fence line in it (three backticks or more, after spaces) stays as
  it is: it is a block already, or part of one.
- **Never below a fence that has no partner.** A fence line above the paste that nothing closes is a block the owner is
  still typing (a fence, Return, then the paste). The wrap's two fences would pair with it and take the note's blocks
  apart, so the paste stays plain and the owner types the closing fence. A paste after blocks that are closed is wrapped.
- **The wrap.** One edit that puts the pasted text between two fence lines:
  - the opening fence names the detected language by its fence name (`python`, not `py`): ```` ```python ````. Code of a
    language Scratch does not know (Ruby, PHP) gets a fence with no name, an uncoloured block;
  - a line break goes before the opening fence when the paste did not start a line, and after the closing fence when it did
    not end one, so that the fences are lines of their own and the text around the paste keeps its own lines;
  - the closing fence is on the line after the last pasted line, and when the paste ended with a line break that break is
    the one before the fence, so the block has no blank line that was not pasted;
  - **every pasted character is inside the fences as it came**: no re-indenting, no trimming, no change of line breaks.
  The caret ends up where it was, after everything that was pasted.
- **Two undo steps.** The wrap is applied on the next turn of the main run loop, once the undo group of the paste has
  closed, so ⌘Z once leaves exactly the pasted text, and ⌘Z again takes it away. The wrap is one `apply(_:)`.
- **When the text changes first, nothing is wrapped.** A key typed, or a note loaded, between the paste and the wrap
  cancels it. A note that cannot be edited takes no paste at all.
- **Paste and Match Style** is the same as Paste, and so is a paste with the real Edit menu: all of them end in
  `readSelection(from:)`.

### How fast it is

The `paste-code` signpost interval (`Signposts.beginOpenEditorInterval`) runs from the paste until the colours of the
block are on screen: the plain paste, the detection, the wrap, the highlighting on its queue and the colours written back.
The performance test pastes 500 lines of Swift into an empty note (`CodePastePerfTests`, `paste_code_ms`, budget 50 ms,
spec §7). A paste that is not wrapped ends the interval at the next idle moment.

On the macOS CI the median is 55 to 85 ms (79.2 in the run of the final screenshots), which is a WARN above the budget
and under the 100 ms where the check fails. The reason is the runner and not a step of the paste: the same build takes 55
ms on a fast runner and 85 ms on a slow one, as `launch_ms` (506 to 871 ms against a budget of 400) and `switch_small_ms`
do, and the slowest of five runs is the baseline (docs/decisions/0003, "Addendum: `paste_code_ms`"). The table there has the five
runs, with the fastest and the slowest of the ten pastes of each.

### Tests

- `CodePasteTests` (hosted, `readSelection(from:)` with a pasteboard of its own): `testMultiLinePythonPasteIsFenced`,
  `testSingleLinePasteStaysPlain`, `testPasteMidLineGetsFenceOnItsOwnLines`, `testPasteInsideBlockIsNotFenced`,
  `testPasteWithFencesStaysAsIs`, `testProseSampleStaysPlain`, `testUnknownLanguageGetsUnnamedFence`, and the cases above:
  a paste ending with a line break, into inline code, below an unmatched fence, edited before the wrap, in a read-only note,
  and `PasteClassifier.wrap` itself.
- `CodePasteUITests` (real keys and the real pasteboard): `testUndoAfterCodePasteRestoresPlainText` (Review Focus 2),
  `testPastingAnEmailStaysPlain` (Review Focus 1) and a paste in the middle of a line.
- `CodePastePerfTests.testPasteFiveHundredLinesOfCode`: `paste_code_ms`.

## Screenshots

`ScreenshotTests` takes two of the `code` fixture, `code-light` and `code-dark` (`make screenshots`, published by CI in
`ci-results/<sha>/macos/screenshots/`), and `typical-*` and `formatting-*` have a block each. A person (or an agent that
opens the PNGs) checks, in both appearances:

- every block is a rounded, tinted block, with no fence line in sight (the caret is in the first line of the note);
- each block has its label at the top right: `Swift`, `Python`, `SQL`, `JSON`, `Shell`, and `JavaScript` in italics for the
  block whose fence has no name (the detected language); the `bash` block of `typical` says `Shell` and the `sh` block of
  `formatting` too, upright;
- keywords are `#9B2393` (light) or `#FC5FA3` (dark), strings `#C41A16` or `#FC6A5D`, comments `#5D6C79` or `#7F8C98`,
  numbers `#1C00CF` or `#D0BF69`, types `#0B4F79` or `#5DD8FF`, functions (`curl`, `fetch`) `#326D74` or `#67B7A4`, and
  attributes (`@app.route`) `#815F03` or `#BF8555`, as in Xcode's default themes.

The colours come from a background queue after the window is up, so both tests wait for `debug.state` to report no pending
highlight (`pendingHighlights` is zero) before the picture is taken. The note is 44 lines, and the whole of it, the last
block included, fits the 1024 x 674 window. They were looked at on CI for the release: all six blocks, their labels and
their colours are as above in light and dark (pixels of every colour in the table above are in both PNGs), and the blocks
of `typical` and `formatting` look the same way. The
README's `code.png` is `code-light`, and its other pictures are copies of the `typical`, `formatting` and `search`
screenshots of the same run.

## Detection

`CodeDetector.detect(_:)` answers one question about a text of two lines or more: is it code, and in which language?
It is offline and deterministic (the same text always gives the same answer) and it never changes the text.

- **Prose stays prose.** When unsure, it is not code (spec §6.4). A text is code only when the mean evidence of its lines
  is 0.5 or more and at least two of its lines are code that is not a comment. Evidence is read from the lines:
  - code: a call (`foo(x)`), an operator (`==`, `=>`, `::`), a `{` that opens a block, a comment marker, a tag, a shell
    command, a `$variable`, a `;` or a `}` at the end, `import x`, `const x = 1`
  - prose: a whole sentence, a line of a wrapped paragraph
  - neither: a heading, a list item, a label such as `Subject:`, a URL, a number, a rule of `=====`
- **Inline code is a word.** What is between backticks does not count: ``Call `init()` first`` is a sentence.
- **A paste of one line is never code**, and neither is a text of comments only.
- **Which language.** The idioms of each language give it points (`func` with a type, `def f():`, `package main`,
  `SELECT … FROM`, `#!/bin/bash`, a JSON document, `<!DOCTYPE html>`). A language that is far ahead is the answer.
  Otherwise at most four candidates are parsed with tree-sitter, and the one with the fewest syntax errors wins
  (`Highlighter.errorRate`). TypeScript and JavaScript share their idioms, so the ones only TypeScript has (`: number`,
  `interface`, `type X =`) decide between them.
- **Code of a language Scratch does not know** (Ruby, PHP, Kotlin, XML) is code with no language (`language` is nil): an
  uncoloured block with an unnamed fence. So is code that several grammars read equally well and that has no idiom of
  any of them (`for (int i = 0; i < 3; i++) {`).
- **A shebang is `#!` and a path** (`#!/bin/bash`, `#! /usr/bin/env python3`) on the first line, and only that is a
  marker. `#!important remember this` and a bare `#!` are text: they go through the lines like any other paste.
- **Speed.** Only the first 300 lines (40,000 bytes) are read and the first 50 lines (4,000 bytes) are parsed. 500
  lines take 2 to 12 ms in Release (the budget is 20 ms) and under 100 ms in the Debug test run.

### Tests

`Packages/ScratchCode/Tests/ScratchCodeTests/CodeDetectorTests.swift`, against the corpus in
`Tests/ScratchCodeTests/Corpus/`:

- `<fence name>/`: at least 4 samples of each language, 3 to 60 lines, one of them short and one with comments.
  `everyCodeSampleIsCodeWithItsLanguage` wants the folder's language for each.
- `unknown/`: code of languages Scratch does not know. They must come out as code with no language.
- `prose/`: emails with a signature and a quoted reply, meeting notes with times, lists, a log, a CSV, a note with
  `**bold**`, a recipe, a few lines of verse, a chat, error messages, a two-line "Hi, thanks!". `everyProseSampleStaysProse`
  wants nil for each. **A prose sample is never deleted to make a test pass.**

A paste that is detected wrongly becomes a sample, and the detector is changed until every sample passes. Every sample is
written for the corpus: no text of someone else's.
