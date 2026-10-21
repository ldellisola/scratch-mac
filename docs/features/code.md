# Code

Code blocks, their colours and the detection of code in a paste. Spec:
[§6.4 Code block and Code highlighting](../superpowers/specs/2026-10-19-scratchpad-design.md), §6.5 (paste order), §7
(the highlight budget) and §8.1 (tree-sitter, "Code detection"). The pieces live in `ScratchCode`
(`Packages/ScratchCode`, no AppKit).

Status: plan 4, tasks 2 to 5 (the languages, the highlighter, the detection and the rendering). The paste wrap and the
label menu are added to this file by tasks 6 and 7.

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
- **The fence lines are padding.** Each is a line of exactly 6 pt with no glyphs, so the top and the bottom of a block have
  a little space and no text. While the caret or the selection touches a fence line (its two ends included, so the
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
  lines, 100 blocks) at 37 ms per scroll frame and 37 ms per keystroke, where it had been 3 ms, because every colour was
  an edit that invalidated the layout of its block and the layout manager laid the note out again in the background, on
  the main thread, a slice of tens of milliseconds at a time.
- **A keystroke in a block keeps the colours of its line** until the new result replaces them, so that the line being
  typed does not flash to the text colour (the layout manager carries a temporary attribute along with the text). A
  block whose fences changed (a fence typed or deleted, so that the pairs of fences are not what they were) is styled
  again whole, and a paragraph that leaves a block loses the colours of its code.
- **A fence line is hidden by its role.** The characters of the line (not its line break) have the marker role `fence`,
  which `MarkupLayoutManager` makes null glyphs, as for a hidden `**`. The line's paragraph style gives it a height of
  6 pt (`MarkupAppearance.codeFenceStyle`); while it is shown it has the style of the lines of code. **A line of null
  glyphs only is not 6 pt high:** the macOS CI measured 16 pt for a closing fence that ends the note, which has no line
  break to give the line a glyph, whatever its paragraph style says. The last character of the note keeps its glyph in
  that case (it is clear, so nothing is drawn), and the line is 6 pt.

### Tests

- `CodeBlockStylerTests` (hosted, `testExistingFencesRenderAsBlocks`, `testBlockIsColoured`,
  `testFenceRevealedWhenCaretOnIt`, `testStaleHighlightIsNotApplied`, `testUnnamedFenceUsesDetectedLanguage`,
  `testUnknownFenceNameIsUncoloured`, `testHugeBlockIsNotHighlighted`, `testDarkModeUsesDarkColours` and more): the
  blocks of the `typical` fixture, the `code` fixture's JavaScript block, a 6,000-line block, the colour assets.
- `CodeBlockPartsTests` (hosted): the name, the code and the fence lines of a block, found from its range.
- `MarkupStylerTests.testFencedBlockIsNotStyled`: nothing in a block is formatting, and its lines are indented.
- ScratchCore's `FixtureTests` (`codeFixtureHasABlockForEachLanguageAndOneWithoutAName`): the `code` fixture.

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
