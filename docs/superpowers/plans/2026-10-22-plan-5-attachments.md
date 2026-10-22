# Scratch Plan 5: Attachments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scratch 0.5.0. Images and files can be pasted, dropped or attached with the toolbar paperclip.

- **In the note:** each sits on its own line, an image as a scaled preview and any other file as a chip with an icon, name and size.
- **Using one:** a double-click opens it with its default app, and dragging it out gives the file.
- **Copying:** copied text names the files, and copying exactly one attachment also copies the file itself.
- **Storage:** Scratch keeps its own copy of every file, and removes the copy only when no note, including Recently Deleted, refers to it any more.

The plan also fixes the 0.4.0 follow-ups:

- the "```swift" note titles
- `key: value` notes mistaken for YAML
- licence acknowledgements
- vendoring tree-sitter-sql
- flaky timing tests
- late first colours
- the label that overlaps code

**Architecture:**

- **Core.** An attachment is a line of plain text, `[[attachment:<id>]]`, so the stored note stays plain text like every other marker (spec §6.4).
  - `ScratchCore` gets `AttachmentToken` (the syntax) and `AttachmentStore` (a table in schema v3, plus the copied files under the data directory). Deletion is decided by reference: a file goes when no stored body names its id.
- **App.**
  - `MarkupStyler` gives a token line null glyphs and a paragraph tall enough for the preview. `MarkupLayoutManager` draws the image or chip over it, like checkboxes and code blocks.
  - `NoteTextView` handles paste and drop order, selection and deletion of a token as one unit, double-click, drag out, and copy.
  - `SessionCoordinator` imports and stores the files on the storage queue.

**Tech Stack:** as Plan 4. Images are decoded with ImageIO thumbnails (`CGImageSourceCreateThumbnailAtIndex`) off the main thread. No new dependency.

**Spec:** [`docs/superpowers/specs/2026-10-19-scratchpad-design.md`](../specs/2026-10-19-scratchpad-design.md):
- §6.4, "Attachments"
- §6.5, the paste order and copy-out rules
- §6.2, purge "along with their attachments"
- §4, lost text

Read `AGENTS.md` first. Its pitfalls on the styler, null glyphs (and that they take no line fragment of their own), hosted-test clicks, undo groups, `persistNow` and `UnsavedNotes` all apply here. Roadmap row 5: [`2026-10-19-roadmap.md`](2026-10-19-roadmap.md).

**Branch:** `plan-5-attachments`, from `main` at 0.4.0. One PR at the end, which publishes 0.5.0 (DMG and zip).

## Global Constraints

Everything in Plans 1–4 still applies (AGENTS.md section 5). In addition:

**Tokens** [calls]
- An attachment is exactly one line, `[[attachment:<lowercase UUID>]]`, with no other characters on the line.
- An inserted attachment always gets its own line. A line break is added before it when the caret isn't at a line start, and after it when it isn't at a line end.
- Several attachments are several lines.
- A token whose id has no row, or whose file is missing, draws as a "Missing attachment" chip and is never removed automatically.

**Files**
- Files are copied into `<data directory>/attachments/<id>/<original file name>` (spec §6.4), on the storage queue, never on the main thread. The original can then be moved or deleted.
- The token is inserted at once. Until the copy is done, the line draws as a chip saying "Copying…".

**Never lose an attachment** [call]
- A stored file and its row are removed only when **no stored note body** (live or in Recently Deleted) contains its token, and
  - its note was just deleted permanently or purged, or
  - the launch sweep finds it unreferenced and created more than 24 hours ago.
- So deleting a token and pressing ⌘Z in the same session always brings the attachment back.

**Selection and deletion** [call]
- The caret never stops inside a token. A selection that partly covers a token grows to cover all of it.
- Backspace right after a token (or Delete right before it) first selects the token. The next press deletes it.
- Cut, copy and typing over a selection always act on whole tokens.

