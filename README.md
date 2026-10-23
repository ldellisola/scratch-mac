# Scratch

A native macOS scratchpad. It is a window that is always ready to type in, never asks you to save, and brings
everything back when you open it again. It is made for one person on one Apple Silicon Mac, for code snippets, quick
notes and todo lists.

<p align="center">
  <img src="docs/images/window-light.png" alt="Scratch in light mode: a sidebar of notes grouped by day, the tabs in the toolbar next to the pin, paperclip and new note buttons, and a note with a checklist, bullets, bold text, a code pill and a coloured shell snippet in a bordered block with a Shell label" width="49%">
  <img src="docs/images/window-dark.png" alt="The same window in dark mode" width="49%">
</p>

## Why

On Windows, Notepad was the place for anything you did not want to file: open it, type or paste, close it without
saving, and find it all again next time. Scratch is that habit on the Mac, with just enough structure for what ends up
there: code snippets, quick notes and todo lists. Text you paste always takes the note's font, whatever it was copied
from, and text you copy always comes out as plain text.

## What it does

Scratch is at version 1.0, which does these things:

- **Always ready.** It opens to a note you can type in at once. There is no Save and no file to name: everything you
  type is written within about a second, and a crash or a force-quit loses at most that second. Quitting and opening
  the app again restores your tabs, the active one, and the cursor and scroll position in each.
- **Pasted text takes the note's font, copied text comes out plain.** Whatever you paste from a browser, Word or a
  terminal, only its text is used. Whatever you copy goes out as plain text, with nothing of the note's font. Every
  note uses one monospaced font (SF Mono, 13 pt by default; ⌘+, ⌘− and ⌘0 change the size for all notes). Nothing
  is autocorrected, so pasted code keeps every character.
- **Notes with an optional title, and tabs.** A note can have a bold title above its text. Tabs sit in a glass strip
  in the toolbar, next to the buttons, each with its own cursor, scroll position and undo history, and a title in a tab
  or in the sidebar shows the line as the note does, without its `- `, `[ ] `, `**` or backticks.
- **A sidebar that finds things.** Notes are grouped as Pinned, Today, Yesterday and Earlier, newest edit first. Pin a
  note (the pin button or ⇧⌘P) to keep it at the top. The search field filters the notes as you type, over titles and
  text.
- **Deleting is undoable.** Delete a note from its right-click menu, or with ⌘⌫ in the sidebar. It moves to Recently
  Deleted, where you can restore it, and is removed for good after 30 days.
- **Just enough formatting, from what you type.** `- ` is a bullet, `[ ] ` and `[x] ` are checkboxes you can click
  (ticked ones are struck through), `**bold**` is bold, `` `code` `` is a small pill, and `http(s)://` links open with
  ⌘-click. Return continues a list, Tab and ⇧Tab indent it, ⌘B makes the word under the caret (or each selected line)
  bold, ⇧⌘L makes a checklist and ⇧⌘U ticks it. Open boxes are grey, ticked ones are blue and struck through, and
  lines have a little air between them. The `**` and the backticks hide, except where the caret is. Bold needs a word
  boundary on each side, so `x**2 + y**2` and `src/**/*.ts` stay plain text. What is stored never changes, so copying a note out gives the characters you typed,
  `- ` and `**` included. Inside a fenced block (three backticks), and inside inline code, every character stays
  exactly as typed.
- **Code looks like code.** A fenced block (a line of three backticks, the code, a line of three backticks) is drawn as a
  tinted, rounded block with a hairline border and a small language label at its top right, and the code is coloured in
  the colours of Xcode's default theme, light and dark, for 17 languages: Swift, Python, JavaScript, TypeScript, JSON, Shell, SQL, YAML,
  HTML, CSS, C#, Go, Rust, C, C++, Java and PowerShell. The fence lines shrink to a little padding and come back where
  the caret is. A block you type with no language on its fence gets one from its code (shown in italics, which means
  "automatic"). Colouring never changes a character, and a block too long to colour (over 5,000 lines or 300,000 characters)
  stays tinted and plain.
- **Pasted code is fenced for you.** Paste two lines or more of code and Scratch puts them in a fence with the language
  it detected, with every pasted character kept as it was. It works offline, and when it is unsure it leaves your text
  alone: an email, a list, meeting notes with times, a log, a CSV row or a note of `name: value` lines stay plain text. ⌘Z once gives back exactly the
  text you pasted, and ⌘Z again removes it. Click a block's label to choose another language, to show the block as
  plain text, or to take the fence off (Not Code), each one undo step.
