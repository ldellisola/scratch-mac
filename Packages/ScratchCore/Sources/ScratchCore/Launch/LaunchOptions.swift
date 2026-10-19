import Foundation

/// Which TextKit the editor uses. Task 10 of plan 1 decides between them, then removes this switch.
public enum TextKitMode: String, Sendable {
    case one = "1"
    case two = "2"
}

/// Forces the app's appearance, so a screenshot in light or dark mode does not depend on the machine's setting.
public enum AppearanceOverride: String, Sendable {
    case light
    case dark
}

/// Why the launch arguments were rejected. Each case carries the offending flag or value.
public enum LaunchOptionsError: Error, Equatable {
    case missingValue(String)
    case unknownFixture(String)
    case unknownTextKit(String)
    case unknownAppearance(String)
}

/// What the launch arguments ask for: where the data lives, and the switches that tests, screenshots and benchmarks
/// use to get reproducible runs (spec §9.4).
///
/// | Flag | Value |
/// |---|---|
/// | `-ScratchDataDir <path>` | the data directory |
/// | `-ScratchFixture <name>` | a ``Fixture`` raw value: the database is replaced by that fixture |
/// | `-ScratchTextKit <1\|2>` | the TextKit version |
/// | `-ScratchAppearance <light\|dark>` | the appearance |
/// | `-ScratchFrameMonitor <path>` | scroll the note by itself, and write the frame times to this JSON file (performance tests) |
public struct LaunchOptions: Equatable, Sendable {
    public var dataDirectory: URL
    /// False only for the real data directory. A fixture refuses to run when this is false (see ``ScratchStorage``).
    public var isIsolated: Bool
    public var fixture: Fixture?
    public var textKit: TextKitMode?
    public var appearance: AppearanceOverride?
    /// Where the app writes the frame times of a scroll that it does by itself, a few seconds after launch. Nil means
    /// it neither scrolls nor measures. A debug flag for the performance tests: the app has no other use for it.
    public var frameMonitorFile: URL?

    public init(
        dataDirectory: URL,
        isIsolated: Bool,
        fixture: Fixture? = nil,
        textKit: TextKitMode? = nil,
        appearance: AppearanceOverride? = nil,
        frameMonitorFile: URL? = nil
    ) {
        self.dataDirectory = dataDirectory
        self.isIsolated = isIsolated
        self.fixture = fixture
        self.textKit = textKit
        self.appearance = appearance
        self.frameMonitorFile = frameMonitorFile
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
        var textKit: TextKitMode?
        var appearance: AppearanceOverride?
        var frameMonitorPath: String?

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
            case .textKit:
                guard let parsed = TextKitMode(rawValue: value) else { throw LaunchOptionsError.unknownTextKit(value) }
                textKit = parsed
            case .appearance:
                guard let parsed = AppearanceOverride(rawValue: value) else {
                    throw LaunchOptionsError.unknownAppearance(value)
                }
                appearance = parsed
            case .frameMonitor:
                frameMonitorPath = value
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
            fixture: fixture, textKit: textKit, appearance: appearance,
            frameMonitorFile: frameMonitorPath.map { URL(fileURLWithPath: $0) })
    }

    private enum Flag: String {
        case dataDirectory = "-ScratchDataDir"
        case fixture = "-ScratchFixture"
        case textKit = "-ScratchTextKit"
        case appearance = "-ScratchAppearance"
        case frameMonitor = "-ScratchFrameMonitor"
    }

    /// The directory's path with `..`, trailing slashes and symbolic links resolved, so that no spelling of the real
    /// directory can pass for an isolated one.
    private static func identity(of directory: URL) -> String {
        directory.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
