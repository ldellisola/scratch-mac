# Accessibility

What VoiceOver hears, what the keyboard reaches, and how the window looks with Increase Contrast. Spec:
[§6.1](../superpowers/specs/2026-10-19-scratchpad-design.md) ("Accessibility settings such as Reduce Transparency and
Increase Contrast must be respected, which system materials do automatically"), §6.4 (the markers) and §6.5. Plan:
[Plan 6](../superpowers/plans/2026-10-22-plan-6-polish.md), task 8.

Status: plan 6, task 8 (1.0.0). Nothing here changes a character of a note: what VoiceOver reads is made from the styled text,
and `accessibilityValue` stays the stored text.

## VoiceOver

### The note

The editor is labelled "Note" and its title "Title". A range of the note is read as the editor shows it, and not as it is
stored. `NoteTextView.accessibilityString(for:)` and `accessibilityAttributedString(for:)` ask `SpokenText.spoken(_:range:)`,
which reads the attributes that the styler gave the text (`scratchMarker`, `scratchCodeBlock`, `scratchAttachment`):

| In the note | Spoken |
|---|---|
| hidden and revealed markers (the `**` of bold, the backticks of inline code) | nothing |
| a bullet marker (`-`) | "bullet" |
| `[ ]` | "unchecked" |
| `[x]` | "checked" |
| an image token | "image, dashboard.png" |
| a file token | "file, rollback-plan.txt" |
| a token whose file is being copied | "attachment, rollback-plan.txt, copying" |
| a missing token | "missing attachment" |
| an opening fence | "code block, Swift", or "code block" when the fence has no name and no language was detected |
| a closing fence | "end of code block" |

So `[ ] buy milk` is "unchecked buy milk", `a **bold** word` is "a bold word", and a block is "code block, Swift", its code
line by line and "end of code block". Every other character is read as it is, and so are the line breaks and the indent of
a nested item. Inside a fenced block nothing is a marker: a line `- not a bullet` is read as typed.

- **A range is cut to the text.** A marker is replaced by its words when the range holds its first character. A range that
  starts inside a marker (a word range that begins at the `]` of a box) says nothing for the part of it that it holds: the
  words were not asked for.
- **The value is the stored text.** The accessibility value is the note's text with every marker in it (AppKit's own answer:
  the text view does not override it, and a test holds it to the text), so that a range
  and the caret that VoiceOver reports are characters of that text. `accessibilityString(for:)` says what a range sounds
  like. This is a deviation from a text view that reads what it holds, and it is the plan's: the words differ in length from
  the characters, and only the value fixes the offsets.
- **A range with no marker in it is AppKit's own** for the attributed string (the font, the colours and the underline of a
  link that AppKit translates).

### The window

- **A sidebar row is one element.** The row's cell has the label "<title>, <time>, <preview>" and, for a pinned note,
  ", pinned": "Groceries, Oct 18, milk, eggs, coffee beans" (`NoteRowCellView.accessibilityLabel(for:now:)`, set in
  `configure`). A note with no text reads "Untitled", and a note with no preview has two parts. The row's three texts are still its children, each with its identifier (`sidebar.row.title`, `.time`,
  `.preview`), which the UI tests read. The pin is not an element. A press from VoiceOver opens the note, as a click and
  Return do (the arrow keys only move the highlight): the cell has the press, `onPress`.
- **The header of Recently Deleted is a button.** Its title is a button for VoiceOver with the label "Recently Deleted, 2
  notes" ("1 note" for one), whether it is expanded and a hint ("Shows the deleted notes", "Hides the deleted notes"), and a
  press from VoiceOver shows or hides the notes, as a click does (`HeaderTitleField`). The title stays the header's child
  with its identifier and its text as its value ("Recently Deleted (2)"), so that the UI tests find it by identifier and
  not by type. The header is a cell of its own kind in the table, so that no other header is ever made a button by being
  reused. The other headers are plain text.
- **The close button of a tab names the tab:** "Close Deploy checklist". The tab itself is a button whose label is its title
  and which is selected for the active tab (plan 2). The "+" button is "New Tab".
