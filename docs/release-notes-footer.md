## Install or update

Scratch needs macOS 26 on a Mac with Apple Silicon. Your notes live in `~/Library/Application Support/Scratch`, not in
the app, so replacing the app never touches them.

1. Download `Scratch-<version>.zip` from the assets below and unzip it.
2. Quit Scratch if it is running.
3. Drag `Scratch.app` to Applications. When you update, replace the old copy.
4. Open it. macOS blocks the first launch of every new version, because the app is not notarised. Go to System
   Settings → Privacy & Security, scroll down to the message about Scratch and click Open Anyway. The alternative is
   to run `xattr -dr com.apple.quarantine /Applications/Scratch.app` in Terminal, then open the app as usual.
