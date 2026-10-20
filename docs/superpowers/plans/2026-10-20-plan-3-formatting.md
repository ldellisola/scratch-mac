# Scratch Plan 3: Formatting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scratch 0.3.0, in which the plain-text markers a note already holds render as formatting:

- `- ` becomes a bullet with a hanging indent.
- `[ ] ` and `[x] ` become clickable checkboxes, with ticked items struck through and dimmed.
- `**bold**` and `` `inline code` `` hide their markers, except next to the caret.
- `http(s)://` links are coloured and open with ⌘-click.

Return, Tab and ⇧Tab continue, indent and outdent lists, ⌘B toggles bold, and ⇧⌘L toggles a checklist. The stored text, and therefore copy and paste, stays exactly the characters typed.

**Architecture:**

- **Core.** Every rule is pure and tested on Linux in `ScratchCore/Markup`:
  - `MarkupParser`: one line of text to spans with UTF-16 `NSRange`s.
  - `FenceScanner`: the fenced code blocks, inside which nothing is formatting.
  - `ListEditing` and `InlineEditing`: what Return, Tab, ⇧Tab, ⇧⌘L, ⌘B and a checkbox click change, as a `TextEdit`.
- **App.** The shell renders and applies those results:
  - `MarkupStyler` is an `NSTextStorageDelegate`. It restyles only the paragraphs an edit touched, and styles a newly shown note visible part first.
  - `MarkupLayoutManager` is an `NSLayoutManager` subclass that is also its own delegate. It gives marker characters null glyphs (docs/decisions/0001) and draws bullets and checkboxes over their transparent marker characters.
  - `NoteTextView` routes keys, clicks and the Format menu to the core rules.

**Tech Stack:** as Plan 2: Swift 6.3.3, AppKit with TextKit 1 only (docs/decisions/0001), Swift Testing in core, XCTest/XCUITest in the app, CI on GitHub's Macs with the `ci-results` branch.

**Spec:** [`docs/superpowers/specs/2026-10-19-scratchpad-design.md`](../specs/2026-10-19-scratchpad-design.md) §6.4 (the marker table, list behaviour, marker rules) and §6.5 (copy-out keeps the markers). Read `AGENTS.md` first. Roadmap row 3: [`2026-10-19-roadmap.md`](2026-10-19-roadmap.md). Code blocks with a coloured background, a language label and hidden fences are **Plan 4**. In this plan fences only make their contents literal.

**Branch:** `plan-3-formatting`, from `main` after 0.2.1. When every task is green and approved, open one PR to `main` and merge it. The merge publishes 0.3.0 (zip and dmg).

## Global Constraints

Everything in Plans 1 and 2 still applies (AGENTS.md section 5). In addition:

**Text and markers**
- **Formatting never changes the stored characters.** Styling only sets attributes and glyphs. The only edits are explicit actions the owner takes: Return, Tab or ⇧Tab on a list line, ⌘B, ⇧⌘L, or a checkbox click. Each is one undo step, through `shouldChangeText`/`didChangeText`.
- **Copy and Cut stay plain text with the markers as stored**, so `- `, `[ ] `, `[x] `, `**` and the backticks are kept (spec §6.5). Paste stays plain text in the note font, and what it pastes renders like typed text.
- **Markers only mean something outside code.** Inside a fenced block (a pair of lines starting with ```` ``` ````) and inside inline code, every character is literal. An unclosed `**`, backtick or fence is plain text [call: an unclosed fence is not a block, so typing ```` ``` ```` never un-renders the rest of the note].
- **Marker syntax** [call where marked; the rest is the spec]:

  | Construct | Syntax |
  |---|---|
  | Bullet | a line of spaces, then `- `. The level is the number of leading spaces ÷ 2. |
  | Checkbox | a line of spaces, then `[ ] `, `[x] ` or `[X] `. A `- [ ] ` is a bullet, not a checkbox [call]. |
  | Bold | `**` + at least one character + `**` on one line. The content contains no `**`, and neither starts nor ends with whitespace [call]. |
  | Inline code | `` ` `` + at least one character that isn't a backtick + `` ` `` on one line. It is found before bold, and bold inside it is literal. |
  | Link | `http://` or `https://` followed by non-whitespace. Trailing `.,;:!?'"` is excluded, and so is a trailing `)` that has no `(` in the URL [call]. Links inside inline code are literal. |

- **The list indent unit is two spaces** [call, spec §6.4 left it to the builder].

