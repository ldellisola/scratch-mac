import XCTest

/// Gives `Bundle(for:)` a class of the test bundle to ask about.
private final class PerfBundleToken {}

/// What the performance tests share. They drive the real app, like the UI tests do, always in a data directory of its
/// own (`UITestSupport.makeDataDirectory`).
@MainActor
enum PerfSupport {
    /// The metric of the app's signpost interval `name`: `keystroke` and `switch-note`. The subsystem and the category
    /// are those of `Signposts.editor` in the app.
    static func signpostMetric(named name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(subsystem: "io.github.ldellisola.Scratch", category: "editor", name: name)
    }

    /// Launches the app on `fixture`, seeded into `dataDirectory`, in light mode. `extraArguments` come last.
    static func launch(fixture: String, dataDirectory: URL, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-ScratchDataDir", dataDirectory.path,
                "-ScratchFixture", fixture,
                "-ScratchAppearance", "light",
            ] + extraArguments
        app.launch()
        return app
    }

    /// The folders above the test bundle, nearest first, each with `LaunchReference.app` in it: where `testReferenceLaunch`
    /// looks for the app that App/project.yml builds with this bundle, into the same products folder. The bundle is in the
    /// runner, `<products>/ScratchPerfTests-Runner.app/Contents/PlugIns/ScratchPerfTests.xctest`.
    static func referenceApplicationCandidates() -> [URL] {
        var candidates: [URL] = []
        var directory = Bundle(for: PerfBundleToken.self).bundleURL
        while directory.path != "/", !directory.path.isEmpty {
            directory = directory.deletingLastPathComponent()
            candidates.append(directory.appendingPathComponent("LaunchReference.app", isDirectory: true))
        }
        return candidates
    }

    /// The app to launch for `testReferenceLaunch`: the first candidate that is there, or, when none can be seen (the runner is
    /// sandboxed and may not be allowed to look), the one next to the runner app, where the build puts it.
    static func referenceApplicationURL() -> URL {
        let candidates = referenceApplicationCandidates()
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { return found }
        var directory = Bundle(for: PerfBundleToken.self).bundleURL
        while directory.path != "/", !directory.path.isEmpty {
            if directory.pathExtension == "app" {
                return directory.deletingLastPathComponent().appendingPathComponent(
                    "LaunchReference.app", isDirectory: true)
            }
            directory = directory.deletingLastPathComponent()
        }
        return candidates.first ?? URL(fileURLWithPath: "/LaunchReference.app")
    }

    /// Attaches a screenshot of the app's window to the test, kept even when the test passes, so that a person (or an
    /// agent that opens the PNG) can see what the test saw.
    static func attachScreenshot(of app: XCUIApplication, named name: String, to test: XCTestCase) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
