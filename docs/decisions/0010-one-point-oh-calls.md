# 0010: Scratch 1.0 calls: the look, accessibility, editing, attachments and the app icon

Status: accepted, 2026-10-23 (Plan 6, tasks 5 to 10, Scratch 1.0.0). Records the calls that Plan 6 makes for 1.0.0, each
marked `[calls, ADR 0010]` or `[call]` in the plan's Global Constraints: mockup B's look (spec §6.1), what VoiceOver hears and
what Increase Contrast shows (§6.1), the editing and attachment follow-ups of 0.5.0 (§6.4 and §6.5), and the app icon, which
fills the spec's one open item for it (§8.2: "App icon, accent colour usage, and other visual polish within the native, Liquid
Glass look of the mockup"). Adds no runtime dependency: Pillow draws the icon on a developer's machine and in the `linux` CI
job, and neither the app nor any build of it uses it.

The decisions are numbered in one list. 1 to 5 are the icon (Task 9), 6 to 11 the look (Tasks 4 and 7), 12 to 14 accessibility
(Task 8), 15 and 16 editing (Task 5) and 17 to 19 attachments (Task 6). The plan's Global Constraints say what each does; this
record says why it is that and not the other thing, and what was measured. The behaviour itself is in `docs/features/`.

## Context

- **0.5.0 shipped with a placeholder icon.** `App/Resources/Assets.xcassets/AppIcon.appiconset` held ten PNGs, one for each
  size of a Mac icon, that were never designed. There is nothing to show in the Dock, in Raycast (how the owner launches
  Scratch) or in the About panel that says what the app is.
- **The app is developed by agents,** in Linux sessions that have no Xcode, no Icon Composer and no Sketch. An icon that
  cannot be made, looked at and changed there would be made once and never touched again.
- **The look has to be the system's.** An icon on macOS 26 sits among the system's own, so it follows the shape and the
  grid of a Big Sur icon, and it is judged where it is small: in a Dock at 32 to 64 pixels.

## Decisions

1. **The icon is a notepad with a ticked checkbox.** It draws what the app is for: a yellow note (a sticky note's yellow, the
   colour of every scratchpad on a desk) with the one piece of structure Scratch adds that is recognised at a glance, a
   checklist. The design, in units of a 1024 px canvas:
   - **The base** is the macOS squircle of the Big Sur grid, 824 x 824 at (100, 100): a superellipse with exponent 5, filled
     with a vertical gradient from `#FFE07A` (top) to `#FFB938` (bottom), and a shadow of 28 px blur (a Gaussian of sigma 14,
     what a blur of 28 means in CSS and in design tools), 12 px down, 30% black.
   - **On it:** a ticked checkbox (a 120 px square of radius 28 at (230, 300), `#0A84FF`, with a white tick of 22 px stroke)
     and a line beside it (x 400 to 790 at y 360, 56 px high, `#1C1C1E` at 85%), a 64 px dot of the same blue at (290, 540) with
     a line beside it (400 to 720 at y 540), and a last, paler line (260 to 620 at y 720, 45%): a ticked item, a bullet and a
     line of plain text, the three things a note in Scratch is made of.
   - **The blue is the system's** (the default accent colour: `#0A84FF` is `systemBlue` in dark mode), so the box of the
     icon looks like the box of the editor, which `controlAccentColor` fills.
   - **It has to read at 32 px,** which the plan's rule makes the test of the design: at that size the checkbox is a blue
     square of about 4 pixels with a lighter pixel for the tick, and the three lines are lines. `test_make_app_icon.py` samples
     the pixels of the 32, 128 and 1024 px icons at the points of the design (the checkbox and the dot blue, the first
     two lines dark, the third paler, the paper yellow between them, the corner of the canvas transparent).
