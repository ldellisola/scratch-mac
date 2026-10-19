# 0001: The editor uses TextKit 1

Status: accepted, 2026-10-19 (plan 1, task 10). Decides the question left open in spec §8.2: "TextKit 1 vs TextKit 2,
chosen by measuring against the §7 budgets".

## Decision

The editor is an `NSTextView` on the **TextKit 1** stack (`NSTextStorage`, `NSLayoutManager`, `NSTextContainer`), built
by `TextViewFactory`. TextKit 2 is not used, and the switch that chose between them (`TextKitMode`, the
`-ScratchTextKit` launch argument, `make perf TEXTKIT=`) is removed.

The reason is the keystroke budget (§7: at most 8 ms of main-thread work per keystroke in a note of up to 10,000
lines). In a note of 10,000 lines TextKit 1 needs 3.6 to 4.5 ms per keystroke on the CI runner and TextKit 2 needs 19.8
to 28.0 ms, 2.5 to 3.5 times the budget. Both stacks can hide the `**` markers of a bold run cleanly (below), so the
spec's tie-breaker, "if both can, choose TextKit 2", does not apply: TextKit 2 does not meet the budget.

## How it was measured

On a throwaway branch (`spike/textkit`, deleted after this record was written) the performance tests of this task ran
on each stack, on the GitHub-hosted runner the rest of CI uses: `macos-26`, an Apple virtual machine, macOS 26.6.2,
Xcode 26.6, the Release build, arm64. Runner and tests are described in `AGENTS.md`; the numbers are the median of
each test's measurements (15 to 100 iterations), in milliseconds, one column per run of the whole suite:

| Metric | CI budget | TextKit 1, run 1 | run 2 | run 3 | TextKit 2, run 1 | run 2 |
|---|---|---|---|---|---|---|
| `launch_ms` | 400 (spec: 200) | 581.5 | 441.7 | 372.4 | 491.2 | 620.1 |
| `keystroke_ms` | 8 | 4.5 | 3.6 | 3.7 | **28.0** | **19.8** |
| `scroll_frame_ms` (95th percentile of 300 frames) | 8 | 7.2 | 3.7 | 5.3 | **15.1** | **16.2** |
| longest of the 300 frames (not checked) | | 34.3 | 5.5 | 12.0 | 31.1 | 50.7 |
| `switch_small_ms` | 8 | 13.5 | 11.0 | 7.6 | 16.6 | 12.1 |
| `switch_huge_ms` | 50 | 45.4 | 64.1 | 40.3 | 20.6 | 18.6 |

Two earlier rounds of the suite, with earlier versions of the same tests, gave the same picture: keystroke medians of
3.2 to 6.7 ms for TextKit 1 (five runs) against 19.5 to 38.5 ms for TextKit 2 (four runs). Runs on this runner differ a
lot (the first run of a job is the slowest in both stacks), which is why the CI check compares medians with a baseline
that is the slowest run (`docs/decisions/0003-ci-performance-checks.md`). The gap between the stacks in keystroke time
and in scroll frames is not noise: every TextKit 2 run is slower than every TextKit 1 run in both.

What the metrics are, in short: `keystroke_ms` runs from `NoteTextView.keyDown` to the moment the main run loop is next
about to wait, which is after AppKit has laid out, drawn and committed the character (a character typed about a third of
the way into the 10,000-line note, 100 times). `switch_*_ms` is the same for a click on a sidebar row, until the note is
on screen. `scroll_frame_ms` is the main thread's work per frame while the app scrolls the huge note by itself. The
intervals end when the main run loop is idle, and not when the work returns, so that TextKit's lazy layout and drawing
are inside them.

### Where TextKit 2's time goes

A second set of signposts around the steps of a keystroke (`NoteTextView.insertText`, `layout`, `draw`, the
`textDidChange` callback), in the 10,000-line note and in a small one (6 lines). Medians in milliseconds:

| | whole keystroke | `insertText` | `layout` | `draw` | `textDidChange` callback |
|---|---|---|---|---|---|
| TextKit 1, 10,000 lines | 5.0 | 1.6 | 0.00 | 0.12 | 0.03 |
| TextKit 1, 6 lines | 4.6 | 1.5 | 0.01 | 0.10 | 0.03 |
| TextKit 2, 10,000 lines | **29.5** | **20.2** | 2.6 | never called | 0.03 |
| TextKit 2, 6 lines | 5.3 | 1.8 | 0.9 | never called | 0.02 |

