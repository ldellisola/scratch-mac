import Foundation

/// Forces the app's appearance, so a screenshot in light or dark mode does not depend on the machine's setting. The two
/// `-contrast` ones are light and dark with Increase Contrast on: the app forces light or dark, and the high contrast
/// variants of its colours (`CatalogColour`), for the screenshots that show them (plan 6 task 8).
public enum AppearanceOverride: String, CaseIterable, Sendable {
    case light
    case dark
    case lightContrast = "light-contrast"
    case darkContrast = "dark-contrast"

    /// True for the two dark appearances.
    public var isDark: Bool { self == .dark || self == .darkContrast }

    /// True for the two appearances with Increase Contrast on.
    public var isHighContrast: Bool { self == .lightContrast || self == .darkContrast }
}

/// Why the launch arguments were rejected. Each case carries the offending flag or value.
public enum LaunchOptionsError: Error, Equatable {
    case missingValue(String)
    case unknownFixture(String)
    case unknownAppearance(String)
}

/// What the launch arguments ask for: where the data lives, and the switches that tests, screenshots and benchmarks
/// use to get reproducible runs (spec §9.4).
///
/// | Flag | Value |
/// |---|---|
/// | `-ScratchDataDir <path>` | the data directory |
/// | `-ScratchFixture <name>` | a ``Fixture`` raw value: the database is replaced by that fixture |
/// | `-ScratchAppearance <light\|dark\|light-contrast\|dark-contrast>` | the appearance |
/// | `-ScratchFrameMonitor <path>` | scroll the note by itself, and write the frame times to this JSON file (performance tests) |
/// | `-ScratchIdleMonitor <path>` | measure the app's CPU over 5 seconds of idle, and write the numbers to this JSON file (performance tests) |
public struct LaunchOptions: Equatable, Sendable {
    public var dataDirectory: URL
    /// False only for the real data directory. A fixture refuses to run when this is false (see ``ScratchStorage``).
    public var isIsolated: Bool
    public var fixture: Fixture?
    public var appearance: AppearanceOverride?
    /// Where the app writes the frame times of a scroll that it does by itself, a few seconds after launch. Nil means
    /// it neither scrolls nor measures. A debug flag for the performance tests: the app has no other use for it.
    public var frameMonitorFile: URL?
    /// Where the app writes how much CPU it used while it did nothing, a few seconds after launch (`IdleMonitor`: ADR 0009).
    /// Nil means it does not measure. Another debug flag for the performance tests.
    public var idleMonitorFile: URL?

    public init(
        dataDirectory: URL,
        isIsolated: Bool,
        fixture: Fixture? = nil,
        appearance: AppearanceOverride? = nil,
        frameMonitorFile: URL? = nil,
        idleMonitorFile: URL? = nil
    ) {
        self.dataDirectory = dataDirectory
        self.isIsolated = isIsolated
        self.fixture = fixture
        self.appearance = appearance
        self.frameMonitorFile = frameMonitorFile
        self.idleMonitorFile = idleMonitorFile
    }

    /// `~/Library/Application Support/Scratch`, the real data directory.
    public static func defaultDataDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Scratch", isDirectory: true)
    }

    /// Reads the flags in the table above and ignores every other argument, because Xcode and AppKit add their own.
    ///
    /// A flag needs a value: the argument after it. A flag that is last, or is followed by another Scratch flag or an
    /// empty argument, throws ``LaunchOptionsError/missingValue(_:)``. When a flag is repeated the last one wins.
    ///
    /// A fixture without `-ScratchDataDir` gets a new directory `Scratch-<uuid>` inside `temporaryDirectory`, so it can
    /// never reach real data.
    public static func parse(_ arguments: [String], home: URL, temporaryDirectory: URL) throws -> LaunchOptions {
        var dataDirectoryPath: String?
        var fixture: Fixture?
        var appearance: AppearanceOverride?
        var frameMonitorPath: String?
        var idleMonitorPath: String?

        var index = arguments.startIndex
        while index < arguments.endIndex {
            guard let flag = Flag(rawValue: arguments[index]) else {
                index += 1
                continue
            }
            let valueIndex = index + 1
            guard valueIndex < arguments.endIndex, Flag(rawValue: arguments[valueIndex]) == nil,
                !arguments[valueIndex].isEmpty
            else { throw LaunchOptionsError.missingValue(flag.rawValue) }
            let value = arguments[valueIndex]
            index = valueIndex + 1

            switch flag {
            case .dataDirectory:
                dataDirectoryPath = value
            case .fixture:
                guard let parsed = Fixture(rawValue: value) else { throw LaunchOptionsError.unknownFixture(value) }
                fixture = parsed
            case .appearance:
                guard let parsed = AppearanceOverride(rawValue: value) else {
                    throw LaunchOptionsError.unknownAppearance(value)
                }
                appearance = parsed
            case .frameMonitor:
                frameMonitorPath = value
            case .idleMonitor:
                idleMonitorPath = value
            }
        }

        let defaultDirectory = defaultDataDirectory(home: home)
        let directory: URL
        if let dataDirectoryPath {
            directory = URL(fileURLWithPath: dataDirectoryPath)
        } else if fixture != nil {
            directory = temporaryDirectory.appendingPathComponent("Scratch-\(UUID().uuidString)", isDirectory: true)
        } else {
            directory = defaultDirectory
        }
        return LaunchOptions(
            dataDirectory: directory, isIsolated: identity(of: directory) != identity(of: defaultDirectory),
            fixture: fixture, appearance: appearance,
            frameMonitorFile: frameMonitorPath.map { URL(fileURLWithPath: $0) },
            idleMonitorFile: idleMonitorPath.map { URL(fileURLWithPath: $0) })
    }

    private enum Flag: String {
        case dataDirectory = "-ScratchDataDir"
        case fixture = "-ScratchFixture"
        case appearance = "-ScratchAppearance"
        case frameMonitor = "-ScratchFrameMonitor"
        case idleMonitor = "-ScratchIdleMonitor"
    }

    /// The directory's path with `..`, trailing slashes and symbolic links resolved, so that no spelling of the real
    /// directory can pass for an isolated one.
    private static func identity(of directory: URL) -> String {
        directory.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
