import AppKit

/// The menu bar. The app has no storyboard, so without this there would be no ⌘Q and no ⌘C, ⌘V or ⌘Z for the editor.
/// Most items send their action to the first responder, so the editor and the window handle them. The items that
/// belong to the app (the font size) have `commands` as their target.
enum MainMenu {
    /// Makes this the application's menu bar. The Window menu is registered as the application's windows menu, so the
    /// system lists the open windows in it. `commands` is the target of the app's own items and must outlive the menu:
    /// a menu item holds its target weakly.
    static func install(in application: NSApplication, commands: AppCommands) {
        let menuBar = NSMenu()
        let windowMenu = windowMenu()
        for menu in [appMenu(), fileMenu(), editMenu(), viewMenu(commands: commands), windowMenu] {
            let item = NSMenuItem()
            item.submenu = menu
            menuBar.addItem(item)
        }
        application.mainMenu = menuBar
        application.windowsMenu = windowMenu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(
            withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        return menu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Scratch")
        menu.addItem(
            withTitle: "About Scratch", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
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

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    private static func editMenu() -> NSMenu {
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
