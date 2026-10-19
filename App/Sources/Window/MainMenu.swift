import AppKit

/// The menu bar. The app has no storyboard, so without this there would be no ⌘Q and no ⌘C, ⌘V or ⌘Z for the editor.
/// Every item sends its action to the first responder, so the editor and the window handle them.
enum MainMenu {
    /// Makes this the application's menu bar. The Window menu is registered as the application's windows menu, so the
    /// system lists the open windows in it.
    static func install(in application: NSApplication) {
        let menuBar = NSMenu()
        let windowMenu = windowMenu()
        for menu in [appMenu(), fileMenu(), editMenu(), viewMenu(), windowMenu] {
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

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        let sidebar = menu.addItem(
            withTitle: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        let fullScreen = menu.addItem(
            withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        return menu
    }
}
