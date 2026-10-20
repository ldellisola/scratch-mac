# 0004: A new note opens at the end of the strip, and an emptied note is kept

Status: accepted, 2026-10-20 (the owner's decisions after Plan 2's final review). Settles where a new tab opens, which
spec §6.3 left open, and narrows a [call] in spec §6.3: "A note that is still completely empty (no title, no text, no
attachments) when its tab is closed is discarded."

## Decision

1. **A new note opens at the end of the tab strip.** ⌘N, ⌘T, the toolbar's new note button and the strip's "+" button
   all make a new empty note in a new tab after the last tab, as a browser does, and put the cursor in it. A note that
   the owner opens with ⌘-click in the sidebar opens in a new tab right after the active tab, which is what the code
   does already and is now confirmed. A plain click still shows the note in the current tab.
2. **Only an untouched note is discarded when its tab closes or when another note replaces it in the tab.** An
   untouched note is one that nobody has used: created in this session, or empty when the app started, and still empty
   (no title, no text beyond whitespace). A note that already existed and that the owner empties is kept, listed as
   "Untitled", until the owner deletes it. Spec §6.3 said that any note that is completely empty when its tab closes is
   discarded: that is no longer so.

## Why

- **Where a tab opens.** A new tab at the end is what the owner expects from a browser, and the strip's "+" button sits
  at the end. A note opened from the sidebar is different: the owner picked it from a list, and it belongs next to what
  they were looking at, as "open link in new tab" does.
- **Emptying a note is not deleting it.** Spec §6.7 says that notes are deleted only by the owner, and that nothing
  else ever removes a note (the 30-day purge only touches Recently Deleted). A note that disappears because its text
  was cleared and its tab was closed is a note the owner did not delete. The empty notes ⌘T makes are different: nobody
  wrote anything in them, and keeping them would litter the list, which is why §6.3 discards them.

## What the app does

`SessionCoordinator` keeps `untouchedNoteIDs`: the notes it created in this session (⌘N, ⌘T, the toolbar, "+", closing
the only tab, the first launch) and the notes that were empty when the saved session was restored. An untouched note is
one of these that is still empty. It is not listed in the sidebar while it is empty, it survives a switch to another tab,
and it is discarded (`NoteStore.discard`, the row is deleted) when its tab closes or another note replaces it in its
tab. `newNoteInNewTab` selects the last tab before it opens the new one, which puts it at the end. The sidebar's
⌘-click goes through `TabList.open(_:inNewTab:)`, which inserts after the active tab.

## Consequences

- `docs/features/tabs.md` states both rules and points here, and spec §6.3 carries a one-line note that this record
  amends it.
- **The code does not tell every emptied note from an untouched one yet.** A stored note has no mark for "was typed in",
  so the set above is an approximation of the owner's rule, and it is wrong in two cases, both for a note whose tab is
  still open when it is emptied:
  1. A note created in this session, typed in, and then emptied is still in `untouchedNoteIDs` (typing does not remove
     it), so closing its tab discards it.
  2. A note that had text, was emptied, and was still open in a tab at quit is empty when the session is restored, so it
     counts as untouched after the relaunch: it is not listed in the sidebar and closing its tab discards it.

  Closing both needs a change to `App/` (take a note out of the set at its first edit, and, when restoring, count a note
  as untouched only when its `modifiedAt` is still its `createdAt`, which `NoteStore.create` sets and every save of typed
  text changes) with a test for each case, and a `VERSION` bump. It is not part of this record's change, which touches
  no app code.
- Any other rule for discarding a note, or for where a tab opens, supersedes this record.
