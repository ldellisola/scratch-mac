# Paste and copy

What the editor does with text that comes in and text that goes out, and what it never does to text that is typed.
Spec: [§6.5 Clipboard](../superpowers/specs/2026-10-19-scratchpad-design.md) and §6.4 (one font, no smart
substitutions), guarding the anti-goals "Font contamination", "Rich-text leakage" and "Mangled code" (§4).

Status: plan 1 (walking skeleton). Plain text only. Later plans add code detection on paste (plan 3), attachments and
file references (plan 4), and may add rich copy-out.

## Behaviour

- **Paste takes the note's font and colours.** Whatever the source put on the pasteboard, only its text is used. Font,
  size, colour and style are dropped, so pasted text looks exactly like typed text. This holds for rich text from a
  browser, Word or Excel.
- **"Paste and Match Style" is the same as Paste.**
- **Copy and Cut put plain text only on the pasteboard.** No RTF, RTFD or HTML. Nothing of the note's font or colours
  reaches Slack, mail or a terminal. The text is exactly what the editor holds.
- **Nothing is substituted while typing or pasting.** Smart quotes, smart dashes, text replacement, auto-correct,
  spell and grammar checking, link and data detection, text completion and smart insert/delete are all off. A straight
  quote stays straight, `--` stays two hyphens, and the characters of pasted code are never changed.
- **One font.** Every character is SF Mono 13 pt in the standard text colour (`NoteTextView.noteFont`).

## Where it lives

All of it is in `App/Sources/Editor/NoteTextView.swift`:

- `applyScratchConfiguration()` makes the view a plain-text editor and turns every substitution off.
  `TextViewFactory.makeEditor(mode:)` calls it.
- `readablePasteboardTypes` is `[.string]`: the one place that decides what a paste takes.
- `writablePasteboardTypes` is `[.string]` and `writeSelection(to:types:)` writes the selected text as `.string` and
  nothing else: the one place that decides what Copy, Cut, drags and Services put out. Rich copy-out would be added
  here (spec §6.5, "for now").

## Tests

Hosted tests in `App/Tests/ScratchAppTests/NoteTextViewTests.swift`. They run inside the app on CI and use a
pasteboard of their own, never the real clipboard. The first four run on both the TextKit 1 and the TextKit 2 editor,
because `-ScratchTextKit` can start the app on either.

| Behaviour | Test |
|---|---|
| Rich text pasted (Times New Roman 24 pt, red) lands in the note font and colour | `testPastingRichTextUsesNoteFont` |
| Every substitution flag is off, plain text mode, note font | `testSmartSubstitutionsAreOff` |
| Typed straight quotes and `--` stay as typed | `testTypedStraightQuotesStayStraight` |
| Copy writes `.string` and no `.rtf`, `.rtfd` or `.html` | `testCopyWritesOnlyPlainText` |
| The TextKit 1 editor keeps its text storage and layout manager after `makeEditor` returns | `testTextKitOneEditorKeepsItsTextStack` |
| The TextKit 2 editor has a text layout manager and no owned TextKit 1 storage | `testTextKitTwoEditorUsesTextLayoutManager` |

Not covered yet: pasting through the real Edit menu in a running app, and Cut. Both go through the same two pasteboard
type lists as the tests above.
