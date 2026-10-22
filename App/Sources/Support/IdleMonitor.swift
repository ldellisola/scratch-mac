import AppKit
import Darwin

/// Measures how much CPU the app uses while it does nothing, and writes the numbers to a JSON file. A debug tool for the
/// performance tests, switched on by `-ScratchIdleMonitor <path>` (`LaunchOptions`); a normal launch never creates one.
///
/// The spec's idle budget (§7) is "no wake-ups or CPU use while idle": a scratchpad that sits in the background all day
/// must cost nothing. XCTest has no metric for it that works on a UI test's app, so the app measures itself:
///
/// - `warmUp` seconds after launch (the launch's own work, the launch log, the query warm-up and the first layout are done
///   by then, and they are the launch budget's business) it reads `getrusage(RUSAGE_SELF)`, the CPU time that every
///   thread of the process has used (user and system), and begins to count the passes of the main run loop that follow a
///   wait (`wakeups`: a pass is one wake-up of the main thread, by a timer, an event or a source).
/// - `duration` seconds later it reads both again and writes the report: `cpu_ms` (the CPU time used), `wall_ms` (the time
///   that passed, by the clock), `cpu_pct` (`cpu_ms` over `wall_ms`, as a percentage of one core) and `wakeups`.
///
/// It is a percentage and not a number of milliseconds because what an idle app does is a rate, and because the caret's
/// blink is a timer that the app does not own: AppKit runs it, and it is there whatever Scratch does (docs/decisions/0009).
/// The window is open and the caret is in the note, which is the state Scratch is in most of the day. The test that reads
/// the report asks the app nothing meanwhile: a question through the accessibility API is CPU time too.
///
/// The report is written once, atomically, and the test reads it as soon as it is there, like the frame monitor's
/// (`FrameMonitor`).
@MainActor
final class IdleMonitor {
    /// Seconds after launch before it measures, as long as the frame monitor's warm-up (the launch is long over by then).
    static let warmUp: TimeInterval = 3.5
    /// Seconds it measures for.
    static let duration: TimeInterval = 5

    private let file: URL
    private var observer: CFRunLoopObserver?
    private var wakeups = 0
    private var startedAt: UInt64 = 0
    private var startCPU = 0.0

    /// `file` is where the report goes.
    init(file: URL) {
        self.file = file
    }

    /// Starts the clock. Call it once, at the end of the launch.
    func start() {
        Timer.scheduledTimer(withTimeInterval: Self.warmUp, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginMeasuring() }
        }
    }

    // MARK: Measuring

    private func beginMeasuring() {
        wakeups = 0
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.afterWaiting.rawValue, true, RunLoopIdle.order
        ) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.wakeups += 1 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
        startedAt = DispatchTime.now().uptimeNanoseconds
        startCPU = Self.processCPUMilliseconds()
        Timer.scheduledTimer(withTimeInterval: Self.duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishMeasuring() }
        }
    }

    private func finishMeasuring() {
        let cpu = Self.processCPUMilliseconds() - startCPU
        let wall = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        let counted = wakeups
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        observer = nil
        do {
            try Self.reportData(cpuMilliseconds: cpu, wallMilliseconds: wall, wakeups: counted)
                .write(to: file, options: .atomic)
        } catch {
            let message = "Scratch: cannot write the idle report to \(file.path): \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    /// The CPU time that every thread of this process has used so far, user and system, in milliseconds.
    private static func processCPUMilliseconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return milliseconds(of: usage.ru_utime) + milliseconds(of: usage.ru_stime)
    }

    private static func milliseconds(of time: timeval) -> Double {
        Double(time.tv_sec) * 1000 + Double(time.tv_usec) / 1000
    }

    // MARK: The report

    /// The numbers of one measurement: `cpu_ms`, `wall_ms`, `cpu_pct` (the CPU time as a percentage of the time that
    /// passed: 100 is one core busy all the time, and 0 when no time passed) and `wakeups`, the first three rounded to
    /// microseconds, and `cpu_pct` to thousandths.
    static func report(cpuMilliseconds: Double, wallMilliseconds: Double, wakeups: Int) -> [String: Any] {
        let percentage = wallMilliseconds > 0 ? cpuMilliseconds / wallMilliseconds * 100 : 0
        return [
            "cpu_ms": rounded(cpuMilliseconds, to: 1000),
            "wall_ms": rounded(wallMilliseconds, to: 1000),
            "cpu_pct": rounded(percentage, to: 1000),
            "wakeups": wakeups,
        ]
    }

    /// The report as JSON, with sorted keys.
    static func reportData(cpuMilliseconds: Double, wallMilliseconds: Double, wakeups: Int) -> Data {
        let object = report(cpuMilliseconds: cpuMilliseconds, wallMilliseconds: wallMilliseconds, wakeups: wakeups)
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    private static func rounded(_ value: Double, to scale: Double) -> Double {
        (value * scale).rounded() / scale
    }
}