**Rendering** [calls]
- **Bullets** draw `•` in `controlAccentColor` over the transparent `-`. The paragraph's head indent puts wrapped lines under the item's text.
- **Checkboxes** draw the SF Symbol `square`, or `checkmark.square.fill` when ticked, in `controlAccentColor`. The symbol is drawn over the transparent `[?]`, sized to the line height. A ticked line's text after the marker is struck through and in `secondaryLabelColor`.
- **Bold** uses `monospacedSystemFont(ofSize:weight: .bold)`.
- **Inline code** is in the colour asset `CodeText` (light `#C41A16`, dark `#FC6A5D`) on the background asset `CodeBackground` (light `#000000` at 6% alpha, dark `#FFFFFF` at 10% alpha).
- **Links** are in `linkColor`, underlined.
- **Hidden markers.** `**` and the backticks get null glyphs (zero width) **except while the caret or selection touches the run**, edges included. Then they show in `tertiaryLabelColor`, so the owner sees and can delete exactly what they're next to (spec §6.4 bar).

**Performance**
- The budgets (`perf/budgets.json`) must not `FAIL`, in particular `keystroke_ms` (8) and `switch_huge_ms` (50, which was 45.6 at 0.2.0).
- Keystrokes restyle only the edited paragraphs.
- Showing a note styles the visible paragraphs ±200 lines synchronously, and the rest in chunks of 1,000 paragraphs, one chunk per main run loop turn (`RunLoopIdle`).

**Release**
- `VERSION` becomes `0.3.0` in Task 1.

## Review Focus

These are the inputs the spec implies but doesn't spell out that are most likely to hurt the owner. Each has a test in the task named.

1. **Markers inside pasted code**, such as `- ` and `**` in a shell script inside a fence, or a backtick in a SQL string. Nothing renders, and every character survives copy, paste and save. Task 1: `markersInsideCodeBlocksAreLiteral`. Task 3: `testFencedBlockIsNotStyled`.
2. **Backspace right after a bold run.** The caret touches the run, so the markers show and Backspace deletes one visible `*`. It never deletes an invisible character the owner can't see. Task 3: `testBackspaceAfterBoldDeletesOneVisibleStar`.
3. **Return in tricky list positions:**
   - in the middle of an item, which splits it
   - on an empty nested item, which outdents it
   - on an empty top-level item, which ends the list
   - inside a code block, which adds no marker
   - with the caret before the marker, which inserts a plain line above

   Task 2: the `newline…` tests.
4. **A checkbox click** toggles `[ ]`↔`[x]` without moving the caret, and ⌘Z undoes it as one step. A click a little to the right of the box places the caret normally. Task 4: `testClickingCheckboxTogglesWithoutMovingCaret` and `testUndoAfterCheckboxClick`.
5. **A 10,000-line note full of markers.** Switching and typing stay within budget, and the whole note is styled within a second of being shown. Task 3: `testHugeNoteIsFullyStyledSoon`. Task 8: perf report with no FAIL.

---

## File Map

New files are marked `+`. Everything else is modified.

```
VERSION                                                    0.3.0
Packages/ScratchCore/Sources/ScratchCore/Markup/           +
  MarkupSpan.swift  MarkupParser.swift  LinkScanner.swift  FenceScanner.swift
  TextEdit.swift  ListEditing.swift  InlineEditing.swift
Packages/ScratchCore/Sources/ScratchCore/Fixtures/         formatting fixture
Packages/ScratchCore/Tests/ScratchCoreTests/               MarkupParserTests, LinkScannerTests, FenceScannerTests,
                                                           ListEditingTests, InlineEditingTests (+)
App/Sources/Editor/
  MarkupStyler.swift (+)  MarkupLayoutManager.swift (+)  MarkupAttributes.swift (+)
  NoteTextView.swift  TextViewFactory.swift  EditorViewController.swift
App/Sources/Window/MainMenu.swift                          Format menu
App/Sources/Session/SessionCoordinator.swift               failed saves of a note being left (Task 7)
App/Resources/Assets.xcassets/CodeText.colorset  CodeBackground.colorset (+)
App/Tests/ScratchAppTests/ MarkupStylerTests (+) CheckboxTests (+) LinkTests (+) ListKeyTests (+) SaveFailureTests (+)
App/Tests/ScratchUITests/ FormattingUITests (+) ScreenshotTests
docs/features/formatting.md (+)  docs/images/ (README screenshots)  README.md  AGENTS.md  docs/architecture.md
```

---

### Task 1: Markup parser, fences and links (core)

This covers Review Focus 1.

**Files:**
- Create: `Markup/MarkupSpan.swift`, `Markup/MarkupParser.swift`, `Markup/LinkScanner.swift`, `Markup/FenceScanner.swift`
- Modify: `Fixtures/Fixture.swift`, `Fixtures/FixtureContent.swift`, `VERSION`, `AGENTS.md` (module map, fixtures, current plan link)
- Test: `MarkupParserTests.swift`, `LinkScannerTests.swift`, `FenceScannerTests.swift` (+), `FixtureTests.swift`

**Interfaces:**
- Produces:

