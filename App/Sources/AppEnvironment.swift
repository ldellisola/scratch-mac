import Foundation
import ScratchCore

/// What the app was launched with and the storage it opened: built once at launch and shared with the UI.
@MainActor
final class AppEnvironment {
    let options: LaunchOptions
    let storage: ScratchStorage

    init(options: LaunchOptions, storage: ScratchStorage) {
        self.options = options
        self.storage = storage
    }

    /// Reads the `-Scratch*` launch arguments and opens the data directory they name. With a fixture it first empties
    /// that directory and seeds the fixture, but only when the directory is not the real one (`ScratchStorage.open`).
    ///
    /// A hosted unit test runs inside this app, started by Xcode without `-ScratchDataDir`. That launch must not open
    /// the real data directory either (tests never touch real data), so under XCTest an app that was given neither
    /// flag gets an empty fixture in a throwaway directory.
    static func bootstrap(arguments: [String]) throws -> AppEnvironment {
        var arguments = arguments
        if isRunningUnderXCTest, !arguments.contains("-ScratchDataDir"), !arguments.contains("-ScratchFixture") {
            arguments += ["-ScratchFixture", "empty"]
        }
        let options = try LaunchOptions.parse(
            arguments, home: FileManager.default.homeDirectoryForCurrentUser,
            temporaryDirectory: FileManager.default.temporaryDirectory)
        let storage = try ScratchStorage.open(options)
        return AppEnvironment(options: options, storage: storage)
    }

    /// True in a process that XCTest has loaded its test bundle into, which is how a hosted unit test run starts the app.
    private static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
