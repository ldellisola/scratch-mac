# Scratch: a native macOS scratchpad (design)

- **Date:** 2026-10-19
- **Status:** Draft, awaiting owner approval
- **Layout mockup:** [`2026-10-19-scratchpad-mockup.html`](2026-10-19-scratchpad-mockup.html), variant **B** (sidebar + tabs) is the chosen one. The mockup predates some decisions. Where they disagree, this document wins. In particular, the yellow-marker highlight in the mockup is **not** a feature: the owner wants bold only.

How to read this document. Each decision is tagged:

- **[owner]** The owner decided or confirmed this. Don't change it without asking them.
- **[call]** The design author decided this so planning can proceed. It's a sensible default the owner hasn't explicitly confirmed. Change it only with a reason.
- **[builder]** Deliberately left to whoever plans and builds it.

The working name is **Scratch** [call].

---

## 1. Intent

On Windows the owner used Notepad as a throwaway scratchpad. They'd open it, type or paste, close it without saving, and find everything still there next time. They haven't found an equivalent on macOS:

- **TextEdit** wants files saved, and pasting brings in foreign fonts.
- **Apple Notes** also mangles fonts on paste, and feels clunky for this kind of work.

Scratch is that Notepad habit, rebuilt as a proper Mac app. It's a window that is always ready to type in, never asks you to save, keeps whatever you put in it, and adds just enough structure for the things that actually end up in a scratchpad: code snippets, quick notes and todo lists.

**What goes in it** [owner]. Code snippets, quick notes and todo lists. Most notes are useful for a few days in a row, never months. Usually one note is in use at a time. Several are open at once when the owner is switching contexts and moving things between them.

**Who it's for.** One person, on one Apple Silicon Mac.

**Who builds it** [owner]. The app is developed only by AI agents, now and in future. The codebase and its docs must make it easy for an agent arriving cold to add features, fix bugs and prove that its change works. See §9.

## 2. Goals

1. Launch to an editable window fast enough to feel instant, every time.
2. Never lose text, with no save step at all.
3. Pasted text always takes on the note's own font. Copied text always comes out as plain text.
4. Light structure (bullets, checkboxes, bold, auto-highlighted code) that comes from typing, not from toolbars.
5. Feel like a first-class macOS 26 app, with Liquid Glass, at high frame rates.
6. A codebase that agents can safely and verifiably change.

## 3. Non-goals

- Markdown support beyond the handful of markers in §6.4: no headings, italics, tables, block quotes or images by URL.
- Sync, accounts, iCloud, collaboration, or other devices [owner: "just this Mac"].
- Folders, tags or notebooks.
- Automatic expiry or archiving of old notes [owner: notes stay until deleted by hand].
- Exporting to files, printing or sharing sheets [call].
- A built-in global hotkey or menu bar icon [owner: launched from the Dock or a Raycast shortcut].
- A settings window [call]. Nothing in v1 needs one.
- Intel Macs and macOS versions before 26.

## 4. Anti-goals (failure even if it "works")

- **Lost text.** Any keystroke older than about a second disappears after a crash, force-quit or power cut.
- **Font contamination.** Pasted text arrives in a different font, size or colour. This is the core complaint about TextEdit and Notes.
- **Rich-text leakage.** Copied text carries the scratchpad's fonts or colours into Slack, mail or a terminal.
- **Mangled code.** Highlighting, bullet handling or any "smart" behaviour changes the characters of pasted code, such as quotes, dashes, indentation or trailing whitespace.
- **Visible lag.** Noticeable launch time, typing latency, or dropped frames while scrolling.
- **Document-editor clutter.** Formatting toolbars, save dialogs, sign-in prompts, onboarding screens.
- **Fake glass.** Hand-painted imitation translucency instead of the system's Liquid Glass materials.
- **Unverifiable changes.** A codebase where an agent can't tell whether its change broke something.

## 5. Platform constraints

- macOS 26 (Tahoe) or later, arm64 (Apple Silicon) only [owner: Apple Silicon. Tahoe is required because Liquid Glass ships in macOS 26].
- Fully native: Swift and Apple frameworks. No web views, Electron, Catalyst or cross-platform UI toolkits [owner: native].
- The app makes no network requests [call]. It's App Sandboxed without the network entitlement.
- All data is stored under the app's Application Support container, so Time Machine covers it [call].