- **The toolbar's buttons** are "Pin" or "Unpin", "Attach File" and "New Note", with the same words as their tooltips.
- **The search field** is "Search".

## The keyboard

- **Tab visits the window in reading order:** the search field, the note list, the title and the editor, and from the editor
  back to the search field (`KeyViewLoop.connect`, set in `AppDelegate.launch`). Tab in the title goes to the text, as it
  did (spec §6.4), and Tab inside the text is a tab character: ⌃Tab is the next tab. ⌥⌘F puts the keyboard in the search
  field.
- **Every action that only a mouse could do has another way:**

  | Mouse | Keyboard or menu |
  |---|---|
  | a click on a checkbox | Format > Mark as Checked, ⇧⌘U (plan 6 task 5), and the context menu |
  | ⌘-click on a link | the context menu: Open Link |
  | a double-click on an attachment | the context menu: Open Attachment |
  | a click on a code block's label | the context menu: Code Block Language |
  | a click on a sidebar row | the arrow keys and Return, or a press from VoiceOver |
  | a click on the header of Recently Deleted | a press from VoiceOver |

### The context menu

A right click (Control-click, the menu key) in the editor shows what AppKit has for a text view, and in front of it, each only
where it applies to what is under the pointer (`EditorContextMenu`, put in by `NoteTextView.menu(for:)`):

- **On the box of a checklist item:** Mark as Checked, or Mark as Unchecked for a ticked box. It ticks or unticks that box,
  wherever the caret is, with the same edit and the same undo step as a click on it (`toggleCheckbox(at:)`).
- **On a link:** Open Link, which opens it as ⌘-click does (`openURL`).
- **On an attachment's preview or chip:** Open Attachment, which opens the stored file as a double-click does. It is
  disabled when there is no file (a missing attachment, one still being copied).
- **On a line of a code block (a fence line too, not only its label):** a Code Block Language submenu with the items of the
  label's menu (the 17 languages with the current one ticked, Plain Text and Not Code), which do what they do there
  (docs/features/code.md, "The language label menu").

A note that cannot be edited (Recently Deleted) offers only Open Link and Open Attachment: the others would change it. The
items are the text view's own and are always enabled as they were made: `NoteTextView.validateMenuItem` answers for them,
because how a text view validates an action it does not know is not documented.

## Increase Contrast

Every colour of the asset catalog has a high contrast variant, light and dark (`"appearances": [{"appearance": "contrast",
"value": "high"}]`, and with `luminosity: dark` for the dark one). AppKit picks it by itself when Increase Contrast is on in
System Settings: the app asks `NSColor(named:)` and nothing else (`CatalogColour.named(_:fallback:)`).

An app cannot ask for it, and that is why a launch has its own way to show the variants. The appearances that stand for
Increase Contrast cannot be made: `NSAppearance(named:)` answers nil for "NSAppearanceNameAccessibilityHighContrastAqua", and
the SDK's constants `NSAppearance.Name.accessibilityHighContrastAqua` and `…DarkAqua` are plain Aqua and Dark Aqua when they
are made (their raw values are "NSAppearanceNameAccessibilityAqua" and "…DarkAqua"). So `NSColor(named:)` never answers with
its high contrast variant in a test or under a forced appearance. `-ScratchAppearance light-contrast` and `dark-contrast`
force light and dark, and `CatalogColour.isHighContrastForced`, which makes `CatalogColour.named` answer with the colours of
`CatalogColour.highContrast`: a table that a test holds to the catalog's `Contents.json`, colour for colour. The same flag
(and the system setting) puts an outline on the raised tab.

- **The code colours** (`CodeKeyword`, `CodeString`, `CodeComment`, `CodeNumber`, `CodeType`, `CodeFunction`,
  `CodeAttribute`, `CodePreprocessor`, and `CodeText` of inline code) are darker in light mode and lighter in dark mode, so
  that each reads at 7:1 or more against the editor's background (white, and the dark background), and in dark mode at 5:1 or
  more against the stronger tint. They are the usual hues, moved along their lightness (the numbers are in `Contents.json`).
- **The tint** of a block and of a pill (`CodeBackground`) is black 10% in place of 6% in light mode and white 14% in place of
  10% in dark mode.