- **Images and files, right in the note.** Paste an image or a file you copied in Finder, drop one on the note, or click
  the paperclip (⇧⌘A), and it sits in the note on a line of its own: an image as a preview, as wide as the text and up
  to 240 pt high, and any other file as a chip with its icon, name and size. Double-click one to open the file with its
  default app, and drag it out of the note to give the file to Finder, Mail or any app that takes files. Scratch keeps its
  own copy of every file, so the original can be moved or deleted, and removes the copy only when no note, Recently
  Deleted included, refers to it any more. Backspace next to an attachment selects it before the next press deletes it,
  and ⌘Z brings a deleted one back, file and all. Copying text with attachments in it writes the file names for other
  apps, and copying exactly one attachment copies the file (or the image) as well. Inside Scratch the attachments themselves travel: a
  selection with attachments in it, copied or dragged to another place in the note or into another note, keeps them. Typing
  next to an attachment never breaks it (the text goes on the line above or below), and a copied image can still be pasted
  after Scratch has quit. When a paste holds files, text and an image, the files
  win, then the text (Excel and Word paste text, not a picture of it), and an image comes in only when there is no text.
- **It records its own launch times.** Scratch writes down how long each of its launches took. Help > Launch Times…
  shows the newest 50 and copies them (see Checking launch speed), so the speed on your Mac is a number and not a feeling.
- **Works with VoiceOver, Increase Contrast and the keyboard.** VoiceOver reads a note as it looks ("unchecked buy milk",
  "image, dashboard.png", "code block, Swift"), every colour has a stronger variant for Increase Contrast, Reduce
  Transparency is the system's, and everything a mouse can do (tick a box, open a link or an attachment, choose a code
  block's language) is also in the editor's right-click menu or the Format menu.
- **Made for macOS 26.** The sidebar, the tab strip and the toolbar buttons are native Liquid Glass, and the app is
  built only for Apple Silicon. It has an icon: a yellow notepad with a ticked checkbox.

<p align="center">
  <img src="docs/images/formatting.png" alt="One note with a bullet and a nested bullet, an open and a ticked checkbox, bold text, inline code, a link, and a tinted block whose lines show exactly as typed" width="70%">
</p>

<p align="center">
  <img src="docs/images/code.png" alt="One note with a tinted block for each of Swift, Python, SQL, JSON and Shell, and one whose language was detected, each with its label at the top right and its code in colour" width="70%">
</p>

<p align="center">
  <img src="docs/images/attachments.png" alt="One note with a line of text, a small image drawn as a preview with rounded corners, a line of text, and a chip for the file rollback-plan.txt with its icon, name and size" width="70%">
</p>

<p align="center">
  <img src="docs/images/search.png" alt="Typing kube in the search field leaves only the notes that contain it" width="49%">
  <img src="docs/images/recently-deleted.png" alt="The Recently Deleted section open under the note list" width="49%">
</p>

## Releases

| Release | Added |
|---|---|
| 0.1 | The walking skeleton: a glass sidebar and toolbar, one plain-text editor, plain paste and copy, autosave and restore |
| 0.2 | Titles, tabs, the sidebar's groups, pinning and search, Recently Deleted, and the font size |
| 0.3 | Bullets, checkboxes, bold, inline code and links, and the keys that edit them |
| 0.4 | Highlighted code blocks in 17 languages, code detection on paste, and the language label menu |
| 0.5 | Images and files in a note: paste, drop, paperclip, open, drag out and copy |
| 1.0 | Launch times you can read (Help > Launch Times…), VoiceOver and Increase Contrast, the look of the mockup (tabs in the toolbar, air between lines, code pills and borders), an app icon, and the follow-ups of 0.5 |

The plan behind that order is in [the roadmap](docs/superpowers/plans/2026-10-19-roadmap.md).

## Checking launch speed

The design asks for a launch within 200 ms and within 500 ms right after the Mac has started. CI cannot measure a cold boot, so
Scratch measures itself: every launch is recorded (from the start of the process to the first frame on screen that takes
keystrokes), and the newest 50 are in `~/Library/Application Support/Scratch/launch-times.json`. To check it on your Mac:

1. Restart the Mac and log in.
2. Open Scratch from Raycast.
3. Choose Help > Launch Times…, press **Copy**, and send it.
4. Then quit and open Scratch five times, and send it again.

The first launch after the restart is marked "first after start-up" and is compared with 500 ms, the others with 200 ms, each as
the median of the newest ten. The text you copy has the date, the time and the milliseconds of each launch and the two medians.