(These runs have more signposts than the ones in the table above, which is why the totals differ a little. In TextKit 2
`draw(_:)` of the text view was not called once in 60 keystrokes: it draws in layers, which is why the keystroke
interval ends when the run loop is idle and not when `draw(_:)` returns.) TextKit 1
costs the same for any note size. TextKit 2 pays for the size of the note inside `insertText` itself: 1.8 ms for 6
lines, 20 ms for 10,000. A hosted test that inserts into a text view in a window that is never shown (3.5 ms for
TextKit 1, 3.0 ms for TextKit 2 with 10,000 lines) does not show it, so the cost appears only when the view is on
screen. The CI has no profiler, and I did not find out which step inside `insertText` it is. I tried no tuning of the
TextKit 2 view (for example not resizing it to the height of the text): the decision rests on the stack as the editor
needs it.

TextKit 2 is better at one thing: switching to the 10,000-line note (19 to 21 ms against 40 to 64 ms, because it lays
out lazily), which is the one metric where TextKit 1 is over its budget in some runs. That is a warning, not a failure,
and `NoteTextView.load` sets the text, the font and the colour in three passes, which is a known place to save time.

### The string conversion is not the cost

`Note.displayTitle`, `Note.preview` and `TextOffset.clamp` scan Swift strings, and the editor's string is a bridged
`NSString`. Per keystroke in the 10,000-line note (848,893 UTF-16 units, hosted test, microseconds):

| | read `textView.string` | title and preview | clamp |
|---|---|---|---|
| TextKit 1 | 5 | 80 | 4 |
| TextKit 2 | 6 | 67 | 3 |

The `textDidChange` callback, which reads the string and hands it to the coordinator, takes 0.03 ms in the app. Neither
the title and preview (computed when a note is saved, on the storage queue, and not per keystroke) nor the offset clamp
(once per note shown) matter for the budgets. Converting the text on every edit is not why TextKit 2 is slow.

## Hiding the `**` markers of a bold run

Plan 3 hides the markers of bold runs without changing the text (the copy still has them). The prototype hid the
markers of `**don't deploy after 4pm on fridays**` in the `typical` fixture's first note and set the run in bold, and a
hosted test asked each stack where the caret is for each index of `ab **cd** ef` (the x coordinate in points):

```
index                0    1    2    3    4    5    6    7    8     9     10    11    12
TextKit 1, plain     29.0 37.0 45.1 53.1 61.1 69.2 77.2 85.3 93.3  101.3 109.4 117.4 125.4
TextKit 1, null      29.0 37.0 45.1 53.1 53.1 53.1 61.1 69.2 69.2  69.2  77.2  85.3  93.3
TextKit 2, zero-wid. 29.0 37.0 45.1 53.1 53.1 53.1 61.1 69.2 69.2  69.2  77.2  85.3  93.3
TextKit 2, tiny font 29.0 37.0 45.1 53.1 53.2 53.2 61.3 69.3 69.4  69.4  77.5  85.5  93.5
TextKit 1, tiny font 29.0 37.0 45.1 53.1 53.2 53.2 61.3 69.3 69.4  69.4  77.5  85.5  93.5
TextKit 2, deleted   29.0 37.0 45.1 53.1 61.1 69.2 77.2 85.3 -100  -100  -100  -100  -100
```

With the markers hidden, the carets at 3, 4 and 5 (before, between and after the opening markers) share one x and so do
those at 7, 8 and 9: the markers take no room, and `cd` is two characters wide (16 points). Screenshots, from the same
run (light mode, 1024 x 674 px):

