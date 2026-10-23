import Foundation

/// How long one launch of Scratch took, as the app wrote it down (`LaunchLog`): when it was, which version, when the Mac
/// started, and how far into the process each phase of the launch was.
///
/// The phases are `main` (`main.swift` begins), `storage` (the storage is open), `restore` (the session is restored),
/// `window` (the window is shown) and `firstFrame` (the main run loop was next idle after the window was shown: the
/// note is on screen and accepts keystrokes). Each value is milliseconds from the start of the process, which is what
/// the spec's launch budgets measure (§7). docs/features/launch-times.md.
public struct LaunchRecord: Codable, Equatable, Sendable {
    /// When the launch reached its first frame.
    public var date: Date
    /// The app's version, for example `1.0.0`.
    public var version: String
    /// When the Mac started. Two records with the same boot time are launches in the same session of the Mac.
    public var bootTime: Date
    /// Milliseconds from the process start to each phase: "main", "storage", "restore", "window" and "firstFrame".
    public var phases: [String: Double]
    /// True for the first launch after the Mac started: its files are not in the disk cache yet, so it is the slow one
    /// (the spec's cold-boot budget, §7). Set by ``LaunchLog/append(_:)``.
    public var isFirstAfterStartUp: Bool

    /// The launch's time, from the process start until the note was on screen: the `firstFrame` phase, or 0 for a record
    /// that has none.
    public var totalMilliseconds: Double { phases["firstFrame"] ?? 0 }

    public init(
        date: Date, version: String, bootTime: Date, phases: [String: Double], isFirstAfterStartUp: Bool
    ) {
        self.date = date
        self.version = version
        self.bootTime = bootTime
        self.phases = phases
        self.isFirstAfterStartUp = isFirstAfterStartUp
    }
}
