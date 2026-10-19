import AppKit

/// Measures how long the main thread works for each frame while the editor scrolls, and writes the numbers to a JSON
/// file. A debug tool for the performance tests, switched on by `-ScratchFrameMonitor <path>` (`LaunchOptions`); a
/// normal launch never creates one.
///
/// XCTest has no metric for the most expensive frame of a scroll on macOS (`XCTOSSignpostMetric`'s scrolling metrics
/// are not there), and a display link only reports the time between two frames, which includes the time the main
/// thread was idle. What the spec's budget asks for is the main thread's work per frame (§7), so this measures that:
///
/// - A frame is one pass of the main run loop in which the editor's clip view scrolled. It starts when the loop wakes
///   up and ends when the loop is next about to wait, after AppKit has drawn and Core Animation has committed
///   (`RunLoopIdle`).
/// - Scrolling during the first `warmUp` seconds after launch is ignored: restoring the note and the first layout move
///   the clip view as well, and are the launch budget's business.
/// - `reportDelay` seconds after the last frame the file is written, with the longest frame (`max_frame_ms`), the 95th
///   percentile (`p95_frame_ms`), the mean (`mean_frame_ms`) and the number of frames (`frames`). It is written again
///   after any later scrolling, with every frame since launch.
@MainActor
final class FrameMonitor {
    static let warmUp: TimeInterval = 3
    static let reportDelay: TimeInterval = 0.8

    private let file: URL
    private let clipView: NSClipView
    private let startedAt = DispatchTime.now().uptimeNanoseconds
    private var passStartedAt = DispatchTime.now().uptimeNanoseconds
    private var passScrolled = false
    private var frameMilliseconds: [Double] = []
    private var runLoopObserver: CFRunLoopObserver?
    private var scrollObserver: (any NSObjectProtocol)?
    private var reportTimer: Timer?

    /// `clipView` is the one to watch (the editor's), `file` is where the report goes.
    init(file: URL, clipView: NSClipView) {
        self.file = file
        self.clipView = clipView
    }

    /// Starts measuring. Call it once, at the end of the launch.
    func start() {
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clipView, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clipViewDidScroll() }
        }
        let activities: CFRunLoopActivity = [.afterWaiting, .beforeWaiting]
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, activities.rawValue, true, RunLoopIdle.order
        ) { [weak self] _, activity in
            MainActor.assumeIsolated { self?.runLoopReached(activity) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        runLoopObserver = observer
    }

    private func clipViewDidScroll() {
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000
        guard seconds >= Self.warmUp else { return }
        passScrolled = true
        reportTimer?.invalidate()
        reportTimer = Timer.scheduledTimer(withTimeInterval: Self.reportDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeReport() }
        }
    }

    private func runLoopReached(_ activity: CFRunLoopActivity) {
        let now = DispatchTime.now().uptimeNanoseconds
        if activity.contains(.afterWaiting) {
            passStartedAt = now
        }
        if activity.contains(.beforeWaiting), passScrolled {
            passScrolled = false
            frameMilliseconds.append(Double(now - passStartedAt) / 1_000_000)
        }
    }

    private func writeReport() {
        do {
            try Self.reportData(frameMilliseconds: frameMilliseconds).write(to: file, options: .atomic)
        } catch {
            let message = "Scratch: cannot write the frame report to \(file.path): \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    // MARK: The report

    /// The numbers of `frameMilliseconds`, rounded to microseconds: `frames`, `max_frame_ms`, `p95_frame_ms` (nearest
    /// rank) and `mean_frame_ms`. All zero without frames.
    static func report(frameMilliseconds frames: [Double]) -> [String: Double] {
        guard !frames.isEmpty else {
            return ["frames": 0, "max_frame_ms": 0, "p95_frame_ms": 0, "mean_frame_ms": 0]
        }
        let sorted = frames.sorted()
        let rank = Int((0.95 * Double(sorted.count)).rounded(.up))
        let mean = frames.reduce(0, +) / Double(frames.count)
        return [
            "frames": Double(frames.count),
            "max_frame_ms": rounded(sorted[sorted.count - 1]),
            "p95_frame_ms": rounded(sorted[max(rank - 1, 0)]),
            "mean_frame_ms": rounded(mean),
        ]
    }

    /// The report as JSON, with sorted keys.
    static func reportData(frameMilliseconds frames: [Double]) -> Data {
        (try? JSONSerialization.data(withJSONObject: report(frameMilliseconds: frames), options: [.sortedKeys]))
            ?? Data("{}".utf8)
    }

    private static func rounded(_ milliseconds: Double) -> Double {
        (milliseconds * 1000).rounded() / 1000
    }
}
