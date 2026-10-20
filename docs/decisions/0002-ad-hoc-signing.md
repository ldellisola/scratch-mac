# 0002: Releases are ad-hoc signed

Status: accepted, 2026-10-20 (plan 1, task 11). Changes a [call] in spec §9.6 ("Every release is signed with the same
self-signed code-signing certificate") and removes the owner's second one-time step in spec §11 ("Add the
signing-certificate secret to the repository"). The owner's decision in §9.6 stands: no Apple Developer account, no
notarisation (the owner: "unsigned is fine"), and the owner clicks through macOS's prompts.

## Decision

Every release build is **ad-hoc signed**: `CODE_SIGN_IDENTITY: "-"` in `App/project.yml`, which is also what Debug and
the CI builds use. It is not signed with a self-signed certificate, so there is no certificate, no GitHub Actions secret
and nothing for the owner to set up. The release workflow (`.github/workflows/release.yml`) needs only the repository's
own token.

Nothing else about §9.6 changes. Builds are not notarised, each release is a zip of `Scratch.app` on a GitHub Release,
and the owner approves each downloaded version once with System Settings → Privacy & Security → Open Anyway (or
`xattr -dr com.apple.quarantine`). `docs/release-notes-footer.md` repeats these steps on every release.

## Why

The spec wanted a stable signing identity for one reason: macOS ties some things to the signature of the app, and an
update with a different identity is a different app to those things. An ad-hoc signature has no identity beyond the hash
of the code (its `cdhash`), so it changes with every build. What matters is whether Scratch has anything of that kind.
It does not:

- **Its data is not behind its signature.** The app is not sandboxed (spec §5), so its notes are ordinary files in
  `~/Library/Application Support/Scratch`, owned by the user and readable by any build of the app. The risk the spec
  names, a sandbox container that a new identity cannot open, does not exist without a sandbox.
- **It uses no keychain item**, whose access list names the app that created it.
- **It asks for no privacy permission** (Accessibility, Full Disk Access, Files and Folders, the camera and the like),
  which macOS records against the app's code requirement and asks for again when that changes.
- **It makes no network connection**, so there is no firewall prompt, which is also tied to the signature.

A self-signed certificate would also not change what Gatekeeper does. A downloaded app that is signed by neither an
Apple Developer ID nor notarised is blocked the same way whatever it is signed with, so the owner approves each new
download either way.

Apple silicon runs only signed code. The linker signs every arm64 binary ad hoc, and Xcode seals the app bundle the same
way when the signing identity is `-`, so a build needs no certificate to run.

## Consequences

- **Spec §11, step 2 no longer applies.** There is no certificate to create and no secret to add. Step 1 (allowing
  `download.swift.org`) is unaffected.
- **Each release has a new identity.** That is invisible today, for the reasons above.
- **Revisit this when a feature needs a stable identity.** Any of these does: a sandbox, a keychain item, a privacy
  permission (Accessibility for a global hotkey, for example), a login item, or talking to another app by its code
  requirement. The spec's non-goals (§3: no global hotkey, no menu bar icon, no sync or accounts) already rule out the
  likeliest ones. The request that needs one is the time to supersede this record with a self-signed certificate or a
  Developer ID.
- **`make release-zip` checks the signature** (`scripts/check-release-zip.sh`): it must verify and it must be ad hoc, so
  a project change that quietly switched the signing identity would fail CI.
