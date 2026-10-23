# 0010: Scratch 1.0 calls: the app icon, and Pillow as a development tool

Status: accepted, 2026-10-23 (Plan 6, task 9, Scratch 1.0.0). Fills the spec's one open item for the icon (§8.2: "App icon,
accent colour usage, and other visual polish within the native, Liquid Glass look of the mockup"). Adds no runtime dependency:
Pillow draws the icon on a developer's machine and in the `linux` CI job, and neither the app nor any build of it uses it.

This record is the one for the calls that Plan 6 makes for 1.0.0 (its Global Constraints mark them `[calls, ADR 0010]`). Task 9
writes the section on the icon. The sections on the look, editing and attachments are written by Task 10, from the plan's
Global Constraints and from what the code does by then.

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

## What it does not do

- **No dark or tinted variant.** One set of PNGs, one look (decision 2).
- **No change to the DMG's window** (ADR 0005): it still shows the app and the Applications link, now with the icon.
