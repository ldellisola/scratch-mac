import AppKit

// The entry point. The application object keeps its delegate only weakly, so the delegate lives in this constant.
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