```swift
public enum MarkupKind: Equatable, Sendable {
    case bullet(level: Int)
    case checkbox(checked: Bool, level: Int)
    case bold
    case inlineCode
    case link(URL)
}
public struct MarkupSpan: Equatable, Sendable {
    public let kind: MarkupKind
    public let range: NSRange     // bullet/checkbox: the line without its line break; bold/inlineCode: markers included; link: the URL
    public let markers: [NSRange] // bullet: the "-"; checkbox: the "[?]"; bold: both "**"; inlineCode: both "`"; link: []
    public let content: NSRange   // after the marker's space / between the markers / the URL
    public init(kind: MarkupKind, range: NSRange, markers: [NSRange], content: NSRange)
}
public enum MarkupParser {
    /// One line without its line break, whose first character is at UTF-16 offset `lineStart` of the document.
    public static func parseLine(_ line: String, at lineStart: Int) -> [MarkupSpan]   // ordered by range.location
    /// The whole text: every line outside FenceScanner's blocks.
    public static func parse(_ text: String) -> [MarkupSpan]
}
public enum LinkScanner { public static func links(in line: String, at lineStart: Int, excluding: [NSRange]) -> [MarkupSpan] }
public enum FenceScanner {
    public static func isFenceLine(_ line: String) -> Bool        // optional spaces, then at least three backticks
    public static func codeBlocks(in text: String) -> [NSRange]   // opening fence line start … closing fence line end; pairs only
}
public enum Fixture { …; case formatting }
```

- All offsets are UTF-16 (`NSRange`), so the app can use them on `NSTextStorage` directly.
- Line breaks are `\n`, `\r\n` or `\r` (AGENTS.md pitfall).
- The `formatting` fixture is one note titled "Formatting", and the session is one tab on it. Its body, line by line:

  ```
  - first bullet
    - nested bullet
  [ ] open task
  [x] done task
  Some **bold** text, `inline **code**` and https://example.com/a_(b)?q=1.
  Unclosed **star and a lone ` tick stay plain.
  ```sh
  - not a bullet
  **not bold**
  ```
  ```

- [ ] **Step 1: Write the failing tests.**

  `MarkupParserTests`. Assert the exact `MarkupSpan` values with `NSRange`s:
  - `bulletAtLineStart`: `"- a"` is a bullet at level 0, with marker {0,1} and content {2,1}.
  - `nestedBulletLevel`: `"    - a"` is level 2.
  - `dashWithoutSpaceIsNotABullet`: `"-a"`.
  - `emptyBulletIsABullet`: `"- "`.
  - `checkboxUncheckedAndChecked`: `[ ] a` and `[x] a`, and `[X] a` counts as checked.
  - `bulletBeforeCheckboxIsABullet`: `"- [ ] a"` is a bullet whose content is `[ ] a`.
  - `boldRun`: `"a **b** c"` has bold with markers {2,2} and {5,2}, and content {4,1}.
  - `boldNeedsNonSpaceEdges`: `"** a **"` gives no span.
  - `unclosedBoldIsPlain`: `"**a"`.
  - `inlineCodeBeatsBold`: `` "`**x**`" `` gives one inlineCode and no bold.
  - `twoBoldRunsOnOneLine`
  - `utf16OffsetsAfterEmoji`: in `"😀 **b**"`, the bold markers start at 3.
  - `parseUsesLineStart`: `parseLine("- a", at: 10)` has marker {10,1}.

  `FenceScannerTests`:
  - `pairOfFencesIsABlock`
  - `unclosedFenceIsNotABlock`
  - `indentedFenceCounts`
  - `fourBackticksCount`
  - `twoBlocks`
  - `crlfLines`

  `markersInsideCodeBlocksAreLiteral`: `parse` on the fixture body gives no span inside the block.

  `LinkScannerTests`:
  - `plainURL`
  - `trailingPeriodExcluded`
  - `balancedParenKept`: `https://example.com/a_(b)` is kept whole.
  - `unbalancedParenExcluded`: `(see https://x.io)` gives `https://x.io`.
  - `linkInsideInlineCodeIgnored`
  - `ftpIsNotALink`

  Fixture: `formattingFixtureHasOneNote`.

- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`. Expected: compile failure.

- [ ] **Step 3: Implement.** Scan the line once over its UTF-16 view. Find inline code first, then bold outside code, then links outside code. Keep files small. Set `VERSION` to `0.3.0`.

- [ ] **Step 4: Run them to verify they pass.** Run: `make core-test && make lint`. Push, and wait for CI (`CI_WAIT_TIMEOUT=540 scripts/ci-wait.sh <sha> linux macos`). Expected: green.

- [ ] **Step 5: Commit.** `git commit -m "Add the markup parser, fence and link scanners"`

---

### Task 2: List and inline editing rules (core)

This covers Review Focus 3.

**Files:**
- Create: `Markup/TextEdit.swift`, `Markup/ListEditing.swift`, `Markup/InlineEditing.swift`
- Test: `ListEditingTests.swift`, `InlineEditingTests.swift` (+)

**Interfaces:**
- Consumes: `MarkupParser.parseLine` (Task 1).
- Produces:

```swift
public struct TextEdit: Equatable, Sendable {
    public let range: NSRange          // document UTF-16 range to replace
    public let replacement: String
    public let selection: NSRange      // selection after the edit, document coordinates
    public init(range: NSRange, replacement: String, selection: NSRange)
}
public enum ListEditing {
    public static let indentUnit = "  "
    /// `paragraphs` is the text of the whole lines covering `selection` (line breaks included), starting at document
    /// offset `start`. Nil means "not a list action: let the text view do its default".
    public static func newline(paragraphs: String, start: Int, selection: NSRange) -> TextEdit?
    public static func indent(paragraphs: String, start: Int, selection: NSRange) -> TextEdit?
    public static func outdent(paragraphs: String, start: Int, selection: NSRange) -> TextEdit?
    public static func toggleChecklist(paragraphs: String, start: Int, selection: NSRange) -> TextEdit
    public static func toggleCheckmark(line: String, lineStart: Int, selection: NSRange) -> TextEdit?
}
public enum InlineEditing {
    public static func toggleBold(paragraphs: String, start: Int, selection: NSRange) -> TextEdit
}
```

The app passes only the covering paragraphs, never the whole note, so a keystroke never copies a 5 MB string. Callers check `MarkupStyler.isInCodeBlock` first: none of these run inside a fenced block.

**`newline`:**
- With a non-empty selection, it returns nil.
- When the caret is before the end of the marker (at the indentation or inside `- `), it returns nil.
- On an item with content, it inserts `"\n" + indentation + marker`. The marker is `- ` for a bullet, and `[ ] ` for a checkbox even when the line is ticked. Text after the caret moves to the new item.
- On an empty item (marker only):
  - at level > 0, it removes one indent unit
  - at level 0, it removes the marker, which leaves an empty line, and the list ends
- On a non-list line, it returns nil.

**`indent` / `outdent`:**
- `indent` adds two spaces at the start of every list line in the selection.
- `outdent` removes up to two leading spaces from every list line in the selection.
- Either returns nil when no line in the selection is a list line. Tab then inserts a tab and ⇧Tab does its default.
- The selection moves with the text.

**`toggleChecklist`** (⇧⌘L):
- When every non-empty line in the selection is a checkbox, it removes the `[?] ` markers.
- Otherwise, on each line that isn't a checkbox, it replaces a `- ` bullet marker with `[ ] `, or inserts `[ ] ` after the indentation.

**`toggleCheckmark`** (a click on the box): flips the `[ ]` / `[x]` at the line start, or returns nil when the line isn't a checkbox. The selection is passed through unchanged.

**`toggleBold`** (⌘B):
- When the selection is exactly a bold run's content, or a whole run with its markers, it removes the markers. The selection then covers the content.
- With a non-empty selection otherwise, it wraps the selection in `**`. The selection covers the content.
- With an empty selection, it inserts `****` and puts the caret between the pairs.

- [ ] **Step 1: Write the failing tests.** Use a helper `apply(_ edit: TextEdit, to text: String) -> (String, NSRange)`. `|` marks the caret in the strings:
  - `newlineContinuesBullet`: `"- a|"` gives `"- a\n- |"`.
  - `newlineSplitsItem`: `"- ab|cd"` gives `"- ab\n- |cd"`.
  - `newlineOnCheckedItemAddsUnchecked`: `"[x] a|"` gives `"[x] a\n[ ] |"`.
  - `newlineKeepsIndentation`
  - `newlineOnEmptyTopLevelItemEndsList`: `"- a\n- |"` gives `"- a\n|"`.
  - `newlineOnEmptyNestedItemOutdents`: `"  - |"` gives `"- |"`.
  - `newlineBeforeMarkerIsDefault`: the caret at offset 0 gives nil.
  - `newlineOnPlainLineIsDefault`
  - `newlineWithSelectionIsDefault`
  - `indentAddsTwoSpacesToEachListLine`
  - `outdentRemovesAtMostTwoSpaces`
  - `indentOnPlainLineIsDefault`
  - `toggleChecklistAddsBoxes`
  - `toggleChecklistReplacesBulletMarker`
  - `toggleChecklistRemovesWhenAllChecked`
  - `toggleCheckmarkFlips`
  - `toggleCheckmarkOnPlainLineIsNil`

  `InlineEditingTests`:
  - `wrapSelection`
  - `unwrapContentSelection`
  - `unwrapWholeRunSelection`
  - `emptySelectionInsertsPairs`
  - `unicodeSelectionOffsets`: an emoji inside the selection.

- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`. Expected: compile failure.

- [ ] **Step 3: Implement** the three files.

- [ ] **Step 4: Run them to verify they pass.** Run: `make core-test && make lint`, push, and wait for CI. Expected: green.