## Install

Scratch needs macOS 26 on a Mac with Apple Silicon.

1. Download `Scratch-<version>.dmg` from the [latest release](https://github.com/ldellisola/scratch-mac/releases/latest)
   and open it.
2. Drag Scratch onto the Applications folder in the window that opens, then eject the disk image.
3. Open Scratch. macOS blocks the first launch of every new version, because the app is not notarised. Go to
   System Settings → Privacy & Security, scroll down to the message about Scratch and click **Open Anyway**. In Terminal,
   `xattr -dr com.apple.quarantine /Applications/Scratch.app` does the same.

To update, do the same with the new release and choose Replace. Your notes live in
`~/Library/Application Support/Scratch`, not in the app, so replacing the app never touches them. Every release also has
`Scratch-<version>.zip` with the same app, if you prefer a zip.

## Keyboard shortcuts

| Shortcut | Does |
|---|---|
| ⌘N, ⌘T | New note, in a new tab at the end of the strip |
| ⌘W, ⇧⌘W | Close the tab, close the window (which quits) |
| ⌃Tab, ⌃⇧Tab | Next and previous tab |
| ⌘1 to ⌘8, ⌘9 | The tab with that number, the last tab |
| ⌘-click a note | Open it in a new tab next to the active one |
| ⇧⌘P | Pin or unpin the note |
| ⌥⌘F | Search the notes. ⌘F finds inside the open note |
| ⌘⌫ | Delete the highlighted note, while the sidebar has the keyboard |
| ⌃⌘S | Show or hide the sidebar |
| ⌘+, ⌘−, ⌘0 | Bigger, smaller, actual text size |
| Return | In a list, a new item below (a new checkbox is open). On an empty item it ends the list, or outdents the item |
| Tab, ⇧Tab | In a list, indent or outdent the item (every list line of the selection) |
| ⌘B | Bold: with the caret in a word, `**` around the word, and on a bold run the stars come off. With a selection of several lines, each line is its own run |
| ⇧⌘L | Turn the selected lines into a checklist, or back into plain lines |
| ⇧⌘U | Mark as Checked: tick every checklist line of the selection, or untick them all when they are all ticked |
| Right-click in the note | Where they apply: Mark as Checked on a box, Open Link on a link, Open Attachment on an attachment, and Code Block Language inside a code block |
| ⌘-click a link | Open the `http://` or `https://` link in your browser. A plain click only places the caret |
| ⌘V | Paste as plain text. Two lines or more of code are then wrapped in a fence with their language: ⌘Z once leaves the plain paste. Files copied in Finder, and an image that comes with no text, become attachments |
| Click a code block's label | Choose the block's language, show it as plain text, or take its fence off (Not Code) |
| ⇧⌘A, the paperclip | Attach files: choose them in a sheet, and they go in at the caret (File > Attach File…) |
| Click an attachment | Select it (⌘C copies its file and its name, ⌘X cuts it) |
| Double-click an attachment | Open its file with its default app |
| Click a checkbox | Tick or untick the item. A double-click ticks it once, not twice |
| Help > Launch Times… | The newest launches, with Copy (see Checking launch speed) |
| Drag an attachment out | Give its file to Finder, Mail or another app. Scratch's own copy stays in the note |
| Backspace after an attachment, Delete before it | Select it. Press again to delete it (⌘Z brings it back) |

## How it is built

Scratch is developed only by AI agents. The app is a thin AppKit shell (a TextKit 1 editor, and a Liquid Glass sidebar
and tab strip) over two Swift packages that build and test on Linux as well as on macOS: `ScratchCore`, which is
Foundation-only and holds the rules and the SQLite storage, and `ScratchCode`, which wraps
[tree-sitter](https://tree-sitter.github.io/) (the one third-party dependency) to colour code and to detect it. The
licences of tree-sitter and its grammars are in the About panel.
Everything that needs a Mac runs on GitHub's Macs, and each merge that changes the app publishes a release.

- [AGENTS.md](AGENTS.md): the entry point for anyone working on the repository: commands, how to verify a change, and
  the pitfalls found so far
- [The design](docs/superpowers/specs/2026-10-19-scratchpad-design.md), [the roadmap](docs/superpowers/plans/2026-10-19-roadmap.md)
  and [the architecture](docs/architecture.md)
- [`docs/features`](docs/features) (what each feature does) and [`docs/decisions`](docs/decisions) (why it is that way)