| Technique | Screenshot |
|---|---|
| TextKit 1, markers visible | [`tk1-plain.png`](0001-textkit-version/tk1-plain.png) |
| TextKit 1, null glyphs | [`tk1-glyphs.png`](0001-textkit-version/tk1-glyphs.png) |
| TextKit 1, 0.1 pt font and clear colour | [`tk1-tiny.png`](0001-textkit-version/tk1-tiny.png) |
| TextKit 2, markers visible | [`tk2-plain.png`](0001-textkit-version/tk2-plain.png) |
| TextKit 2, paragraph with the markers deleted | [`tk2-paragraph.png`](0001-textkit-version/tk2-paragraph.png) |
| TextKit 2, paragraph with zero-width spaces for the markers | [`tk2-zerowidth.png`](0001-textkit-version/tk2-zerowidth.png) |
| TextKit 2, 0.1 pt font and clear colour | [`tk2-tiny.png`](0001-textkit-version/tk2-tiny.png) |

- **TextKit 1, null glyphs (the technique to use).** An `NSLayoutManagerDelegate` implements
  `layoutManager(_:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:)`, copies the glyph properties,
  sets `.null` on the glyphs whose character index is in a marker, and calls `setGlyphs(_:properties:characterIndexes:font:forGlyphRange:)`
  (returning the glyph count). Zero width, exact caret positions, the text storage untouched:

  ```swift
  func layoutManager(
      _ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
      properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
      characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont, forGlyphRange glyphRange: NSRange
  ) -> Int {
      var modified = [NSLayoutManager.GlyphProperty](repeating: [], count: glyphRange.length)
      var changed = false
      for index in 0..<glyphRange.length {
          modified[index] = props[index]
          if hiddenCharacterIndexes.contains(charIndexes[index]) { modified[index] = .null; changed = true }
      }
      guard changed else { return 0 }
      layoutManager.setGlyphs(glyphs, properties: modified, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
      return glyphRange.length
  }
  ```

  The delegate class conforms with `@preconcurrency NSLayoutManagerDelegate`, and the delegate must be kept alive by
  its owner (the layout manager's delegate is weak). Bold is plain text attributes on the text between the markers.
- **TextKit 2, same-length paragraphs (works).** An `NSTextContentStorageDelegate` implements
  `textContentStorage(_:textParagraphWith:)`, copies the paragraph's attributed string and replaces each marker
  character with U+200B (zero-width space), so the paragraph keeps its length and the offsets stay right. Same caret
  positions as null glyphs.
- **TextKit 2, deleted markers (does not work).** The same delegate with the markers *removed* from the paragraph hides
  them, but the paragraph is shorter than the stored text, and the layout cannot place any index after the first hidden
  marker (the rectangle for the caret is empty: -100 above).
- **A 0.1 pt font with the clear colour (works on both, a hack).** Zero width to within 0.1 point; the markers are real
  text with an invisible style, and typing next to a marker inherits that style unless the code resets it.
- **In every technique the caret still stops at each hidden marker character**, once per character, because the stored
  text is unchanged. Plan 3 decides how arrow keys, selection and deletion treat them (for example adjusting the
  selection in `textView(_:willChangeSelectionFromCharacterRange:toCharacterRange:)`); this prototype did not try.

## Why not TextKit 2

TextKit 2 is the newer API and the one Apple develops, which is a reason to prefer it. It is not enough here:

- It misses the keystroke budget by 2.5 to 3.5 times, in a note that §7 says must stay inside it, and its cost grows
  with the length of the note. The spec's rule is "choose the mode that meets the budgets".
- It is worse on every other metric measured but switching to the huge note.
- TextKit 1 can do everything the editor needs, including marker hiding, with the techniques above.

## Consequences

- `TextViewFactory.makeEditor()` builds the TextKit 1 stack by hand and keeps the text storage in
  `NoteTextView.ownedTextStorage`. An `NSTextView` made any other way (`NSTextView()`, `NSTextView(frame:)`, a nib) is a
  TextKit 2 view on macOS 26, so every editor goes through the factory. `NoteTextViewTests` checks that the editor has a
  layout manager and no text layout manager.
- Removed: `TextKitMode`, `LaunchOptions.textKit` and its error, the `-ScratchTextKit` flag, the TextKit 2 branch of
  the factory, `TEXTKIT=` on `make perf` and the tests of both stacks (the tests now test the one).
- If a later macOS makes TextKit 2 fast on large notes, the way to find out is to build the editor on it again behind a
  launch argument and run `make perf` on each, as this record did. Until then there is no reason to.
- Plan 3 hides markers with the null glyph technique above. The prototype is not kept in the repository: the code is
  in this record.
