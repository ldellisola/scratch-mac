import Foundation

/// Runs work at the moment the main run loop is next about to wait for more events.
///
/// That moment comes after everything an event caused has happened: AppKit's layout and display of the views the event
/// invalidated (its observer runs at order 1,500,000 or so) and Core Animation's commit (order 2,000,000). The
/// observers here run after them, so "until the loop is idle" means "until the change is on screen". The performance
/// signposts end there (`Signposts.beginEditorInterval`), and so does the frame monitor's measurement of one frame.
enum RunLoopIdle {
    /// The observers' order: after AppKit's display cycle and Core Animation's commit, which run before the loop waits.
    static let order: CFIndex = 3_000_000

    /// Calls `work` once, the next time the main run loop is about to wait. Call it on the main thread.
    static func onNext(_ work: @escaping @MainActor () -> Void) {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, false, order
        ) { _, _ in
            MainActor.assumeIsolated { work() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
