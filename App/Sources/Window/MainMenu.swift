import AppKit

/// The menu bar. The app has no storyboard, so without this there would be no ⌘Q and no ⌘C, ⌘V or ⌘Z for the editor.
/// Most items send their action to the first responder, so the editor and the window handle them. The items that
/// belong to the app (the tabs, pinning, searching the notes and the font size) have `commands` as their target.
enum MainMenu {
    /// Makes this the application's menu bar. The Window menu is registered as the application's windows menu, so the
    /// system lists the open windows in it. `commands` is the target of the app's own items and must outlive the menu:
    /// a menu item holds its target weakly.
    static func install(in application: NSApplication, commands: AppCommands) {
        let menuBar = NSMenu()
        let windowMenu = windowMenu(commands: commands)
        let helpMenu = helpMenu(commands: commands)
        for menu in [
            appMenu(commands: commands), fileMenu(commands: commands), editMenu(commands: commands), formatMenu(),
            viewMenu(commands: commands), windowMenu, helpMenu,
        ] {
            let item = NSMenuItem()
            item.submenu = menu
            menuBar.addItem(item)
        }
        application.mainMenu = menuBar
        application.windowsMenu = windowMenu
        // The system adds its Help search field to this menu and puts the menu last.
        application.helpMenu = helpMenu
    }