- **The border** of a block (`CodeBorder`) is 35% black or 45% white, in place of 8% and 12%.
- **The raised tab** also has a 1 pt outline, because a white pill and a shadow do not set it apart from the glass for
  everyone (`TabItemView.updateLayer`).
- **Reduce Transparency** is the system's. Only system materials are translucent in the app (the sidebar, the toolbar's
  buttons and the tab strip are Liquid Glass), and they follow the setting by themselves. There is no code for it and no test.

`-ScratchAppearance` takes `light-contrast` and `dark-contrast` besides `light` and `dark` (`AppearanceOverride`,
`force(on:)`), so that a screenshot shows the variants without the setting being changed on the machine, and the system's own
chrome (the glass of the toolbar and the sidebar) is the usual one: `typical-contrast-light` and `code-contrast-dark`
(docs/images are not made of them).

## Where it lives

- `App/Sources/Editor/SpokenText.swift`: the words of a range. `NoteTextView.swift`: `accessibilityString(for:)`,
  `accessibilityAttributedString(for:)`, `menu(for:)`, `validateMenuItem`, `toggleCheckbox(at:)`,
  `codeBlock(atViewPoint:)`.
- `App/Sources/Editor/EditorContextMenu.swift`: the context menu's items.
- `App/Sources/Sidebar/SidebarRowViews.swift`: the row's label (`accessibilityLabel(for:now:)`), its press, and the header's
  button (`HeaderTitleField`). `SidebarViewController.swift`: the header's own cell kind and the presses.
- `App/Sources/Tabs/TabStripViewController.swift`: the close buttons' labels and the high contrast outline of the raised tab.
- `App/Sources/Window/KeyViewLoop.swift`: the order of Tab. `App/Sources/Support/DebugStateElement.swift`: `firstResponder`
  (`editor`, `title`, `search`, `sidebar` or `other`), for the tests.
- `App/Resources/Assets.xcassets/*.colorset`: the colours and their variants. `App/Sources/Support/CatalogColour.swift`: the
  catalog's colours as the code asks for them, and the forced high contrast table.
  `App/Sources/Support/AppearanceOverride+AppKit.swift` and ScratchCore's `AppearanceOverride`: the launch appearances.

## Tests

- `SpokenTextTests` (hosted): a checklist, bullets and nested items, bold and inline code with the caret away and in them,
  a range cut to its words, tokens (an image, a file and a token with no row), a block with its label and one with none, a
  block's lines as typed, the value being the stored text.
- `SidebarRowViewsTests` (hosted): a row's label (title, time, preview, pinned, "Untitled", no preview), a press on a row,
  the Recently Deleted header as a button with its count and state and its press, and an ordinary header as plain text.
- `ContextMenuTests` (hosted): the box (open and ticked, and the caret staying), a link (choosing it opens its URL), an
  attachment (choosing it opens the stored file), a code block (the submenu's items, choosing Python renames the fence), a
  note that cannot be edited, and the menu of a right click with the items first.
- `AppearanceTests` (hosted): the catalog's `Contents.json` files give every colour a high contrast variant that differs from
  the usual one, the text colours' contrast ratios on the background and the tint, the border and the tint being stronger,
  the forced table being the catalog's high contrast colour for colour, forced colours resolving by appearance and the
  catalog being asked as before without a forced launch, and the launch appearances.
- `AccessibilityUITests`: the toolbar's labels, the editor, the title and the search field, a sidebar row read as one
  element and still holding its texts, the Recently Deleted header as a button, the close button's label, and Tab from the
  search field through the note list and the title to the editor (`debug.state`'s `firstResponder`).
- ScratchCore's `LaunchOptionsTests.parsesContrastAppearances`.

## Screenshots

`typical-contrast-light` (the `typical` fixture with `-ScratchAppearance light-contrast`) and `code-contrast-dark` (the
`code` fixture with `dark-contrast`). A person (or an agent that opens the PNG) checks: stronger tints and borders than in
`typical-light` and `code-dark`, code in darker (light) and lighter (dark) colours that read on them, the labels of the blocks
readable, and the glass of the toolbar and the sidebar still the system's.