- [ ] **Step 5: Commit.** `git commit -m "Add list and bold editing rules"`

---

### Task 3: Styling and hidden markers (app)

This covers Review Focus 1, 2 and 5.

**Files:**
- Create: `App/Sources/Editor/MarkupStyler.swift`, `MarkupLayoutManager.swift`, `MarkupAttributes.swift`, `App/Resources/Assets.xcassets/CodeText.colorset`, `CodeBackground.colorset`
- Modify: `TextViewFactory.swift` (use `MarkupLayoutManager`, attach the styler), `NoteTextView.swift` (`load` and `applyFontSize` go through the styler), `EditorViewController.swift` (`show` calls `noteDidLoad`, and selection changes call `selectionDidChange`)
- Test: `App/Tests/ScratchAppTests/MarkupStylerTests.swift` (+)
- Create: `docs/features/formatting.md` (styling sections)

**Interfaces:**
- Consumes: `MarkupParser.parseLine`, `FenceScanner` (Task 1).
- Produces:

```swift
extension NSAttributedString.Key { static let scratchMarker: NSAttributedString.Key }   // value: MarkerRole.rawValue
enum MarkerRole: String { case hidden, revealed, bullet, checkboxOpen, checkboxChecked }
enum MarkupColors { static var codeText: NSColor; static var codeBackground: NSColor }  // from the assets
@MainActor final class MarkupStyler: NSObject, NSTextStorageDelegate {
    init(textView: NoteTextView)
    var fontSize: Double { get set }                 // restyles everything when changed
    func noteDidLoad(visibleRange: NSRange)          // style visible ±200 lines now, the rest in idle chunks
    func selectionDidChange(_ selection: NSRange)    // reveal/hide the markers of runs touching the selection
    func isInCodeBlock(_ location: Int) -> Bool
    var isFullyStyled: Bool { get }
    func checkboxMarker(at characterIndex: Int) -> NSRange?   // Task 4
    func link(at characterIndex: Int) -> URL?                 // Task 6
}
final class MarkupLayoutManager: NSLayoutManager, NSLayoutManagerDelegate   // null glyphs for .hidden; draws bullet/checkbox roles
// NoteTextView: var styler: MarkupStyler { get }  (set by TextViewFactory)
```

**Behaviour:**
- **When styling happens.** `textStorage(_:didProcessEditing:range:changeInLength:)`, for `.editedCharacters`, restyles the paragraphs of the edited range. If the edit touched a fence line or a backtick, it rescans the fences with `FenceScanner.codeBlocks` and restyles the paragraphs whose code-block membership changed. Otherwise it shifts the stored block ranges by `changeInLength`.
- **What styling sets** on each paragraph:
  - the base font at `fontSize` and `textColor`, which resets the paragraph
  - then the spans' attributes: bold font; code colours; link colour and underline; ticked strikethrough and secondary colour
  - a paragraph style with a head indent of (level × 2 + 2) × the width of a space for list lines
  - `scratchMarker` roles on the marker characters, with `foregroundColor: .clear` for `bullet` and the checkbox roles
- **Glyphs.** `MarkupLayoutManager.layoutManager(_:shouldGenerateGlyphs:…)` sets `.null` for characters with the role `hidden` (the code in docs/decisions/0001). Changing a role calls `invalidateGlyphs(forCharacterRange:changeInLength: 0, actualCharacterRange:)` and `invalidateLayout` for that range.
- **Drawing.** `drawGlyphs(forGlyphRange:at:)` calls `super`, then draws `•` in `controlAccentColor` at the `-` glyph's rect for `bullet`, and the symbol image at the 3-character rect for the checkbox roles.
- **Revealing markers.** `selectionDidChange` finds the bold and inline-code runs whose range touches the selection, edges included. Their markers get `revealed` (`tertiaryLabelColor`), and the markers of runs no longer touched go back to `hidden`.
- **Loading a note.** `noteDidLoad` styles the paragraphs of the visible range ±200 lines synchronously. The rest is styled in chunks of 1,000 paragraphs, one per main run loop turn (`RunLoopIdle`), and `isFullyStyled` becomes true at the end. A `show` of another note cancels the job.
- **Undo.** Styling never registers undo. Attribute changes made inside `didProcessEditing` aren't recorded.
- **Font size.** `applyFontSize` → `styler.fontSize`, which restyles everything (bold must survive a font size change).

