## Install or update

Scratch needs macOS 26 on a Mac with Apple Silicon. Your notes live in `~/Library/Application Support/Scratch`, not in
the app, so replacing the app never touches them.

1. Download `Scratch-<version>.dmg` from the assets below and open it.
2. Quit Scratch if it is running.
3. In the window that opens, drag Scratch onto the Applications folder. When you update, choose Replace. Then eject the
   disk image.
4. Open Scratch. macOS blocks the first launch of every new version, because the app is not notarised. Go to System
   Settings → Privacy & Security, scroll down to the message about Scratch and click Open Anyway. The alternative is
   to run `xattr -dr com.apple.quarantine /Applications/Scratch.app` in Terminal, then open the app as usual.

`Scratch-<version>.zip` holds the same app, if you prefer a zip: unzip it and drag `Scratch.app` to Applications.