**Copy and paste** (spec §6.5)
- **Copy and Cut** write plain text in which each token is replaced by its file name. When the selection is exactly one token (its line, line break excluded), they also write the file's URL and, for an image, the image itself.
- **Paste and drop**, in this order of preference:
  1. file URLs become attachments
  2. any text wins, even with an image present (Excel, Word and browsers), and goes through Plan 4's code classification
  3. an image with no text becomes an image attachment, stored as PNG
- **Excluded:** a read-only note takes nothing. Pasting or dropping into a code block inserts the file names as text instead [call: a block is literal].

**Display** [calls]
- **Images:**
  - As wide as the text, up to their own width.
  - At most 240 pt high, keeping their aspect ratio.
  - Rounded corners of 6 pt, and 6 pt of space above and below.
- **Other files:** a chip 44 pt high and up to 360 pt wide, on `CodeBackground`, holding the file's Finder icon (32 pt), its name, and its size (`ByteCountFormatter`, `.file`).
- **Selected:** a selected token draws a 2 pt `controlAccentColor` outline.

**Titles** (0.4.0 follow-up) [call]
- `Note.displayTitle` and `Note.preview` skip fence lines and attachment lines.
- A note with nothing else shows "Untitled" (Plan 2's dimmed row).

**Performance**
- No budget may `FAIL`.
- Showing a note with attachments decodes previews off the main thread, visible ones first, and never blocks `switch_*`.
- Inserting a 50 MB file returns to the run loop in under 100 ms.

**Release**
- `VERSION` becomes `0.5.0` in Task 1.

## Review Focus

These are the inputs the spec implies that are most likely to hurt the owner. Each has a test in the task named.

1. **Delete an attachment, then ⌘Z**, in the same session and after an autosave. The image comes back with its file intact. Task 2: `sweepNeverRemovesAReferencedFile`. Task 5: `testUndoAfterDeletingAnAttachmentBringsItBack`.
2. **A file that is gone, renamed or corrupt** on disk, or a token typed by hand with an unknown id. It draws a "Missing attachment" chip, never crashes, and isn't removed. Task 4: `testMissingFileDrawsMissingChip`, `testCorruptImageDrawsChip`.
3. **Excel or Word pastes, which carry text and an image**, still paste text. Task 5: `testTextAndImagePastesText`.
4. **Arrow keys, Backspace and selection around an attachment** never split a token or leave half of one. Task 5: `testBackspaceSelectsThenDeletes`, `testCaretSkipsOverToken`.
5. **Purging or permanently deleting a note** removes its files only when no other note refers to them. Task 2: `deletePermanentlyRemovesUnsharedFiles`, `sharedTokenKeepsFile`.

---

## File Map

New files are marked `+`.

```
VERSION                                                        0.5.0
Packages/ScratchCore/Sources/ScratchCore/
  Notes/Note.swift                                             titles skip fence and attachment lines
  Storage/Schema.swift                                         v3: attachments table + recomputed derived columns
  Attachments/AttachmentToken.swift  AttachmentID.swift  Attachment.swift  AttachmentStore.swift   (+)
  Storage/ScratchStorage.swift                                 `attachments`, purge and delete-permanently remove files
  Notes/NoteStore.swift                                        referencedAttachmentIDs()
  Fixtures/                                                    attachments fixture (embedded PNG bytes and a text file)
Packages/ScratchCode/
  Sources/GrammarSQL/ (+)                                      tree-sitter-sql vendored (0.4.0 follow-up)
  Sources/ScratchCode/CodeDetector.swift  DetectionFeatures.swift   key: value notes stay prose
  Tests/ScratchCodeTests/Corpus/prose/                         contact card, todo/idea/buy lines (+)
App/Sources/Editor/
  AttachmentCatalog.swift (+)  AttachmentPreviews.swift (+)  AttachmentDrawing.swift (+)  AttachmentDrag.swift (+)
  MarkupStyler.swift  MarkupLayoutManager.swift  MarkupAttributes.swift  NoteTextView.swift  EditorViewController.swift
  CodeBlockStyler.swift                                        warm-up, label tail indent (0.4.0 follow-ups)
App/Sources/Session/SessionCoordinator.swift                   import, launch sweep
App/Sources/Window/ToolbarController.swift  AppCommands.swift  MainMenu.swift   paperclip, File > Attach File… ⇧⌘A
App/Resources/Acknowledgements.rtf (+)                         licences of tree-sitter and its grammars
scripts/check-release-zip.sh                                   checks Acknowledgements.rtf
App/Tests/ScratchAppTests/ AttachmentRenderingTests AttachmentEditingTests AttachmentPasteTests AttachmentCopyTests (+)
App/Tests/ScratchUITests/ AttachmentUITests (+) ScreenshotTests
docs/features/attachments.md (+)  docs/decisions/0008-attachments.md (+)  README.md  docs/images/  AGENTS.md
docs/architecture.md
```

---

### Task 1: Titles skip fences and attachments; schema v3

**Files:**
- Create: `Attachments/AttachmentID.swift`, `Attachments/AttachmentToken.swift`
- Modify: `Notes/Note.swift`, `Storage/Schema.swift`, `VERSION` (0.5.0), `AGENTS.md` (latest plan), roadmap row 5 link
- Test: `NoteTests.swift`, `AttachmentTokenTests.swift` (+), `SchemaTests.swift`

**Interfaces:**

```swift
public struct AttachmentID: Hashable, Sendable, RawRepresentable, Codable { public let rawValue: String; public static func make() -> AttachmentID }
public enum AttachmentToken {
    public static func line(for id: AttachmentID) -> String            // "[[attachment:<id>]]"
    public static func id(inLine line: some StringProtocol) -> AttachmentID?   // the whole line, nothing else
    public static func ids(in text: String) -> [AttachmentID]          // in order, duplicates kept
    public static func lineRanges(in text: NSString, within range: NSRange) -> [(NSRange, AttachmentID)]   // UTF-16, line break excluded
}
public enum Schema { public static let currentVersion = 3 }
```

**Behaviour:**
- **Titles.** `Note.displayTitle` and `preview` skip lines for which `FenceScanner.isFenceLine` or `AttachmentToken.id(inLine:)` matches.
- **Migration v3:**
  - Creates the `attachments` table:

    ```sql
    CREATE TABLE attachments (id TEXT PRIMARY KEY, note_id TEXT NOT NULL, file_name TEXT NOT NULL,
      type_identifier TEXT NOT NULL, byte_size INTEGER NOT NULL, pixel_width INTEGER, pixel_height INTEGER,
      created_at REAL NOT NULL, copied INTEGER NOT NULL)
    ```

  - Adds an index on `note_id`.
  - Recomputes `display_title`, `has_title` and `preview` for every row from `title` and `body` with the new rules, in Swift, inside the migration's transaction. It never touches `modified_at`.

- [ ] **Step 1: Write the failing tests.**
  - `titleSkipsFenceLines`: the body ```` "```swift\nlet a = 1\n```" ```` gives the title `let a = 1`.
  - `titleSkipsAttachmentLines`
  - `imageOnlyNoteHasEmptyTitle`
  - `previewSkipsFenceAndAttachmentLines`
  - `tokenRoundTrips`
  - `tokenMustBeTheWholeLine`: `" [[attachment:…]]"` is not a token.
  - `uppercaseIDIsNotAToken`
  - `idsInText`
  - `migratingV2RecomputesTitles`: a v2 file holding a note whose first line is a fence. After the migration, the `display_title` is the code line, `modified_at` is unchanged, and the version is 3.
  - `freshDatabaseIsVersion3`

- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`. Expected: compile failure.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Verify.** Run: `make core-test && make lint`, push, and wait for CI. Expected: green. The sidebar in the `code` screenshot shows "Snippets, one block…" as before.

- [ ] **Step 5: Commit.** `git commit -m "Titles skip fence and attachment lines; schema v3"`

---

### Task 2: AttachmentStore and reference-based removal

This covers Review Focus 1 and 5.

**Files:**
- Create: `Attachments/Attachment.swift`, `Attachments/AttachmentStore.swift`
- Modify: `Storage/ScratchStorage.swift`, `Notes/NoteStore.swift`, `Fixtures/Fixture.swift`, `Fixtures/FixtureContent.swift`, `LaunchOptionsTests.parsesEveryFixtureName`, `AGENTS.md` (fixtures, launch argument table)
- Test: `AttachmentStoreTests.swift` (+), `ScratchStorageTests.swift`, `FixtureTests.swift`

**Interfaces:**

```swift
public struct Attachment: Equatable, Sendable {
    public let id: AttachmentID; public let noteID: NoteID; public let fileName: String
    public let typeIdentifier: String; public let byteSize: Int64; public let pixelWidth: Int?; public let pixelHeight: Int?
    public let createdAt: Date; public let isCopied: Bool
    public var isImage: Bool { get }   // typeIdentifier is public.png / public.jpeg / public.heic / public.tiff / com.compuserve.gif / public.image
}
public final class AttachmentStore: Sendable {
    public init(database: Database, directory: URL)                    // directory = <data dir>/attachments
    /// Writes the row with isCopied = false and returns it. Fast: no file work.
    public func register(id: AttachmentID, noteID: NoteID, fileName: String, typeIdentifier: String,
                         byteSize: Int64, pixelSize: (width: Int, height: Int)?, now: Date) throws -> Attachment
    /// Copies the file (or writes the data) into place, then sets isCopied = true. Call on the storage queue.
    public func copyIn(_ id: AttachmentID, from source: URL) throws
    public func writeIn(_ id: AttachmentID, data: Data) throws
    public func attachment(_ id: AttachmentID) throws -> Attachment?
    public func attachments(_ ids: [AttachmentID]) throws -> [AttachmentID: Attachment]
    public func fileURL(for attachment: Attachment) -> URL               // directory/<id>/<fileName>
    /// Removes rows and files of `candidates` that no stored body references.
    public func removeUnreferenced(_ candidates: [AttachmentID], notes: NoteStore) throws -> Int
    /// The launch sweep: every attachment created before `cutoff` that no stored body references.
    public func sweep(createdBefore cutoff: Date, notes: NoteStore) throws -> Int
}
extension NoteStore { public func referencedAttachmentIDs() throws -> Set<AttachmentID> }  // scans every body, live and deleted
// ScratchStorage: public let attachments: AttachmentStore
// ScratchStorage.deletePermanently(_:) and purge(deletedBefore:) wrap NoteStore's and then removeUnreferenced(the ids those bodies held)
public enum Fixture { …; case attachments }   // "Screenshots": a line of text, a PNG (embedded bytes, 64×40), a line of text, a text file "rollback-plan.txt"
```

**Behaviour:**
- A file name is sanitised for the file system: `/` and `:` become `-`, it's trimmed, and an empty name becomes `file`. The row keeps the original name for display.
- A copy writes to a temporary name in the same directory and renames it into place, so no half-written file is ever named.
- The coordinator calls the `ScratchStorage` purge and permanent delete, and the storage queue never calls `NoteStore.purge` directly any more. Update `SessionCoordinator`'s two call sites.

- [ ] **Step 1: Write the failing tests:**
  - `registerThenCopyIn`
  - `writeInData`
  - `fileNameIsSanitised`
  - `copyIsAtomic`: a copy that fails mid-way leaves no file named like the target.
  - `deletePermanentlyRemovesUnsharedFiles`
  - `sharedTokenKeepsFile`: two notes reference one id, one is purged, and the file stays.
  - `sweepNeverRemovesAReferencedFile`: a deleted note in Recently Deleted references it.
  - `sweepRemovesOldUnreferenced`
  - `sweepKeepsRecentUnreferenced`: created 1 h ago.
  - `attachmentsFixtureWritesFiles`: two rows with `isCopied`, and the files exist with the right bytes.

- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`. Expected: compile failure.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Verify.** Run: `make core-test && make lint`, push, and wait. Expected: green.

- [ ] **Step 5: Commit.** `git commit -m "Store attachments and remove them only when nothing refers to them"`

---

### Task 3: 0.4.0 follow-ups in ScratchCode

**Files:**
- Modify: `Packages/ScratchCode/Package.swift`, add `Sources/GrammarSQL/` (vendored, with its LICENSE and a README saying why), `CodeDetector.swift`, `DetectionFeatures.swift`, the corpus (`prose/contact-card.txt`, `prose/todo-idea-buy.txt`, plus two more `key: value` personal notes, all written fresh), the timing tests, `docs/decisions/0007-tree-sitter.md` (the SQL pin and the 240/270 ms figure), README (the cap includes "or 300,000 characters")

**Behaviour:**
- **The `key: value` shape.** A note of short lowercase `key: value` lines whose values are words, numbers, phone numbers, emails or comma lists is prose. YAML needs a structural cue:
  - nesting by indentation under a key that has no value
  - a `- ` list under a key
  - a `---` document start
  - a value that is YAML syntax: `|`, `>`, an anchor `&x`, a quoted string with `:`, or `true`/`false`/`null` together with nesting
- **Timing tests.** Debug-build timing tests assert a bound 4× the Release budget on macOS, and keep the current bounds on Linux. The real budget is checked by `paste_code_ms` in Release.

- [ ] **Step 1: Write the failing tests.** Add the four prose samples; each fails as YAML today. Add `sqlBuildsFromVendoredSources`, which shows that `Package.swift` has no `revision:` pin.

- [ ] **Step 2: Run them to verify they fail.** Run: `swift test --package-path Packages/ScratchCode`. Expected: the prose samples fail.

- [ ] **Step 3: Implement.** Never delete or weaken an existing sample.

- [ ] **Step 4: Verify.** Run: `make core-test && make lint`, push, and wait. Expected: green.

- [ ] **Step 5: Commit.** `git commit -m "Keep key: value notes as prose; vendor the SQL grammar"`

---

### Task 4: Attachments render

This covers Review Focus 2.

**Files:**
- Create: `App/Sources/Editor/AttachmentCatalog.swift`, `AttachmentPreviews.swift`, `AttachmentDrawing.swift`
- Modify: `MarkupStyler.swift`, `MarkupLayoutManager.swift`, `MarkupAttributes.swift`, `EditorViewController.swift`, `AppDelegate.swift` (wire the catalog)
- Test: `App/Tests/ScratchAppTests/AttachmentRenderingTests.swift` (+)
- Create: `docs/features/attachments.md` (display)

**Interfaces:**

```swift
@MainActor final class AttachmentCatalog {          // metadata by id for the shown note, read from AttachmentStore on demand
    init(store: AttachmentStore)
    func attachment(_ id: AttachmentID) -> Attachment?   // cached; nil = unknown id
    func fileURL(_ id: AttachmentID) -> URL?
    func markCopying(_ id: AttachmentID) / markCopied(_ id: AttachmentID)
    var onChange: ((AttachmentID) -> Void)?             // styler restyles that line
}
final class AttachmentPreviews: @unchecked Sendable {   // thumbnails on a background queue, an NSCache by id and pixel size
    func image(for url: URL, id: AttachmentID, maxPixelSize: Int, completion: @escaping @MainActor (NSImage?) -> Void) -> NSImage?
}
final class AttachmentMark: NSObject {                  // nonisolated, set by the styler on a token line's characters (.scratchAttachment)
    let id: AttachmentID; let kind: Kind; let displaySize: NSSize; let fileName: String; let byteSize: Int64?
    enum Kind { case image, file, copying, missing }
}
extension MarkerRole { case attachment }
// MarkupStyler: var catalog: AttachmentCatalog?   (set by EditorViewController)
```

**Behaviour:**
- **Styling a token line.** Every character but the first gets the role `attachment`, which means null glyphs. The first keeps a clear glyph, so the line gets its own fragment (AGENTS.md pitfall). The paragraph style's minimum and maximum line height are the display height + 12. The line carries an `AttachmentMark`.
- **Display size.** An image's display size comes from the row's pixel size, scaled into the text width (minus the insets) and 240 pt. A file is 44 pt high.
- **Drawing.** `MarkupLayoutManager.drawBackground` draws, in the line's fragment rect:
  - the preview, with rounded corners
  - or the chip (icon, name, size)
  - "Copying…" while the copy runs
  - or "Missing attachment" for an unknown id, a missing file or an undecodable image
  - and the selection outline when the token's range is selected
- **Previews** load off the main thread. When one is ready, only that line is invalidated for display, which never changes the layout.
- **Width changes.** A change of the text width restyles the token lines, because their heights depend on it.

- [ ] **Step 1: Write the failing hosted tests**, on the `attachments` fixture and small texts:
  - `testTokenLineHasNullGlyphsAndPreviewHeight`
  - `testImageIsScaledToWidthAndCap`
  - `testFileChipHeightAndName`
  - `testMissingFileDrawsMissingChip`: delete the file first.
  - `testUnknownIDDrawsMissingChip`
  - `testCorruptImageDrawsChip`: write garbage bytes as `.png`.
  - `testPreviewPixelsAreDrawn`: `cacheDisplay`, and the fragment rect isn't the background colour.
  - `testTextIsUnchanged`
  - `testWidthChangeRestylesTokenLines`

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Verify.** Push, then wait. Green, and `switch_*` / `keystroke_ms` have no `FAIL`.

- [ ] **Step 5: Docs and commit.** `git commit -m "Draw images and file chips for attachment lines"`

---

### Task 5: Paste, drop, the paperclip; selecting and deleting tokens

This covers Review Focus 1, 3 and 4.

**Files:**
- Modify: `NoteTextView.swift` (`readablePasteboardTypes`, `readSelection(from:)`, `registerForDraggedTypes`, `deleteBackward`, `deleteForward`), `EditorViewController.swift` (`textView(_:willChangeSelectionFromCharacterRange:toCharacterRange:)` snaps to tokens), `SessionCoordinator.swift` (`importAttachments`, the launch sweep after the purge), `ToolbarController.swift` (paperclip `toolbar.attach`, SF Symbol `paperclip`), `AppCommands.swift` and `MainMenu.swift` (File > Attach File… ⇧⌘A), `AccessibilityID.swift`
- Test: `App/Tests/ScratchAppTests/AttachmentEditingTests.swift`, `AttachmentPasteTests.swift` (+), `App/Tests/ScratchUITests/AttachmentUITests.swift` (+)

**Interfaces:**

```swift
enum AttachmentSource { case file(URL), image(Data, typeIdentifier: String) }
@MainActor protocol AttachmentImporting: AnyObject {
    /// Registers each source (row written, isCopied false), starts the copies on the storage queue, returns the ids in order.
    func importAttachments(_ sources: [AttachmentSource], into noteID: NoteID) -> [AttachmentID]
}
// NoteTextView: weak var attachmentImporter: AttachmentImporting?; var presentOpenPanel: (@escaping ([URL]) -> Void) -> Void   // replaced in tests
// SessionCoordinator: AttachmentImporting; sweep at launch: storage.attachments.sweep(createdBefore: now - 24 h)
```

**Behaviour:**
- **Paste and drop.** `readSelection(from:)` follows the order in Global Constraints.
  - For files and images: get ids, then `apply` one `TextEdit` that inserts the token lines with the line-break rules. That's one undo step.
  - An image's pixel size and type come from `CGImageSource` on the main thread, which reads only the header. A file's size comes from `FileManager` attributes.
- **The paperclip** and ⇧⌘A open an `NSOpenPanel` allowing several files, then insert at the caret.
- **Selection snapping.** A caret inside a token moves to the token's edge in the direction of movement, to the end for a click. A range that partly covers a token grows to cover it.
- **Backspace and Delete.** `deleteBackward` with an empty selection right after a token, at the start of the line after it or at the token line's end, selects the token instead of deleting. With a token selected, it deletes the token and its line break (super). `deleteForward` mirrors it.
- **Excluded targets.** A read-only note ignores all of it. In a code block, files paste as their names.

- [ ] **Step 1: Write the failing tests.**

  Hosted (`AttachmentPasteTests`), with a private pasteboard:
  - `testFileURLPastesAsAttachmentLine`
  - `testImageOnlyPastesAsPNGAttachment`
  - `testTextAndImagePastesText`
  - `testPasteMidLineGetsOwnLine`
  - `testPasteIntoCodeBlockPastesNames`
  - `testReadOnlyIgnoresFiles`
  - `testTwoFilesTwoLines`
  - `testFiftyMegabyteFileReturnsQuickly`: a sparse 50 MB temp file, and `readSelection` returns in under 100 ms.
  - `testOneUndoStepRemovesInsertedTokens`

  Hosted (`AttachmentEditingTests`):
  - `testCaretSkipsOverToken`
  - `testPartialSelectionGrowsToWholeToken`
  - `testBackspaceSelectsThenDeletes`
  - `testDeleteForwardSelectsThenDeletes`
  - `testTypingOverSelectedTokenReplacesWholeToken`
  - `testPaperclipInsertsChosenFiles`: replace `presentOpenPanel`.

  UI (`AttachmentUITests`, fixture `empty`). Put an `NSURL` of a temp PNG on `NSPasteboard.general`, then press ⌘V:
  - `testPastedImageShowsAndSurvivesRelaunch`: the editor value holds one token. After ⌘Q and a relaunch it's still there, and `debug.state`'s new `attachments` value lists it as copied.
  - `testUndoAfterDeletingAnAttachmentBringsItBack`: press Backspace twice, wait 1.5 s for the autosave, then ⌘Z. The token is back and the file exists.

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement.** Add `attachments` (ids with `isCopied`) to `DebugStateElement`.

- [ ] **Step 4: Verify.** Push, then wait. Green.

- [ ] **Step 5: Docs and commit.** `git commit -m "Paste, drop and attach files; keep tokens whole"`

---

### Task 6: Open, drag out, copy

**Files:**
- Create: `App/Sources/Editor/AttachmentDrag.swift`
- Modify: `NoteTextView.swift` (`mouseDown` on a token: a single click selects it, a double-click opens it, a drag starts an `NSDraggingSession`; `writeSelection(to:types:)`)
- Test: `App/Tests/ScratchAppTests/AttachmentCopyTests.swift` (+)

**Interfaces:**

```swift
enum AttachmentDrag { static func pasteboardWriter(for url: URL) -> NSPasteboardWriting }   // the stored file's URL (NSURL)
// NoteTextView: func attachmentHit(atViewPoint: NSPoint) -> (NSRange, AttachmentID)?   (the drawn rect, like labelHit)
```

**Behaviour:**
- **Clicks on a token's drawn rect** never reach `super.mouseDown` (AGENTS.md pitfall).
  - A single click selects the token.
  - A double-click (`clickCount == 2`) calls `openURL` with the stored file, through Plan 3's seam.
  - A `mouseDragged` past 3 pt starts `beginDraggingSession` with `AttachmentDrag.pasteboardWriter`, and the drag image is the preview or chip.
- **A missing attachment** opens nothing and beeps.
- **`writeSelection`:**
  - The plain text has each token line replaced by the file name ("Missing attachment" for an unknown id).
  - When the selection is exactly one token, it also writes the file URL and, for an image, the image as PNG and TIFF.
- **Cut** follows the same rules.

- [ ] **Step 1: Write the failing hosted tests:**
  - `testCopyOfTextAndAttachmentNamesTheFile`
  - `testCopyOfOneAttachmentWritesFileURLAndImage`
  - `testCopyOfOneFileWritesFileURLOnly`
  - `testDoubleClickOpensStoredFile`: replace `openURL`, send `clickCount: 2` only after `attachmentHit` says yes.
  - `testDragWriterIsTheStoredFile`
  - `testPastingCopiedAttachmentMakesANewOne`: copy one attachment, paste it into another note. It's a new id, a new copy, and the same bytes.

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Verify.** Push, then wait. Green.

- [ ] **Step 5: Commit.** `git commit -m "Open, drag out and copy attachments"`

---

### Task 7: 0.4.0 follow-ups in the app

**Files:**
- Create: `App/Resources/Acknowledgements.rtf`, from the LICENSE of tree-sitter, swift-tree-sitter and every grammar (vendored and fetched), each under a heading. Generate it with a script, `scripts/make-acknowledgements.py`, so a new grammar adds itself, and check it in.
- Modify: `AppDelegate.swift` (About panel credits from the RTF), `scripts/check-release-zip.sh` (it must contain `Contents/Resources/Acknowledgements.rtf`) and its test, `CodeBlockStyler.swift` (warm-up), `MarkupAppearance.swift` and `MarkupStyler.swift` (the label's tail indent)
- Test: `App/Tests/ScratchAppTests/CodeBlockStylerTests.swift`, `LargeInsertTests.swift`, `scripts/tests/…`

**Behaviour:**
- **About panel.** `NSApp.orderFrontStandardAboutPanel(options: [.credits: <the RTF>])` shows the licences.
- **Query warm-up.** One main-queue turn after the first frame, `CodeBlockStyler` compiles, on its queue, the queries of the languages of the blocks in open tabs. It's the same `Highlighter` cache, so a later request finds them compiled.
- **The label.** The first line of code of a block with a label gets a tail indent of the label's width + 12 pt, so long code wraps before the label and a click on the code never opens the menu.
- **Large code paste.** A 50,000-line JSON paste is wrapped and returns from each step within the `LargeInsertTests` budget.

- [ ] **Step 1: Write the failing tests:**
  - `testAboutCreditsListTreeSitter`: the RTF string contains "tree-sitter" and "MIT".
  - the release-zip check test fails without the RTF
  - `testFirstLineOfCodeWrapsBeforeLabel`
  - `testWarmUpCompilesOpenLanguages`
  - `testFiftyThousandLineJSONPasteIsWrappedQuickly`

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Verify.** Push, then wait. Green.

- [ ] **Step 5: Commit.** `git commit -m "Acknowledgements, query warm-up, and a label that never covers code"`

---

### Task 8: Screenshots, performance, README, release 0.5.0 (Steps 1–3; the merge comes after review)

**Files:**
- Modify: `ScreenshotTests.swift` and the Makefile's `SCREENSHOT_NAMES` (add `attachments-light` and `attachments-dark` on the `attachments` fixture), `README.md` and `docs/images/` (add `attachments.png`, refresh the window images if they changed), `docs/features/attachments.md`, `docs/decisions/0008-attachments.md` (token syntax, reference-based removal, own-line layout, copy rules), `docs/architecture.md`, `AGENTS.md`, roadmap row 5 done

- [ ] **Step 1: Screenshots.** Push, then wait, and open every PNG.

  Expected in `attachments-light` and `-dark`:
  - the image preview with rounded corners, scaled
  - the file chip with an icon, "rollback-plan.txt" and its size
  - no token text visible
  - the sidebar title "Screenshots" and the preview line without a token

  Fix any mismatch here.

- [ ] **Step 2: Performance.** Expected: no `FAIL`.

- [ ] **Step 3: README.** Update the features (attachments released), the release table, the shortcuts (⇧⌘A, double-click, drag out), and the images.

- [ ] **Step 4 (after the whole-branch review): PR and merge.** Open the PR `plan-5-attachments` → `main`, titled "Scratch 0.5.0: attachments". Merge once CI is green, then check that `v0.5.0` is released with the DMG and the zip.