## 6. Product behaviour

### 6.1 Window layout [owner: mockup variant B]

- There's one window [call]. It has a floating glass **sidebar** on the left and a **content area** on the right.
- The content area has:
  - a **tab strip** across the top
  - a small group of **glass toolbar buttons**: pin, attach file, new note
  - the **editor** below
- There's no other chrome. No formatting bar, no status bar.
- The sidebar can be hidden with ⌃⌘S or the sidebar button [call].
- The window remembers its size, position and sidebar width [call].
- The app follows the system light or dark appearance [call].
- Accessibility settings such as Reduce Transparency and Increase Contrast must be respected, which system materials do automatically.

### 6.2 Sidebar: the note list

- It lists every note, **newest first**, with **pinned notes in their own section at the top** [owner].
- "Newest" means **most recently edited** [call, confirmed by owner in playback]. Pinned notes are also sorted by last edit [call].
- Unpinned notes are grouped under **Today / Yesterday / Earlier** headers [call, shown in mockup, not objected to].
- Each row shows:
  - the note's title, or, if the note has no title, its **first non-empty line** in the monospaced note font (regular weight) [call, confirmed in playback]
  - a one-line preview of the following text
  - the edit time (time of day for Today and Yesterday, otherwise the date)
- Pin and unpin from the toolbar pin button, the row's context menu, or ⇧⌘P [call].
- A **search field** at the top of the sidebar filters the list live, matching titles and note text across all notes [call, confirmed in playback]. ⌘F inside a note is the standard in-note find bar [call].
- Clicking a row shows that note in the current tab. ⌘-click opens it in a new tab [call, confirmed in playback]. If the note is already open in another tab, that tab is focused instead of opening a duplicate [call].
- **Recently Deleted** is a collapsed section at the bottom of the sidebar [call, confirmed in playback]:
  - Notes in it are read-only.
  - They can be restored or deleted permanently.
  - They're purged automatically after 30 days, along with their attachments.

### 6.3 Tabs [owner: sidebar + tabs]

- Tabs are views onto notes. **Closing a tab never deletes the note** [call, confirmed in playback].
- ⌘N and ⌘T both create a new empty note and open it in a new tab [call]. ⌘W closes the tab. ⌃Tab / ⌃⇧Tab and ⌘1…⌘9 switch tabs [call].
- There is always at least one tab. Closing the last tab replaces it with a new empty note [call].
- A note that is still completely empty (no title, no text, no attachments) when its tab is closed is discarded. It never appears in the list [call]. This keeps ⌘N from littering the list.
- Tab titles follow the same rule as sidebar rows: the title, or else the first line in monospace.
- The tab strip is a glass control inside the content area, as in mockup B. Tabs are not native macOS window tabs [call]. Window tabs would give each tab its own sidebar, but the sidebar should be one shared list.

### 6.4 Editor and formatting

**One font** [call, confirmed in playback]. Every character in a note, including the title, body and code, uses one monospaced font: SF Mono, 13 pt by default [call]. Emphasis comes only from weight (bold title, bold text) and colour (code highlighting, links, dimmed ticked items). ⌘+ / ⌘− / ⌘0 change the font size for all notes, and the size is remembered [call].

**Title** [owner: "notes may have a title"]. Each note has an optional title field at the top of the editor, shown bold and slightly larger, with a dimmed "Untitled" placeholder when empty [call]. Return in the title moves the cursor to the body. The title is not part of the copied body text.

**The stored form of a note is plain text** [call]. Formatting is expressed by a few plain-text markers in that text, and the editor *renders* them. This makes copy-out, search, storage and testing simple, and means formatting can never be lost or corrupted separately from the text. The markers:

