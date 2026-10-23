import AppKit

// LaunchReference: an AppKit app that does nothing but show a window with a text view in it, and the floor of what
// the performance tests can say about Scratch's launch (docs/decisions/0009).
//
// A launch on CI's virtual Macs takes about 600 ms whatever the app does (a system app takes a second or more: ADR
// 0003), and varies between runs of the same build by a factor of two, so the spec's 200 ms (§7) cannot gate the app's
// own launch there. `LaunchPerfTests.testReferenceLaunch` measures this app the way it measures Scratch, in the same job
// on the same runner, and the difference (`launch_overhead_ms`) is the work that Scratch adds to what any app with a
// window and a TextKit 1 text view costs. The window has the size of Scratch's (1100 x 700) and the text view is made
// the way the editor's is (TextKit 1: `NSTextView(usingTextLayoutManager: false)`, in a scroll view), so that the text
// system starts in both.
//
// It has no menu, no storage and no sidebar on purpose, and it is never part of the Scratch app or of a release: it is a
// target of its own (App/project.yml) that only the ScratchPerf scheme builds.

@MainActor
final class ReferenceDelegate: NSObject, NSApplicationDelegate {
    /// The one window. The application does not keep it alive: this does.
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = "LaunchReference: an empty AppKit app, the floor of Scratch's launch measurement."

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "LaunchReference"
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// The application keeps its delegate only weakly, so the delegate lives in this constant.
let application = NSApplication.shared
let referenceDelegate = ReferenceDelegate()
application.delegate = referenceDelegate
application.run()
