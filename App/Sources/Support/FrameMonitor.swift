import AppKit

/// Scrolls the editor by itself and measures how long the main thread works for each frame, then writes the numbers to
/// a JSON file. A debug tool for the performance tests, switched on by `-ScratchFrameMonitor <path>`
/// (`LaunchOptions`); a normal launch never creates one.
///
/// XCTest has no metric for the most expensive frame of a scroll on macOS (`XCTOSSignpostMetric`'s scrolling metrics
/// are not there), and a display link only reports the time between two frames, which includes the time the main
/// thread was idle. What the spec's budget asks for is the main thread's work per frame (§7), so this measures that:
///
/// - A frame is one pass of the main run loop in which the editor's clip view scrolled. It starts when the loop wakes
///   up and ends when the loop is next about to wait, after AppKit has drawn and Core Animation has committed
///   (`RunLoopIdle`). It is timed twice: by the clock (`wall`) and by the CPU time of the main thread (`cpu`), which
///   leaves out the time the thread waits (for the window server, or for the virtual machine's other tenants).
/// - The scroll is the monitor's own: `warmUp` seconds after launch it moves the note `scrollStep` points down every
///   1/60 s, `scrollTicks` times (a quick scroll with a trackpad). A test that scrolled through UI events would send a
///   few events a second, and the arrow and page keys scroll a third of a window or a whole one at a time.
/// - Scrolling during the first `warmUp` seconds after launch is ignored: restoring the note and the first layout move
///   the clip view as well, and are the launch budget's business.
/// - `reportDelay` seconds after the last frame the file is written, with the number of frames (`frames`), the median,
///   95th percentile, longest and mean frame by the clock (`median_frame_ms`, `p95_frame_ms`, `max_frame_ms`,
///   `mean_frame_ms`) and by CPU time (`median_cpu_ms`, `p95_cpu_ms`, `max_cpu_ms`, `mean_cpu_ms`), and every frame in
///   milliseconds, in order (`frame_ms`, `frame_cpu_ms`). It is written again after any later scrolling, with every
///   frame since launch.
@MainActor
final class FrameMonitor {
    static let warmUp: TimeInterval = 3
    static let reportDelay: TimeInterval = 0.8
    /// The scripted scroll: how far each tick moves the note, how often, and how many ticks there are (5 seconds).
    static let scrollStep: CGFloat = 20
    static let scrollInterval: TimeInterval = 1.0 / 60
    static let scrollTicks = 300

    private let file: URL
    private let clipView: NSClipView
    private let startedAt = DispatchTime.now().uptimeNanoseconds
    private var passStartedAt = DispatchTime.now().uptimeNanoseconds
    private var passCPUStartedAt = FrameMonitor.threadCPUNanoseconds()
    private var passScrolled = false
    private var frames: [Frame] = []
    private var runLoopObserver: CFRunLoopObserver?
    private var scrollObserver: (any NSObjectProtocol)?
    private var reportTimer: Timer?
    private var scrollTimer: Timer?
    private var scrollTicksLeft = FrameMonitor.scrollTicks

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

        // Just after the warm-up, so that the first frame is already counted.
        Timer.scheduledTimer(withTimeInterval: Self.warmUp + 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginScrolling() }
        }
    }

    // MARK: The scripted scroll

    private func beginScrolling() {
        scrollTimer = Timer.scheduledTimer(withTimeInterval: Self.scrollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrollOneStep() }
        }
    }

    private func scrollOneStep() {
        guard scrollTicksLeft > 0, let scrollView = clipView.enclosingScrollView else {
            scrollTimer?.invalidate()
            scrollTimer = nil
            return
        }
        scrollTicksLeft -= 1
        let bounds = clipView.bounds
        let documentHeight = clipView.documentView?.frame.height ?? 0
        let lastY = max(documentHeight - bounds.height, bounds.origin.y)
        clipView.scroll(to: NSPoint(x: bounds.origin.x, y: min(bounds.origin.y + Self.scrollStep, lastY)))
        scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: Measuring

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
        let cpuNow = Self.threadCPUNanoseconds()
        if activity.contains(.afterWaiting) {
            passStartedAt = now
            passCPUStartedAt = cpuNow
        }
        if activity.contains(.beforeWaiting), passScrolled {
            passScrolled = false
            frames.append(
                Frame(wall: Double(now - passStartedAt) / 1_000_000, cpu: Double(cpuNow - passCPUStartedAt) / 1_000_000)
            )
        }
    }

    private func writeReport() {
        do {
            try Self.reportData(frames: frames).write(to: file, options: .atomic)
        } catch {
            let message = "Scratch: cannot write the frame report to \(file.path): \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    // MARK: The report

    /// How long one frame took, in milliseconds: by the clock, and as CPU time of the main thread.
    struct Frame: Equatable {
        var wall: Double
        var cpu: Double
    }

    /// The CPU time the calling thread has used so far, in nanoseconds.
    private static func threadCPUNanoseconds() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    }

    /// The numbers of `frames`, rounded to microseconds: `frames`; `median_frame_ms`, `p95_frame_ms` (nearest rank),
    /// `max_frame_ms` and `mean_frame_ms` by the clock; the same four by CPU time (`median_cpu_ms`, `p95_cpu_ms`,
    /// `max_cpu_ms`, `mean_cpu_ms`); and `frame_ms` and `frame_cpu_ms`, every frame in the order it came. All zero,
    /// and no frames, without frames.
    static func report(frames: [Frame]) -> [String: Any] {
        var report: [String: Any] = ["frames": frames.count]
        for (values, names) in [
            (frames.map(\.wall), ["median_frame_ms", "p95_frame_ms", "max_frame_ms", "mean_frame_ms", "frame_ms"]),
            (frames.map(\.cpu), ["median_cpu_ms", "p95_cpu_ms", "max_cpu_ms", "mean_cpu_ms", "frame_cpu_ms"]),
        ] {
            let sorted = values.sorted()
            report[names[0]] = sorted.isEmpty ? 0.0 : rounded(percentile(0.5, of: sorted))
            report[names[1]] = sorted.isEmpty ? 0.0 : rounded(percentile(0.95, of: sorted))
            report[names[2]] = sorted.last.map(rounded) ?? 0.0
            report[names[3]] = sorted.isEmpty ? 0.0 : rounded(values.reduce(0, +) / Double(values.count))
            report[names[4]] = values.map(rounded)
        }
        return report
    }

    /// The nearest-rank percentile `fraction` (0.5 is the median) of `sorted`, which must not be empty.
    private static func percentile(_ fraction: Double, of sorted: [Double]) -> Double {
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    /// The report as JSON, with sorted keys.
    static func reportData(frames: [Frame]) -> Data {
        (try? JSONSerialization.data(withJSONObject: report(frames: frames), options: [.sortedKeys]))
            ?? Data("{}".utf8)
    }

    private static func rounded(_ milliseconds: Double) -> Double {
        (milliseconds * 1000).rounded() / 1000
    }
}
