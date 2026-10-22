# Paste and copy

What the editor does with text that comes in and text that goes out, and what it never does to text that is typed.
Spec: [§6.5 Clipboard](../superpowers/specs/2026-10-19-scratchpad-design.md) and §6.4 (one font, no smart
substitutions), guarding the anti-goals "Font contamination", "Rich-text leakage" and "Mangled code" (§4).

Status: plan 1 (walking skeleton), since plan 4 code detection on paste, and since plan 5 file references and images on
paste and the names and files of attachments on copy. Later plans may add rich copy-out.

## Behaviour

- **Paste takes the note's font and colours.** Whatever the source put on the pasteboard, only its text is used. Font,
  size, colour and style are dropped, so pasted text looks exactly like typed text. This holds for rich text from a
  browser, Word or Excel.
- **"Paste and Match Style" is the same as Paste.**
- **Paste order** (spec §6.5). The pasteboard's text is inserted first, as plain text, exactly as above. Then, on the next
  turn of the run loop, text of two lines or more that looks like code is wrapped in a fence with its language, an edit of
  its own: ⌘Z once gives back the plain pasted text, and ⌘Z again removes it. Prose, a single line, a paste into code and a
  paste that holds a fence line are left as pasted. The rules are in docs/features/code.md ("Pasting code"). File
  references come before the text in this order and become attachments, and an image with no text comes after it and
  becomes an image attachment, stored as PNG (plan 5; the rules are in docs/features/attachments.md, "Pasting and
  dropping"). Text that comes with an image (Excel, Word, browsers) is pasted as text.
- **Copy and Cut put plain text only on the pasteboard.** No RTF, RTFD or HTML. Nothing of the note's font or colours
  reaches Slack, mail or a terminal. The text is exactly what the editor holds, except for attachments (plan 5, spec
  §6.5): each token line is written as the name of its file, and a selection that is exactly one attachment also puts the
  file's URL there, and for an image its PNG and TIFF (docs/features/attachments.md, "Copying").
- **Nothing is substituted while typing or pasting.** Smart quotes, smart dashes, text replacement, auto-correct,
  spell and grammar checking, link and data detection, text completion and smart insert/delete are all off. A straight
  quote stays straight, `--` stays two hyphens, and the characters of pasted code are never changed.
- **One font.** Every character is SF Mono 13 pt in the standard text colour (`NoteTextView.noteFont`).

## Where it lives

All of it is in `App/Sources/Editor/NoteTextView.swift`:

- `applyScratchConfiguration()` makes the view a plain-text editor and turns every substitution off.
  `TextViewFactory.makeEditor()` calls it.
- `readablePasteboardTypes` is `[.string, .fileURL, .png, .tiff]`: AppKit offers Paste, and accepts a drag, only for a
  pasteboard that has one of them. The order of preference is not this list's: `readSelection(from:)` reads the files
  first (`attachmentSources(from:)`), then text as `.string` and nothing else, then an image, and
  `preferredPasteboardType(from:restrictedToTypesFrom:)` makes AppKit's own choice `.string` whenever there is text.
- `paste(_:)`, `pasteAsPlainText(_:)` and `readSelection(from:)` start and end a paste (`beginPaste`, `endPaste`), and the
  wrap of a paste of code is `PasteClassifier` (`App/Sources/Editor/PasteClassifier.swift`).
- `writablePasteboardTypes` is `[.string]` and `writeSelection(to:types:)` writes the selected text as `.string` and
  nothing else, except the one attachment that is selected whole (`AttachmentCopying`, `AttachmentPasteboard`): the one
  place that decides what Copy, Cut, drags and Services put out. Rich copy-out would be added here (spec §6.5, "for now").

## Tests

Hosted tests in `App/Tests/ScratchAppTests/NoteTextViewTests.swift`. They run inside the app on CI and use a
pasteboard of their own, never the real clipboard. The editor is TextKit 1 only (docs/decisions/0001), so every test
runs on the one editor `TextViewFactory.makeEditor` makes.

| Behaviour | Test |
|---|---|
| Rich text pasted (Times New Roman 24 pt, red) lands in the note font and colour | `testPastingRichTextUsesNoteFont` |
| Every substitution flag is off, plain text mode, note font | `testSmartSubstitutionsAreOff` |
| Typed straight quotes and `--` stay as typed | `testTypedStraightQuotesStayStraight` |
| Copy writes `.string` and no `.rtf`, `.rtfd` or `.html` | `testCopyWritesOnlyPlainText` |
| The editor is TextKit 1 and keeps its text storage and layout manager after `makeEditor` returns | `testEditorKeepsItsTextKitOneStack` |
| Loading and typing leave the editor on TextKit 1 (a layout manager, no text layout manager) | `testEditorStaysOnTextKitOneWhileEditing` |

Pasting with the real keys is covered by `CodePasteUITests` (⌘V of code, of an email and in the middle of a line). Not
covered yet: pasting through the Edit menu with the mouse, and Cut. Both go through the same two pasteboard type lists as
the tests above.