2. **A script draws it, and the PNGs are checked in.** `scripts/make-app-icon.py [<appiconset directory>]` reads the sizes
   from the set's `Contents.json` (the ten images, 16 to 1024 px), draws each at 4 times its pixels and scales it down with
   LANCZOS, so that no edge is a staircase at 16 px, and writes the PNGs. The files in `AppIcon.appiconset` are its output.
   - **Why a script.** The numbers above are the design, a change to it is a reviewed diff of numbers, and any session
     can look at the result (a PNG, with the Read tool) before it pushes. A picture that somebody drew once cannot be
     changed that way.
   - **Why the PNGs are checked in.** Xcode's asset compiler builds the icon from them (`AppIcon.icns` and `Assets.car` in the
     app: `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in `App/project.yml`), and a build must not need Python.
     `test_checked_in_set_is_what_the_script_makes` fails when the script or the design changed and the PNGs were not made
     again.
   - **Why not an Icon Composer document (`.icon`).** It cannot be made or looked at in a Linux session. macOS 26 draws the
     tinted and clear variants of the icon only for such a document, so this icon is the same in every mode, and the system
     may show it on a plate of its own. A layered icon is a later change, and needs a Mac.
3. **Pillow is a development tool, not a dependency.** It is the one thing the script imports that is not in Python's standard
   library. It is not linked into, bundled with or run by the app, the tests of the app or the release. It is installed where
   the script is tested: the `linux` CI job installs Ubuntu's `python3-pil` (Pillow 10.2.0 in the job's image), and a Linux
   session that lacks it can `pip install pillow` (`make script-test` says so when it is missing). The output is the same bytes
   under Pillow 10.2.0 and 12.3.0 (measured), and the check against the checked-in files allows a mean difference of one level
   of 255 anyway, so another version cannot fail it by a rounding.
4. **A release is held to its icon.** `scripts/check-release-zip.sh` fails a zip whose app has no non-empty
   `Contents/Resources/AppIcon.icns` or whose `CFBundleIconName` is not `AppIcon`, so a build whose catalog lost the set, or
   whose project stopped naming it, never ships with the generic icon again. Its test covers each case
   (`scripts/tests/test-release-zip.sh`).
5. **The About panel is where the icon is looked at.** `ScreenshotTests.testAboutLight` opens Scratch > About Scratch and
   attaches a picture of the panel as `about-light`: the icon at its large size, the version and the credits.

## The look (Tasks 4 and 7, spec §6.1, mockup B)

6. **The tab strip is the view of a toolbar item, in the toolbar's row** (`[.toggleSidebar, .sidebarTrackingSeparator, strip,
   .flexibleSpace, pin, paperclip, .space, new note]`). Mockup B has the tabs on the toolbar's own row, left of the buttons, and
   0.5.0 had them in a band of their own under it. The item's view is the strip's own `NSGlassEffectView`
   (one capsule, 34 pt high like the toolbar's), its item is not bordered, so the toolbar draws no second capsule round it, and
   it has visibility priority `high`, and the three buttons are `user`, so none of them is ever moved into the overflow menu.
   - **The width is made to fit and never left to the toolbar.** A toolbar that is short of room moves items into its
     overflow menu, and a strip that is as wide as twelve tabs want would push the buttons out (Review Focus 4). The strip's
     required width is `min(its tabs' width, the room)`, at least 96 pt, where the room is the window's width less where the
     strip starts (16 pt into the editor area with the sidebar, 150 pt from the window's edge without it) less 176 pt for the
     buttons. The numbers are estimates on the safe side: the real position of the strip is only known after the toolbar has
     laid out, and a width worked out from it would be one layout late.
   - **`NSToolbarItem` has no `hidesSharedBackground` on the macOS 26.5 SDK** (using it did not compile), so `isBordered = false`
     is how the second capsule is kept away. The editor area is now the editor alone, from the very top of the window, with the
     toolbar in its safe area and its title field 10 pt below that: the title sits about 16 pt under the toolbar, with no empty
     band, as in the mockup.
7. **Every line has `round(0.3 x font size)` points after it**: 4 pt at 13 pt, 3 at 9, 10 at 32. It is
   `NSParagraphStyle.lineSpacing`, so TextKit puts it in the line fragments' heights and the text is one font line and the
   spacing apart, for plain lines, list lines and lines of code, and for what is typed next. A fence line (6 pt) and an
   attachment line (as high as its picture) have none. The mockup has air between its lines that 0.5.0's stacked lines lacked,
   and a fraction of the font size follows a change of the font size, where a fixed number of points would not.
   - **Anything that wants the font's line works from the font, never from the fragment.** The checkbox is 85% of the font's
     line height (`checkboxPointSize(for:)`) and the pill runs from the font's ascent to its descent, both measured from the
     baseline, because the fragment now has the spacing in it (`testCheckboxSizeIgnoresSpacing`). The `code` fixture lost three
     lines for the spacing, which pushed its last block below the 674 px window.
8. **Inline code is a pill that the layout manager draws.** The characters between the backticks carry `scratchInlineCode` and
   no `.backgroundColor`; `MarkupLayoutManager.drawInlineCode` fills a rounded rectangle (`CodeBackground`, radius 4, 2 pt wider
   than the text on each side, from the font's ascent to its descent plus 1 pt) behind each line fragment of a run. A
   background colour fills the glyphs' rectangle at the height of the line fragment, which now includes the spacing, and it
   cannot be rounded or padded. The `.backgroundColor` key stays among the keys the styler owns, because composed
   text may carry one (decision 16).
9. **A code block has a radius of 8 and a 1 pt border** in the new colour `CodeBorder` (black at 8% in light mode, white at 12%
   in dark mode, 35% and 45% with Increase Contrast). The border is stroked on the shape of the tint, which is cut off where a
   block goes on, so a redraw of some of a block's lines has no line across it. The mockup has it, and it keeps two blocks that
   sit on lines next to each other (the SQL block under the Python block in the `code` fixture) apart in a tint that is as light
   as 6%.
10. **An open box is grey and a ticked one stays in the accent colour.** The open box is `square` in `secondaryLabelColor`
    and the ticked one `checkmark.square.fill` with `controlAccentColor`, as before. Mockup B draws the boxes that
    way: the ticked ones, which are the only thing besides the bullets in the accent colour, read as done (`testOpenBoxIsGrey`).
11. **A sidebar row and a tab show a line as the editor shows it** (`PlainLine`, schema version 4). A checklist
    note showed its first line in the sidebar and in its tab with the box's brackets, the backticks and the stars that the
    editor hides. A line outside a fenced block loses its list marker, the `**` of bold and the backticks of inline code,
    and a line inside a block, a link and a glob (`src/**/*.ts`, ADR 0006) stay as typed. The three derived columns are
    written on every save and never worked out again, so a change of the rule is a migration step that works them out
    again for every stored note and writes only the rows that differ (never `modified_at`, so the order and the search
    index stay). The typed title is never changed. The `typical` screenshot's row reads `bump version to 2.4.1 run mi…`.

## Accessibility (Task 8, spec §6.1)

12. **VoiceOver hears the rendered note, and `accessibilityValue` stays the stored text.** `NoteTextView.accessibilityString(for:)`
    and `accessibilityAttributedString(for:)` speak what the styler made of the text (`SpokenText`): a bullet is "bullet", `[ ]`
    "unchecked", `[x]` "checked", a token "image, dashboard.png", "file, rollback-plan.txt" or "missing attachment", an opening
    fence "code block, Swift" and a closing one "end of code block", and the hidden and revealed markers nothing. The value
    is the stored text because a range and the caret that VoiceOver reports are offsets into the value, and a spoken text that
    differs in length from the characters (a marker is a word) would put them in the wrong place. The value is AppKit's
    own answer (`NSTextView` does not let a Swift subclass override it), and a test holds it to the text. **Nothing was tried with
    VoiceOver itself**: CI has no screen reader. The tests call the text view's methods, and the attributed string is AppKit's
    own for a range with nothing to replace.
    - **A sidebar row reads as one element through its cell's label**, "<title>, <time>, <preview>, pinned". A label on the row
      view never reached what XCTest sees, and naming the cell's children as its accessibility children hid the cell's texts
      from every UI test (CI: `the sidebar rows: []`). The texts stay the cell's children with their identifiers.
13. **Increase Contrast is a high contrast variant of every colour in the asset catalog**, light and dark, which AppKit picks
    when the setting is on. The hues are the usual ones moved along their lightness (never replaced): the code colours read at
    7:1 or more on the editor's background (and 5:1 on the stronger tint in dark mode), the tint is black 10% in place of 6% and
    white 14% in place of 10%, the border is 35% and 45%, and the raised tab has a 1 pt outline. **Reduce Transparency stays the
    system's**: only system materials (the sidebar, the toolbar's buttons and the tab strip) are translucent, and they follow
    the setting by themselves, so there is no code for it and no test.
    - **A test or a screenshot cannot ask for the variant.** On CI `NSAppearance(named:)` answered nil for the name of the high
      contrast appearances, and the SDK's `.accessibilityHighContrastAqua` and `…DarkAqua` are plain Aqua and Dark Aqua when they
      are made (their raw values are `NSAppearanceNameAccessibilityAqua` and `…DarkAqua`), so `NSColor(named:)` never gave a
      high contrast variant under a forced appearance. So `-ScratchAppearance` also takes `light-contrast` and `dark-contrast`,
      which force light or dark and have `CatalogColour.named` answer from a table of the catalog's high contrast colours (a test
      holds the table to the catalog's `Contents.json`, colour for colour). This deviates from the plan, which names the two
      appearance constants.
14. **Every action that only a mouse could do has another way.** Format > Mark as Checked (⇧⌘U) does what a click on a box does,
    and the editor's context menu has, each only where it applies to what is under the pointer, Mark as Checked (or Unchecked),
    Open Link, Open Attachment and a Code Block Language submenu that is the label's menu. Tab walks the search field, the note
    list, the title and the editor (`KeyViewLoop`, set explicitly, because AppKit's order follows the views' positions and not
    how the window is read). The context menu's items are validated by the text view itself, because how `NSTextView` validates
    an action it does not know is not documented.

## Editing (Task 5, spec §6.4)

15. **⌘B works on a caret and on several lines, ⇧⌘U ticks.** In 0.5.0 ⌘B with a caret put an empty `****` in, so bolding
    a word meant selecting it first, and a selection of several lines was wrapped once, which is no run when it crosses a line
    break (bold is one line only, ADR 0006).
    - **A caret is the word under it** (letters and digits of any script, and an apostrophe between two of them), so the stars
      always make a run: wraps the word with the caret kept at its place in it, unwraps a run it touches, removes an empty
      `****`, and elsewhere puts `****` in with the caret between the pairs. Several lines are a run each (after the list marker,
      white space at the ends and blank lines left out), or the stars come off all of them when every line is a run. White space
      only is a beep. ⌘B twice on a word puts the text back, and the stars never go into a list marker.
    - **⇧⌘U ticks every checklist line under the selection when any is open, and unticks them all otherwise**, so a second
      press is the undo. A selection with no checklist line, or in a code block, beeps. It is a menu item because every
      mouse action needs one (decision 14).
    - **A double-click on a box ticks it once.** The second click of a double-click on a box is taken and does nothing: it
      used to untick the box again, or select a word.
16. **Composed (IME) text keeps what marks it, and the title's undo steps stay with their note.**
    - **Composed text.** The styler gives every edited paragraph its base attributes, and composing is an edit at every key.
      The styler reads the underline, its colour, the clause segment and the `markedTextAttributes` values from what the edit
      put in, and puts them back after the styling. Measured on CI (macOS 26.6.2): AppKit puts none of them in the storage
      (it draws marked text by other means and writes the typing font on it), so the rule changes nothing there. It is kept
      for an input method that does hand them over, and a hosted test sets `isSettingMarkedText` itself and edits the storage
      with an attributed string like an input method's. A colour or a font that is not a `markedTextAttributes` value is the
      neighbour's and stays the styler's: keeping it would paint composed text next to inline code or a link as that.
    - **Title undo.** The title's field editor is the window's one, and a step registered in a note's manager would have it as
      its target and change whatever title it shows by the time it is undone, which was a wrong title or a crash. The title has
      an undo manager of its own (`TitleField.titleUndoManager`, which the field editor asks), and leaving a note ends the
      title's editing, empties it and removes the steps with the field editor as their target from the note's manager.

## Attachments (Task 6, spec §6.5)

17. **No token line ever shares its line with other characters, and the break is a second edit.** In 0.5.0 typing at an end of
    a token line made text of it, and the picture was gone (⌘Z brought it back). Text typed, composed or pasted at the end of a
    token line gets a line break before it, at its start a line break after it, and a token line inside what is inserted
    gets the breaks that keep it whole (`AttachmentEditing.lineBreaks`; none in a fenced block, none for what replaces a whole
    token line, none when the text brings a line break at that end).
    - **For typing and composing the break is its own edit, applied with `apply(_:)` before `super` inserts**, so ⌘Z takes the
      text back first (a key press ends in one run loop turn, so one ⌘Z may take both, and neither leaves half a token). The
      plan says two undo steps. A paste puts its breaks in its one edit. A break that is part of the same edit as the
      text would be one undo step and would have no half-token state either; the plan's two steps were kept, and the break is
      guarded where AppKit hands the view the text (`insertText`, the first `setMarkedText` of a composition, and `insertTab`).
18. **A selection that holds a token also writes the note's text, exactly as stored, on a private pasteboard type**
    (`io.github.ldellisola.Scratch.note-text`), and Paste and a drop into Scratch read it first. Copy writes names ("rollback-plan.txt")
    where a token was, so a drag of text with an attachment in it, or a copy of it into another note, made a line of file
    names, and the attachment was gone. With the type the tokens come in with the same ids, so both notes name one file, which
    stays until no stored note names it (ADR 0008). Other applications see the plain text only, so nothing of the note leaks. Into
    a code block, and where this store has no row for a token (a copy from another Scratch), the plain text is used as before.
19. **A copied image outlives Scratch.** The PNG and the TIFF of a copied image are promised, because decoding and encoding a
    full-size picture must not make Copy wait, and the promise goes when the app does. When Scratch quits while the general
    pasteboard still holds its own last copy of one image (it remembers the pasteboard's change count, so anything written to
    it since is left alone), `applicationWillTerminate` writes the item again with the data in place, after the notes are
    saved. The cost, hundreds of milliseconds for a full-size picture, is at quit and not at Copy.

## What it does not do

- **No dark or tinted variant of the icon.** One set of PNGs, one look (decision 2).
- **No change to the DMG's window** (ADR 0005): it still shows the app and the Applications link, now with the icon.
- **No screen-reader test.** VoiceOver, Increase Contrast and Reduce Transparency were checked through the attributes the app
  sets, the colours it resolves and screenshots of a forced launch; a person with the real setting on is what finds the rest.
- **No other application sees the note's text on the pasteboard** (decision 18), and no copy keeps an attachment for another
  Scratch's storage: that makes a new attachment of the file, as in 0.5.0.
