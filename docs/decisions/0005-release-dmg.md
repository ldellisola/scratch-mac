# 0005: Every release carries a DMG next to the zip

Status: accepted, 2026-10-20 (the owner's request). Extends a [call] in spec §9.6: "Every merge to `main` that changes
the app publishes a GitHub Release, with a zipped `Scratch.app` and short release notes". The zip stays. The spec's
other decisions about releases are unchanged: ad-hoc signed and not notarised (ADR 0002), versions from `VERSION`, one
release per merge that changes the app.

## Decision

Each GitHub Release has two files, built from the same Release app in one run of `.github/workflows/release.yml`:

- `Scratch-<VERSION>.dmg`, the one the release notes tell the owner to download: open it, drag Scratch onto the
  Applications folder in its window.
- `Scratch-<VERSION>.zip`, as before, for anyone who prefers a zip.

The image is made by `make release-dmg`, after `make release-zip`:

- It is a read-only compressed image (`hdiutil create -format UDZO`) named "Scratch <VERSION>", made from a staging
  folder that holds a copy of `Scratch.app` (made with `ditto`, which keeps the ad-hoc signature) and an `Applications`
  symlink to `/Applications`. Finder shows both in the window, and a drag onto the link installs the app.
- `scripts/check-release-dmg.sh` attaches it read-only (`-nobrowse`, at a temporary mount point, always detached again)
  and checks what a user would get: the window holds the app and the link and nothing else that is visible, the version,
  build version and bundle identifier, arm64 only, and a signature that verifies (`codesign --verify --deep --strict`)
  and is ad hoc. `scripts/tests/test-release-dmg.sh` runs the script against stubs of the macOS tools on Linux.
- CI builds and checks the image on every push (the `release-dmg` step of the `macos` job, after `release-zip`), so a
  broken image shows up on the branch, as a broken zip does.

## Why

A disk image is the way a Mac app is usually installed, and its window shows where the app goes. The zip needs the owner
to unzip it and find the Applications folder.

## What it does not do

- **No custom window.** There is no background picture and no icon layout. Those are stored in a `.DS_Store` that only
  Finder writes, through scripting that is fragile on a headless runner, or through a tool such as `create-dmg`, which
  would be a new dependency (and a decision record of its own). `hdiutil` is part of macOS and its output is the same on
  every run. A window design can be added later, with its own record.
- **No change to signing or notarisation.** The image itself is not signed, and signing it would not change what
  Gatekeeper does with an app that is not notarised. The download is quarantined, and macOS passes that on to the app
  copied out of the mounted image, as it does for an unzipped app, so the owner still approves each new version once
  with Open Anyway (ADR 0002). The release notes keep those steps.
