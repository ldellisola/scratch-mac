# Code

Code blocks, their colours and the detection of code in a paste. Spec:
[§6.4 Code block and Code highlighting](../superpowers/specs/2026-10-19-scratchpad-design.md), §6.5 (paste order), §7
(the highlight budget) and §8.1 (tree-sitter, "Code detection"). The pieces live in `ScratchCode`
(`Packages/ScratchCode`, no AppKit).

Status: plan 4, tasks 2 to 4 (the languages, the highlighter and the detection). Rendering, the paste wrap and the
label menu are added to this file by tasks 5 to 7.

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
