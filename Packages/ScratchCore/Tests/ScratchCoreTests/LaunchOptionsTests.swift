import Foundation
import Testing

@testable import ScratchCore

// Spec §9.4 (fixtures): launch arguments choose the data directory and a named fixture, so UI tests, screenshots and
// benchmarks never touch real data.

private let home = URL(fileURLWithPath: "/Users/tester")
private let temporaryDirectory = URL(fileURLWithPath: "/tmp/scratch-tests")

private func parse(_ arguments: [String]) throws -> LaunchOptions {
    try LaunchOptions.parse(arguments, home: home, temporaryDirectory: temporaryDirectory)
}

@Test func defaultsToApplicationSupport() throws {
    let options = try parse([])
    #expect(options.dataDirectory == LaunchOptions.defaultDataDirectory(home: home))
    #expect(options.dataDirectory.path == "/Users/tester/Library/Application Support/Scratch")
    #expect(options.isIsolated == false)
    #expect(options.fixture == nil)
    #expect(options.appearance == nil)
    #expect(options.frameMonitorFile == nil)
}

@Test func dataDirFlagOverridesAndIsolates() throws {
    let options = try parse(["-ScratchDataDir", "/tmp/scratch-ui-1"])
    #expect(options.dataDirectory == URL(fileURLWithPath: "/tmp/scratch-ui-1"))
    #expect(options.isIsolated == true)
    #expect(options.fixture == nil)
}

@Test func dataDirFlagNamingTheDefaultDirectoryIsNotIsolated() throws {
    // A trailing slash and a ".." must not make the real directory look isolated.
    for path in [
        "/Users/tester/Library/Application Support/Scratch",
        "/Users/tester/Library/Application Support/Scratch/",
        "/Users/tester/Library/Application Support/../Application Support/Scratch",
    ] {
        let options = try parse(["-ScratchDataDir", path])
        #expect(options.isIsolated == false, "\(path)")
    }
}

@Test func fixtureWithoutDataDirUsesFreshTemporaryDirectory() throws {
    let first = try parse(["-ScratchFixture", "typical"])
    let second = try parse(["-ScratchFixture", "typical"])
    #expect(first.fixture == .typical)
    #expect(first.isIsolated == true)
    #expect(first.dataDirectory.path.hasPrefix(temporaryDirectory.path + "/Scratch-"))
    #expect(first.dataDirectory != second.dataDirectory)
}

@Test func fixtureWithDataDirKeepsTheGivenDirectory() throws {
    let options = try parse(["-ScratchFixture", "huge-note", "-ScratchDataDir", "/tmp/keep"])
    #expect(options.fixture == .hugeNote)
    #expect(options.dataDirectory == URL(fileURLWithPath: "/tmp/keep"))
    #expect(options.isIsolated == true)
}

@Test func parsesEveryFixtureName() throws {
    for fixture in Fixture.allCases {
        #expect(try parse(["-ScratchFixture", fixture.rawValue]).fixture == fixture)
    }
    #expect(
        Fixture.allCases.map(\.rawValue) == [
            "empty", "typical", "huge-note", "many-notes", "recently-deleted", "formatting",
        ])
}

@Test func parsesAppearance() throws {
    #expect(try parse(["-ScratchAppearance", "dark"]).appearance == .dark)
    #expect(try parse(["-ScratchAppearance", "light"]).appearance == .light)
}

// ADR 0001 chose TextKit 1 and removed the switch: the flag is an unrelated argument now, even with a value that was
// invalid, and it does not hide a flag that follows it.
@Test func theRemovedTextKitFlagIsIgnored() throws {
    #expect(try parse(["-ScratchTextKit", "3"]) == (try parse([])))
    #expect(try parse(["-ScratchTextKit", "2", "-ScratchAppearance", "dark"]).appearance == .dark)
}

@Test func parsesFrameMonitorFile() throws {
    let options = try parse(["-ScratchFrameMonitor", "/tmp/scratch-frames.json", "-ScratchFixture", "huge-note"])
    #expect(options.frameMonitorFile == URL(fileURLWithPath: "/tmp/scratch-frames.json"))
    #expect(options.fixture == .hugeNote)
}

@Test func lastOccurrenceOfAFlagWins() throws {
    let options = try parse(["-ScratchAppearance", "dark", "-ScratchAppearance", "light"])
    #expect(options.appearance == .light)
}

@Test func unknownFixtureThrows() {
    #expect(throws: LaunchOptionsError.unknownFixture("nope")) { try parse(["-ScratchFixture", "nope"]) }
}

@Test func unknownAppearanceThrows() {
    #expect(throws: LaunchOptionsError.unknownAppearance("sepia")) { try parse(["-ScratchAppearance", "sepia"]) }
}

@Test func missingValueThrows() {
    #expect(throws: LaunchOptionsError.missingValue("-ScratchDataDir")) { try parse(["-ScratchDataDir"]) }
    #expect(throws: LaunchOptionsError.missingValue("-ScratchFixture")) { try parse(["-ScratchFixture"]) }
    #expect(throws: LaunchOptionsError.missingValue("-ScratchFrameMonitor")) { try parse(["-ScratchFrameMonitor"]) }
}

@Test func aFlagFollowedByAnotherFlagHasNoValue() {
    #expect(throws: LaunchOptionsError.missingValue("-ScratchDataDir")) {
        try parse(["-ScratchDataDir", "-ScratchFixture", "typical"])
    }
}

@Test func ignoresUnrelatedArguments() throws {
    let options = try parse([
        "/Applications/Scratch.app/Contents/MacOS/Scratch", "-NSDocumentRevisionsDebugMode", "YES",
    ])
    #expect(options == (try parse([])))
}

@Test func unrelatedArgumentsDoNotHideScratchFlags() throws {
    let options = try parse([
        "-NSDocumentRevisionsDebugMode", "YES", "-ScratchAppearance", "dark", "-AppleLanguages", "(en)",
    ])
    #expect(options.appearance == .dark)
}

// The system temporary directory is what UI tests and fixtures use. On macOS it is under /var/folders, and /var is a
// symbolic link to /private/var, so this is the case that must not be mistaken for the real data directory.
@Test func systemTemporaryDirectoryIsIsolatedInEverySpelling() throws {
    let realHome = FileManager.default.homeDirectoryForCurrentUser
    let temporary = FileManager.default.temporaryDirectory
    let resolved = temporary.resolvingSymlinksInPath()
    for directory in [temporary, resolved] {
        let named = directory.appendingPathComponent("ScratchUITests-\(UUID().uuidString)")
        let explicit = try LaunchOptions.parse(
            ["-ScratchDataDir", named.path], home: realHome, temporaryDirectory: temporary)
        #expect(explicit.isIsolated, "\(named.path)")
        #expect(explicit.dataDirectory.path == named.path)
    }
    let seeded = try LaunchOptions.parse(["-ScratchFixture", "typical"], home: realHome, temporaryDirectory: temporary)
    #expect(seeded.isIsolated, "\(seeded.dataDirectory.path)")
}