- [ ] **Step 1: Write the failing hosted tests** (`MarkupStylerTests`, editor in an 800×600 window, on the `formatting` fixture's body or small strings):
  - `testBoldContentIsBoldAndMarkersAreNullGlyphs`: on `"a **b** c"` with the caret at 0, the font at 4 is bold, and `propertyForGlyph` at the glyphs of 2, 3, 5 and 6 is `.null`.
  - `testMarkersRevealedWhenCaretTouchesRun`: with the caret at 7, those glyphs aren't null and their colour is `tertiaryLabelColor`.
  - `testBackspaceAfterBoldDeletesOneVisibleStar`: caret at 7, `deleteBackward`, and the text is `"a **b* c"`.
  - `testInlineCodeColours`
  - `testLinkIsColouredAndUnderlined`
  - `testBulletParagraphHasHangingIndent`
  - `testCheckedLineIsStruckThrough`
  - `testFencedBlockIsNotStyled`: the fixture's `**not bold**` in the block stays at the regular weight, and the `- ` there has no role.
  - `testUnclosedMarkersArePlain`
  - `testTypingClosesBoldRun`: type `**x` then `**`. It becomes bold, and the markers are hidden once the caret moves away.
  - `testFontSizeChangeKeepsBold`
  - `testStylingDoesNotRegisterUndo`: after `noteDidLoad`, `undoManager.canUndo == false`.
  - `testCopyKeepsMarkers`: select all, copy to a private pasteboard. The string equals the stored text.
  - `testHugeNoteIsFullyStyledSoon`: a 10,000-line text of mixed markers. `noteDidLoad` returns in under 100 ms in the Debug build, and `isFullyStyled` is true within 1 s of run loop time.

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement** the files above.

- [ ] **Step 4: Push, then wait.** Expected: all app tests green.
  - In `perf/report.md`, `keystroke_ms` and `switch_*` don't `FAIL`. If one regressed more than 20%, profile the styler (attribute churn, full rescans) and fix it. Don't change the baseline.
  - Look at `typical-light.png`. Bullets, checkboxes and bold should render, but checkboxes are only drawn after Task 4. The transparent markers there are expected until then.

- [ ] **Step 5: Docs and commit.** Write the styling part of `docs/features/formatting.md`, and the AGENTS.md pitfalls (roles, null glyphs, chunked styling). Then `git commit -m "Render bullets, bold, inline code and links with hidden markers"`.

---

### Task 4: Checkboxes and ⇧⌘L

This covers Review Focus 4.

**Files:**
- Modify: `MarkupLayoutManager.swift` (draw checkbox symbols), `MarkupStyler.swift` (`checkboxMarker(at:)`), `NoteTextView.swift` (`mouseDown`, `toggleChecklist(_:)`), `MainMenu.swift` (Format menu)
- Test: `App/Tests/ScratchAppTests/CheckboxTests.swift` (+)

**Interfaces:**
- Consumes: `ListEditing.toggleCheckmark` and `toggleChecklist` (Task 2), and the styler (Task 3).
- Produces:

```swift
// NoteTextView
override func mouseDown(with event: NSEvent)   // a click inside a checkbox's 3-character rect toggles it; else super
@objc func toggleChecklist(_ sender: Any?)     // ⇧⌘L
func apply(_ edit: TextEdit)                    // shouldChangeText + replaceCharacters + didChangeText + setSelectedRange: one undo step
// MainMenu: a "Format" menu after Edit, with "Checklist" ⇧⌘L (action toggleChecklist:, first responder)
```

**Behaviour:**
- **Clicks.** On a click, `mouseDown` converts the point to a character index with `characterIndexForInsertion(at:)`, checked against the marker's glyph rect (`boundingRect(forGlyphRange:in:)`). When the point is inside a checkbox marker's rect, it applies `toggleCheckmark` with the current selection, so the caret doesn't move, and returns without calling `super`.
- **Read-only.** A read-only note ignores checkbox clicks.
- **Code.** In a code block nothing is a checkbox, since the styler gives no role there.
- **⇧⌘L** works like the clicks: in a code block, or when the note is read-only, it does nothing (beep).

- [ ] **Step 1: Write the failing hosted tests.** Build a real `NSEvent.mouseEvent(with: .leftMouseDown, …)` at the marker's rect centre in window coordinates, and call `mouseDown`.
  - `testClickingCheckboxTogglesWithoutMovingCaret`: `"[ ] a"` with the caret at 5, click the box. The text is `"[x] a"` and the caret is still 5.
  - `testUndoAfterCheckboxClick`: ⌘Z through `undoManager.undo()` restores `"[ ] a"`.
  - `testClickRightOfBoxIsNotAToggle`: `styler.checkboxMarker(at:)` for the index just after the marker (the space) is nil. The test doesn't send that click, because `super.mouseDown` would start AppKit's tracking loop.
  - `testReadOnlyCheckboxIgnoresClick`
  - `testToggleChecklistOnSelection`: two plain lines become `[ ] ` lines, and doing it again restores them.
  - `testCheckboxSymbolIsDrawn`: render the view into a bitmap with `cacheDisplay(in:to:)`. Pixels inside the marker rect differ from the background.

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Push, then wait.** Expected: green. `typical-light.png` shows boxes, with the ticked "run migrations on staging" struck through.

- [ ] **Step 5: Commit.** `git commit -m "Add clickable checkboxes and the checklist command"`

---

### Task 5: Return, Tab, ⇧Tab and ⌘B

This covers Review Focus 3 on the app side.

**Files:**
- Modify: `NoteTextView.swift` (`insertNewline(_:)`, `insertTab(_:)`, `insertBacktab(_:)`, `toggleBoldMarkers(_:)`), `MainMenu.swift` (Format > Bold ⌘B)
- Test: `App/Tests/ScratchAppTests/ListKeyTests.swift` (+), `App/Tests/ScratchUITests/FormattingUITests.swift` (+)

**Interfaces:**
- Consumes: `ListEditing.newline/indent/outdent`, `InlineEditing.toggleBold` (Task 2), `apply(_:)` (Task 4) and `styler.isInCodeBlock` (Task 3).
- Produces: `@objc func toggleBoldMarkers(_ sender: Any?)`, and Format > Bold with ⌘B. The name avoids AppKit's font-panel `toggleBold`.

**Behaviour:**
- Each override computes the covering paragraph range with `(string as NSString).paragraphRange(for: selectedRange())`.
- It calls the core rule unless the selection is in a code block, then `apply`s the edit, or falls back to `super` on nil.
- `insertBacktab` with nil keeps AppKit's default, which moves focus to the title field.
- ⌘B in a code block, or when read-only, beeps.

- [ ] **Step 1: Write the failing tests.**

  Hosted (`ListKeyTests`):
  - `testReturnContinuesBullet`
  - `testReturnOnEmptyItemEndsList`
  - `testReturnInsideCodeBlockIsPlain`
  - `testTabIndentsListLine`
  - `testShiftTabOutdents`
  - `testTabOnPlainLineInsertsTab`
  - `testCommandBWrapsSelection`
  - `testEachEditIsOneUndoStep`

  UI (`FormattingUITests`, fixture `empty`):
  - `testTypingAListByKeyboard`:
    1. Type `- milk`, Return, type `eggs`, Return, Return, type `done`.
    2. The value is `"- milk\n- eggs\ndone"`.
  - `testChecklistShortcutThenReturn`: type `buy`, ⇧⌘L, End, Return, type `sell`. The value is `"[ ] buy\n[ ] sell"`.
  - `testCommandBThenCopyKeepsMarkers`:
    1. Type `word`, select all, ⌘B, ⌘C.
    2. `NSPasteboard.general.string(forType: .string) == "**word**"`.
  - `testTabIndentsNestedBullet`

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Push, then wait.** Expected: green.

- [ ] **Step 5: Docs and commit.** Write the keyboard section of `formatting.md` and the shortcut list in README and AGENTS. Then `git commit -m "Continue, indent and outdent lists; toggle bold with ⌘B"`.

---

### Task 6: Links open with ⌘-click

**Files:**
- Modify: `MarkupStyler.swift` (`link(at:)`), `NoteTextView.swift` (⌘-click and the pointing-hand cursor while ⌘ is held over a link)
- Test: `App/Tests/ScratchAppTests/LinkTests.swift` (+)

**Interfaces:**
- Produces: `NoteTextView.openURL: (URL) -> Void`. It defaults to `{ NSWorkspace.shared.open($0) }`, and tests replace it.

**Behaviour:**
- `mouseDown` with `.command` in the modifier flags, over a character whose styler `link(at:)` isn't nil, calls `openURL` and returns.
- A plain click places the caret, and never opens anything.
- `flagsChanged` and `mouseMoved` set `NSCursor.pointingHand` while ⌘ is held over a link, and the I-beam otherwise. The view adds a tracking area for mouse moves.

- [ ] **Step 1: Write the failing hosted tests:**
  - `testCommandClickOpensLink`: the captured URL equals the fixture link without its trailing period.
  - `testPlainClickDoesNotOpen`: first `NSApp.postEvent` a matching `mouseUp` (`atStart: false`), so the tracking loop `super.mouseDown` starts ends at once. Then call `mouseDown` without ⌘ over the link. No URL is captured.
  - `testCommandClickOutsideLinkDoesNothing`
  - `testLinkInsideInlineCodeIsNotOpened`

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Push, then wait.** Expected: green.

- [ ] **Step 5: Commit.** `git commit -m "Open links with ⌘-click"`

---

### Task 7: Follow-ups: failed saves, emptied notes, the top inset

**Files:**
- Modify: `SessionCoordinator.swift`, `EditorViewController.swift`, `Packages/ScratchCore/Sources/ScratchCore/Storage/ScratchStorage.swift`, `docs/features/autosave-and-restore.md`, `docs/decisions/0004-new-tabs-and-emptied-notes.md` (mark both gaps fixed in 0.3.0), `docs/features/tabs.md`
- Test: `App/Tests/ScratchUITests/TabsUITests.swift`
- Test: `App/Tests/ScratchAppTests/SaveFailureTests.swift` (+), `EditorViewControllerTests.swift`

**Interfaces:**
- Produces:
  - Inside `SessionCoordinator`, `private var unsavedNotes: [NoteID: Note]` holds notes whose write failed. Every `saveNow` writes them first, then the current note, and removes each that succeeds.
  - `ScratchStorage` gets `public let database: Database`, so tests can make writes fail. Add it to AGENTS.md's module map.

**Behaviour:**
- **Failed saves.** A failed write of a note that is no longer `current` is kept in `unsavedNotes` instead of being dropped (Plan 2 final review). It's retried on every save until it succeeds.
- **Loading a note with unsaved changes.** `loadNote` prefers the `unsavedNotes` copy over the store, so switching back shows the owner's text, which the undo ranges also need.
- **Emptied notes (owner decision 2026-10-20, docs/decisions/0004 "The code does not tell every emptied note from an untouched one yet").**
  - The first edit of a note's title or text removes it from `untouchedNoteIDs` for good, even when the owner later empties it.
  - At restore, a note counts as untouched only when it is empty **and** its `modifiedAt == createdAt`, which `NoteStore.create` sets and every save of typed text changes.
  - An emptied note is therefore listed (as a dimmed "Untitled") and kept when its tab closes, and only a note nobody ever typed in is discarded.
- **The top inset (Plan 2 final review, huge-note screenshot).** Showing a note without an anchor, or with anchor 0, scrolls to `y = -contentInsets.top`. The text view's `textContainerInset` top stays visible.

- [ ] **Step 1: Write the failing hosted tests.**
  - `testFailedSaveOfLeftNoteIsRetried`:
    1. Use a coordinator on an isolated directory and type into note A.
    2. After `persistNow()`, run `PRAGMA query_only = 1` on `storage.database`, which makes every write fail with `SQLITE_READONLY`. File permissions wouldn't work, because SQLite keeps its file open. Then type more into A and switch to note B.
    3. Run `PRAGMA query_only = 0` and trigger `persistNow()`.
    4. The store has A's typed text.
  - `testSwitchingBackShowsUnsavedText`
  - `testTypedThenEmptiedNoteIsKeptWhenItsTabCloses` (UI, fixture `typical`):
    1. ⌘T, type `x`, wait 1.5 s, Backspace, wait 1.5 s.
    2. ⌘W. There are 7 sidebar title rows, one of them "Untitled".
  - `testEmptiedNoteSurvivesRelaunch` (UI, fixture `typical`):
    1. Open "Groceries", ⌘A, Backspace, wait 1.5 s.
    2. ⌘Q, relaunch. There are still 6 title rows.
    3. ⌘W on its tab. Still 6.
  - `testNoteWithoutAnchorShowsItsTopInset`: after `show` with anchor 0, the clip view origin y equals `-contentInsets.top`, and `textView.visibleRect.minY <= 0`.

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Push, then wait.** Expected: green. `huge-note-light.png` shows the same gap above line 1 as `typical-light.png`.

- [ ] **Step 5: Commit.** `git commit -m "Retry failed saves of a note that was left; keep the top inset visible"`

---

### Task 8: Screenshots, README, performance, release 0.3.0

**Files:**
- Modify: `ScreenshotTests.swift` and the Makefile's `SCREENSHOT_NAMES` (add `formatting-light` and `formatting-dark` on the `formatting` fixture), `README.md` and `docs/images/` (refresh from this branch's final screenshots, since formatting now renders), `docs/features/formatting.md`, `docs/architecture.md` (the styler in the data flow), `AGENTS.md`, `docs/superpowers/plans/2026-10-19-roadmap.md` (Plan 3 done)

- [ ] **Step 1: Screenshots.** Add the two screenshot tests, push and wait, then open every PNG.

  Expected in `formatting-light`:
  - bullets with hanging indents
  - an open box and a ticked box with struck-through text
  - bold with no visible stars away from the caret
  - inline code tinted, a link in the link colour
  - the fenced block's lines shown as typed
  - dark mode correct

  Fix any mismatch in this task.

- [ ] **Step 2: Performance.** Read `perf/report.md` for the final head. Expected: no `FAIL`. Treat a regression of more than 20% as a bug of this plan. Look in the styler first.

- [ ] **Step 3: README.** Copy `typical-light`, `typical-dark` and `formatting-light` from the final head's `ci-results` into `docs/images/`. Update the README's feature list (formatting is now released) and the shortcut table (⌘B, ⇧⌘L, ⌘-click).

- [ ] **Step 4: Whole-branch review, PR, merge.** Open the PR `plan-3-formatting` → `main`, titled "Scratch 0.3.0: formatting". Merge once CI is green, then check that `v0.3.0` is released with `Scratch-0.3.0.zip` and `Scratch-0.3.0.dmg`.
