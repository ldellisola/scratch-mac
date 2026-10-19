import AppKit

/// The one window. Closing it quits the app (`AppDelegate`).
final class MainWindowController: NSWindowController {
    private static let frameAutosaveName = "MainWindow"

    /// Builds the window around `content`. Its frame is remembered between launches, except in an isolated data
    /// directory (tests, screenshots, benchmarks), which must always start from the same frame.
    init(environment: AppEnvironment, content: NSViewController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)

        // The window is owned by this controller. A window that also releases itself on close is over-released.
        window.isReleasedWhenClosed = false
        window.title = "Scratch"
        window.titleVisibility = .hidden
        window.contentViewController = content
        // Assigning the content view controller resizes the window to the controller's view, so size it afterwards.
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.contentMinSize = NSSize(width: 520, height: 320)
        shouldCascadeWindows = false

        if environment.options.isIsolated {
            window.center()
        } else {
            if !window.setFrameUsingName(Self.frameAutosaveName) { window.center() }
            _ = window.setFrameAutosaveName(Self.frameAutosaveName)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MainWindowController is created in code")
    }
}