| What | Typed as | Shown as | Decision |
|---|---|---|---|
| Bullet | `- ` at line start | `•` with hanging indent | owner (dash makes a bullet) |
| Checkbox | `[ ] ` at line start, or ⇧⌘L | clickable box. Ticked = `[x] `, struck through and dimmed | owner (tickable checkboxes). ⇧⌘L matches Apple Notes [call] |
| Bold | `**text**`, or select + ⌘B | bold text, stars hidden once closed | owner (both ways, stars disappear) |
| Inline code | `` `text` `` | tinted background + code colour, backticks hidden once closed | owner (accepted in playback) |
| Code block | pasted code (auto), or a line of three backticks | tinted block with a small language label, fence lines not shown | owner (auto on paste, ``` for typed code) |
| Link | any `http(s)://…` URL | link colour, ⌘-click opens | owner (accepted). ⌘-click rather than click, so clicking to place the cursor never opens a browser [call] |

List behaviour [call, confirmed in playback]:

- Return on a bullet or checkbox line continues the list. A new checkbox is unticked.
- Return on an empty bullet or checkbox ends the list.
- Tab / ⇧Tab on a list line indents or outdents it. The indent unit is [builder].

Marker rules:

- Markers only mean something outside code. Inside inline code or code blocks every character is literal.
- Typing `**` or a backtick without closing it leaves plain text, so nothing half-formatted appears.
- How hidden markers behave under cursor movement, selection and deletion is [builder]. The bar: it should feel like editing ordinary text, and deleting a visible character must never silently delete an invisible one the user didn't intend to remove.

**Code highlighting** [owner: automatic on paste, no picking a language].

- When a paste of **two or more lines** is detected as code, it's inserted as a code block, with the detected language recorded on the opening fence (e.g. ```` ```python ````) [call]. That way it never has to be re-detected.
- Single-line pastes stay plain text [call]. Wrap them in backticks if wanted.
- Prose must stay prose: a pasted paragraph or email must **not** become a code block. When unsure, don't.
- A wrong guess is undone with ⌘Z, which reverts to plain pasted text. The language label on a block is also a small menu for changing the language or turning the block back into plain text [call].
- A code block started by typing ``` gets its language detected from its content as the user types. It can also be set from the label menu.
- Pasted code keeps every character exactly: no smart quotes, no dash substitution, no re-indenting, no trimming. Smart quotes, smart dashes and auto-correct are off everywhere in the editor [call].
- Supported languages [call]: Swift, Python, JavaScript, TypeScript, JSON, Shell (bash/zsh), SQL, YAML, HTML, CSS, C#, Go, Rust, C, C++, Java, PowerShell. Anything else falls back to an uncoloured code block (or plain text, if it doesn't look like code).
- Colours come from Xcode's default light and dark themes [call].

**Attachments** [owner: images and files can be attached to notes].

- Images and files are added by pasting, dragging in, or the toolbar paperclip.
- They sit **inline in the text** where they were inserted [call, confirmed in playback]:
  - Images show as a preview scaled to fit the editor width, capped at a sensible height.
  - Other files show as a chip with an icon, name and size.
- Double-click opens the file with its default app. Dragging out of the note gives the file itself.
- Attachments are **copied into Scratch's own storage** [call], so the original can be moved or deleted.
- In the stored plain text an attachment is a token referring to that copy. The token syntax is [builder].

### 6.5 Clipboard

**Paste in** [owner]. Pasted content always takes the note's font and colours. Any font, size, colour or style from the source is dropped. A paste is handled in this order of preference [call]:

1. File references, e.g. copied in Finder → attachments.
2. If the pasteboard has text, the text wins, even when an image is also present. Excel, Word and browsers put both text and an image of the selection on the pasteboard.
   - Text that looks like code → code block.
   - Otherwise → plain text, as is.
3. An image with no text, such as a screenshot → image attachment.

"Paste and Match Style" is the same as Paste.

**Copy out** [owner: plain text, "for now"].

- Copy and Cut put **plain text only** on the pasteboard, with the markers exactly as stored: `- `, `[ ] `, `[x] `, `**`, backticks, and code fences [call: markers kept].
- Pasting that text back into Scratch reproduces the formatting.
- If the selection includes an attachment, its file name appears in the text.
- If the selection is exactly one attachment, the file or image itself is also put on the pasteboard [call].
- "For now" means rich copy-out may come later. Keep the copy path in one place so it can be extended.

### 6.6 Saving, launching and quitting

- **No save step, ever** [owner].
- Every change, including text, title, pin, ticks, tabs, cursor position and scroll position, is persisted automatically within about one second of the change. Persistence also happens immediately when the app deactivates or quits [call]. A crash or power cut loses at most about one second of typing.
- Launching restores the previous session exactly [call, confirmed in playback]: open tabs, active tab, cursor position and scroll position in each tab, and the sidebar state.
- Closing the window quits the app, like Notepad [call, confirmed in playback]. Reopening restores everything.
- There's no onboarding. The very first launch opens a single empty note, ready to type in.
- Undo history is per note and lasts for the session. It doesn't survive quitting [call].

### 6.7 Deleting

- Notes are deleted only by the owner [owner]. Delete from the row's context menu, or with ⌘⌫ when the sidebar has focus [call].
- Deleted notes go to Recently Deleted (§6.2) [call, confirmed in playback]. Deleting a note closes any tab showing it.
- Nothing else ever removes a note. The 30-day purge only removes notes from Recently Deleted.

## 7. Performance budgets

These are measured on the reference machine: a base M1 MacBook Air [call]. Every budget must have an automated measurement (§9.4). The thresholds below are starting points [call]. The builder may tighten them, and may loosen one only by recording why in a decision record.

| Scenario | Budget |
|---|---|
| Launch, app not running, files in disk cache, to the restored note on screen and accepting keystrokes | ≤ 200 ms |
| Same, from a cold boot (first launch after login) | ≤ 500 ms |
| Keystroke to pixels, any note up to 10,000 lines | within one display frame at 120 Hz |
| Scrolling a 10,000-line note that's half code blocks | no dropped frames at 120 Hz |
| Highlight colours appearing after a 500-line code paste | ≤ 50 ms |
| Switching tabs or notes (up to 10,000 lines) | ≤ 1 frame for ≤ 1,000 lines, ≤ 50 ms otherwise |
| Idle (window open, not typing) | 0% CPU, no timers firing |

Very large pastes, such as a 50,000-line log, must never freeze the UI. Highlighting may be skipped for blocks above a size the builder chooses, as long as the text still pastes instantly.

The launch budget means:

- Do as little work as possible before the first frame.
- Load only the restored tab's note before showing the window.
- Load the note list, other tabs, search index and highlighting grammars lazily, or after the first frame.

## 8. Technical approach

### 8.1 Decided [call]

- **Language:** Swift 6, strict concurrency checking on.
- **UI framework:** AppKit, throughout. Only `NSTextView` gives the control and speed the editor needs, and one UI framework is easier for agents to reason about than a mix. The window uses:
  - `NSSplitViewController` with a sidebar item, so the sidebar is native Liquid Glass
  - `NSToolbar`, so toolbar items get glass automatically
  - `NSGlassEffectView`, the macOS 26 AppKit glass material, for the custom tab strip
- **Liquid Glass comes from system components and materials only.** No custom blur or translucency effects.
- **Storage:** the system SQLite library, with no ORM:
  - WAL journal mode, with FTS5 for search
  - one database for notes, metadata and session state
  - attachment files in a folder beside it
- **Syntax highlighting:** tree-sitter, using the grammars for the languages in §6.4. It's incremental, fast, and accurate enough to be trustworthy. Tree-sitter is the one significant third-party dependency. Every other dependency needs a decision record justifying it.
- **Code detection:** offline and deterministic, and fast enough for the paste budget (well under 20 ms for 500 lines). It must be tested against a fixture corpus that includes prose and must stay prose. The algorithm is [builder]. One suggestion: cheap signals first (shebangs, distinctive keywords, JSON shape), then break ties by tree-sitter parse-error rate across the candidate grammars.
- **Architecture:** a pure-logic core that has no AppKit, under a thin AppKit shell (§9.2).

### 8.2 Left to the builder

- TextKit 1 vs TextKit 2, chosen by measuring against the §7 budgets. A short spike is recommended before committing.
- How markers are hidden and rendered (glyph substitution, attachments, custom layout fragments, …).
- The attachment token syntax, database schema and file layout.
- The detection algorithm, within the constraints in §8.1.
- The indent unit for nested lists.
- Exact debounce intervals within the "about one second" guarantee.
- App icon, accent colour usage, and other visual polish within the native, Liquid Glass look of the mockup.

## 9. Built for AI agents [owner]

Every agent arrives without memory of previous work. The repository must tell it what the app is, where things live, how to change them, and how to prove the change works, without a human in the loop.

### 9.1 Docs agents read first

- **`AGENTS.md`** at the root is the entry point, with **`CLAUDE.md`** pointing to it. It covers:
  - a one-paragraph product summary and a link to this design
  - a module map
  - the exact commands for building, testing, benchmarking, screenshots and running a fixture
  - code conventions
  - a definition of done (below)
  - known pitfalls

  Keep it short and current. An out-of-date AGENTS.md is a bug.
- **`docs/features/*.md`**: one short behaviour spec per feature (tabs, bullets, paste handling, …). Tests reference the spec section they cover. A behaviour change updates its feature doc in the same change.
- **`docs/decisions/NNNN-title.md`**: short decision records for anything non-obvious. That includes every [call] in this document that a builder changes, every new dependency and every budget change.
- **`docs/architecture.md`**: the module boundaries, the data flow (keystroke → text → parse → render → persist), and the threading model.

### 9.2 Code structure

- **`ScratchCore`**: a Swift package with no AppKit or SwiftUI imports. It holds everything rule-based:
  - the note model
  - the marker parser (plain text to formatting spans)
  - list editing rules (what Return or Tab does on a given line)
  - paste classification and normalisation
  - copy-out
  - code detection and highlight tokens
  - storage and session state
  - search

  It builds and runs its tests with plain `swift test` on macOS **and on Linux**, so an agent in a Linux container can still verify most changes.
- **`App/`**: the AppKit shell. It holds the window, sidebar, tab strip and editor view, and maps core spans to text attributes. Keep it as thin as possible. Logic found in the shell that could live in the core is a refactoring target.
- **Dependency rule:** App depends on Core, never the other way round. Core must not import AppKit (enforced by the build or a CI check).
- **Generated project:** the Xcode project is generated from a checked-in text spec (XcodeGen or similar, [builder] picks), and the generated project isn't committed. Hand-edited `.xcodeproj` files are opaque and conflict-prone for agents.
- **Formatting:** a checked-in `swift-format` config, enforced in CI.
- **Files:** small, single-purpose files with names that say what they do.

### 9.3 One command per question

A `Makefile`, or scripts it calls, gives one obvious command for each of:

- core tests
- build the app
- UI tests
- performance benchmarks
- screenshots
- run the app against a named fixture database
- lint/format check

### 9.4 Verification agents can trust

- **Core unit tests** cover every rule in §6.4–6.5. Golden-file fixtures pair input text with expected output (spans, detected language, copy-out text).
- **UI tests** (XCUITest) cover the key flows:
  - launch restores tabs and cursor
  - rich-text paste comes in unstyled
  - copy-out is plain text
  - clicking a checkbox ticks it
  - Return continues a list
  - delete then restore from Recently Deleted
  - a pasted image becomes an attachment
- **Performance tests** cover every §7 budget, using launch metrics and signposts. CI fails when a budget is exceeded.
- **Screenshots:** a command renders the key screens in light and dark mode to PNG files, and CI publishes them as artifacts. Agents can't see the screen, so this is how they check visual changes. Comparing against reference images is recommended.
- **Fixtures:** launch arguments load a named fixture database (empty, typical, huge note, many notes, every formatting feature) and can reset state. That makes UI tests, screenshots and benchmarks reproducible.
- **CI:**
  - a fast Linux job runs core tests and lint
  - a macOS job builds the app and runs UI tests, performance tests and screenshots, and publishes a built `Scratch.app` as an artifact

### 9.5 Definition of done (goes into AGENTS.md)

A change is done when:

- core tests, UI tests and lint pass
- no performance budget regressed
- screenshots of any affected screen have been looked at
- the feature doc and AGENTS.md are updated if behaviour or commands changed
- a decision record exists for any new dependency or any changed [call]

## 10. Success looks like

- The owner uses Scratch every day in place of TextEdit and Notes for scratch work, and never thinks about saving.
- Pasting code from anywhere looks right immediately. Pasting text out of Scratch into anything looks native to that app.
- Launching from Raycast feels instant.
- Nothing has ever been lost.
- An agent can pick up a bug report, reproduce it with a fixture, fix it, and prove the fix with tests and screenshots, unaided.

## 11. Open questions for the owner

None yet. This section is filled in after the builder review.