    /// Launch Times… shows how long the launches of Scratch on this Mac took (plan 6 task 1), which is how the cold-boot
    /// budget of the spec (§7) is checked.
    private static func helpMenu(commands: AppCommands) -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(
            commandItem("Launch Times…", #selector(AppCommands.showLaunchTimes(_:)), key: "", target: commands))
        return menu
    }

    /// Minimize and Zoom, then the tabs (spec §6.3): ⌃Tab and ⌃⇧Tab, and ⌘1 to ⌘9.
    private static func windowMenu(commands: AppCommands) -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(
            withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let next = commandItem("Show Next Tab", #selector(AppCommands.nextTab(_:)), key: "\t", target: commands)
        next.keyEquivalentModifierMask = [.control]
        menu.addItem(next)
        // Shift+Tab is a character of its own on the keyboard, "back tab" (U+0019), and AppKit matches the key
        // equivalent against the character. Whether it also wants the Shift flag in the mask is not documented, so the
        // item exists in the three spellings that could match, and only the first one is listed. A hidden item still
        // answers its key equivalent (`allowKeyEquivalentWhenHidden`).
        let previous = commandItem(
            "Show Previous Tab", #selector(AppCommands.previousTab(_:)), key: "\t", target: commands)
        previous.keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(previous)
        let backTabMasks: [NSEvent.ModifierFlags] = [[.control], [.control, .shift]]
        for mask in backTabMasks {
            let alternate = commandItem(
                "Show Previous Tab", #selector(AppCommands.previousTab(_:)), key: backTab, target: commands)
            alternate.keyEquivalentModifierMask = mask
            alternate.isHidden = true
            allowKeyEquivalentWhenHidden(alternate)
            menu.addItem(alternate)
        }

        menu.addItem(.separator())
        for number in 1...9 {
            let title = number == 9 ? "Select Last Tab" : "Select Tab \(number)"
            let item = commandItem(title, #selector(AppCommands.selectTab(_:)), key: String(number), target: commands)
            item.tag = number
            menu.addItem(item)
        }
        return menu
    }

    /// Shift+Tab's character, `NSBackTabCharacter`.
    private static let backTab = "\u{19}"

    /// About Scratch is the app's own item, so that the panel can show the licences of tree-sitter as its credits
    /// (`AboutCredits`).
    private static func appMenu(commands: AppCommands) -> NSMenu {
        let menu = NSMenu(title: "Scratch")
        menu.addItem(commandItem("About Scratch", #selector(AppCommands.showAbout(_:)), key: "", target: commands))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Scratch", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Scratch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    /// New Note and New Tab both open a new empty note in a new tab. ⇧⌘A attaches files to the note (spec §6.4). ⇧⌘P pins
    /// the note of the active tab, or unpins it (`AppCommands.validateMenuItem` sets the title). ⌘W closes the tab, and
    /// ⇧⌘W the window (which quits, spec §6.6).
    private static func fileMenu(commands: AppCommands) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(commandItem("New Note", #selector(AppCommands.newNote(_:)), key: "n", target: commands))
        menu.addItem(commandItem("New Tab", #selector(AppCommands.newNote(_:)), key: "t", target: commands))
        menu.addItem(.separator())
        let attach = commandItem("Attach File…", #selector(AppCommands.attachFile(_:)), key: "a", target: commands)
        attach.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(attach)
        let pin = commandItem("Pin Note", #selector(AppCommands.togglePin(_:)), key: "p", target: commands)
        pin.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(pin)
        menu.addItem(.separator())
        menu.addItem(commandItem("Close Tab", #selector(AppCommands.closeTab(_:)), key: "w", target: commands))
        let closeWindow = menu.addItem(
            withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeWindow.keyEquivalentModifierMask = [.command, .shift]
        return menu
    }

    private static func editMenu(commands: AppCommands) -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        // The same as Paste: pasted text always takes the note's font (spec §6.5).
        let pasteAndMatch = menu.addItem(
            withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        pasteAndMatch.keyEquivalentModifierMask = [.command, .option, .shift]
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        // The standard find bar of the text view. The tag is the NSTextFinder.Action the text view performs.
        let find = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        for (title, key, action) in [
            ("Find…", "f", NSTextFinder.Action.showFindInterface),
            ("Find Next", "g", NSTextFinder.Action.nextMatch),
            ("Find Previous", "G", NSTextFinder.Action.previousMatch),
        ] {
            let item = findMenu.addItem(
                withTitle: title, action: #selector(NSTextView.performTextFinderAction(_:)), keyEquivalent: key)
            item.tag = action.rawValue
        }
        find.submenu = findMenu
        menu.addItem(find)

        // ⌘F finds in the note. This one searches all the notes, in the sidebar.
        let search = commandItem("Search Notes", #selector(AppCommands.focusSearch(_:)), key: "f", target: commands)
        search.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(search)
        return menu
    }

    /// The commands that change the text of the note (spec §6.4): Bold, ⌘B, and Checklist, ⇧⌘L. They go to the first
    /// responder, so only the editor answers them (`NoteTextView`). The items are not validated by AppKit: it would ask
    /// the first responder, which is a text view whose own validation of an action it does not know is not documented,
    /// and a command that cannot work (a read-only note, a code block) beeps instead of being greyed out. The action of
    /// Bold is `toggleBoldMarkers:` and not AppKit's `toggleBold:`, which is the font panel's.
    static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        menu.autoenablesItems = false
        menu.addItem(
            withTitle: "Bold", action: #selector(NoteTextView.toggleBoldMarkers(_:)), keyEquivalent: "b")
        let checklist = menu.addItem(
            withTitle: "Checklist", action: #selector(NoteTextView.toggleChecklist(_:)), keyEquivalent: "l")
        checklist.keyEquivalentModifierMask = [.command, .shift]
        return menu
    }

    private static func viewMenu(commands: AppCommands) -> NSMenu {
        let menu = NSMenu(title: "View")
        // The font size, the same for every note (spec §6.4).
        menu.addItem(commandItem("Bigger", #selector(AppCommands.bigger(_:)), key: "+", target: commands))
        // ⌘= does the same, because the + key needs Shift on most keyboards. It is hidden, so the menu lists ⌘+ only.
        let alternate = commandItem("Bigger", #selector(AppCommands.bigger(_:)), key: "=", target: commands)
        alternate.isHidden = true
        allowKeyEquivalentWhenHidden(alternate)
        menu.addItem(alternate)
        menu.addItem(commandItem("Smaller", #selector(AppCommands.smaller(_:)), key: "-", target: commands))
        menu.addItem(commandItem("Actual Size", #selector(AppCommands.actualSize(_:)), key: "0", target: commands))
        menu.addItem(.separator())

        let sidebar = menu.addItem(
            withTitle: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        let fullScreen = menu.addItem(
            withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        return menu
    }

    /// A menu item with ⌘ plus `key` that sends `action` to `target`.
    private static func commandItem(_ title: String, _ action: Selector, key: String, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    /// Lets a hidden item still answer its key equivalent: AppKit may skip the key equivalent of a hidden item, and
    /// `allowsKeyEquivalentWhenHidden` tells it not to. The property is set by name and only when the item has it, so
    /// that a system without it leaves the item alone instead of failing.
    private static func allowKeyEquivalentWhenHidden(_ item: NSMenuItem) {
        guard item.responds(to: Selector(("setAllowsKeyEquivalentWhenHidden:"))) else { return }
        item.setValue(true, forKey: "allowsKeyEquivalentWhenHidden")
    }
}
