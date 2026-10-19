import Foundation
import Testing

@testable import ScratchCore

// Spec §9.4 (fixtures) and the data rules: tests never touch real data, and a fixture only ever replaces the
// contents of an isolated directory.

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ScratchStorageTests-\(UUID().uuidString)")
}

private func options(
    directory: URL, isolated: Bool = true, fixture: Fixture? = nil
) -> LaunchOptions {
    LaunchOptions(dataDirectory: directory, isIsolated: isolated, fixture: fixture)
}

private func fileNames(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

@Test func openCreatesDirectoryAndDatabase() throws {
    let directory = temporaryDirectory().appendingPathComponent("nested/deeper")
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent().deletingLastPathComponent()) }
    let storage = try ScratchStorage.open(options(directory: directory))
    #expect(storage.directory == directory)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("scratch.sqlite").path))
    #expect(ScratchStorage.databaseFileName == "scratch.sqlite")
    #expect(try storage.notes.summaries().isEmpty)
    #expect(try storage.session.load() == nil)
}

@Test func notesAndSessionPersistAcrossOpens() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let created: Note
    do {
        let storage = try ScratchStorage.open(options(directory: directory))
        created = try storage.notes.create(now: Date(timeIntervalSinceReferenceDate: 1000))
        try storage.session.save(
            SessionState(tabs: [TabState(noteID: created.id, selection: 0, scrollY: 0)], activeTabIndex: 0))
    }
    let reopened = try ScratchStorage.open(options(directory: directory))
    #expect(try reopened.notes.note(created.id) == created)
    #expect(try reopened.session.load()?.tabs.first?.noteID == created.id)
}

@Test func openWithoutFixtureKeepsExistingData() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let storage = try ScratchStorage.open(options(directory: directory, fixture: .typical))
        #expect(try storage.notes.summaries().count == 6)
    }
    let storage = try ScratchStorage.open(options(directory: directory))
    #expect(try storage.notes.summaries().count == 6)
    #expect(try storage.session.load()?.tabs.count == 2)
}

@Test func openSeedsTheFixture() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let storage = try ScratchStorage.open(options(directory: directory, fixture: .typical), now: now)
    let summaries = try storage.notes.summaries()
    #expect(summaries.count == 6)
    #expect(summaries[1].modifiedAt == now.addingTimeInterval(-3600))
    #expect(try storage.session.load()?.tabs.count == 2)
}

@Test func fixtureReplacesExistingData() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let typical = try ScratchStorage.open(options(directory: directory, fixture: .typical))
        #expect(try typical.notes.summaries().count == 6)
    }
    let empty = try ScratchStorage.open(options(directory: directory, fixture: .empty))
    #expect(try empty.notes.summaries().count == 0)
    #expect(try empty.session.load() == nil)
}

@Test func fixtureLeavesOnlyTheNewDatabaseFilesBehind() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    do { _ = try ScratchStorage.open(options(directory: directory, fixture: .typical)) }
    let stale = directory.appendingPathComponent("scratch.sqlite-journal")
    try Data("stale".utf8).write(to: stale)
    let unrelated = directory.appendingPathComponent("notes-export.txt")
    try Data("keep".utf8).write(to: unrelated)

    _ = try ScratchStorage.open(options(directory: directory, fixture: .empty))
    #expect(!FileManager.default.fileExists(atPath: stale.path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
    #expect(try fileNames(in: directory).filter { $0.hasPrefix("scratch.sqlite") }.contains("scratch.sqlite"))
}

@Test func fixtureOnRealDirectoryIsRefused() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let real = options(directory: directory, isolated: false, fixture: .typical)
    #expect(throws: StorageError.fixtureRequiresIsolatedDirectory) { try ScratchStorage.open(real) }
    // Refused before anything happened to the directory.
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test func realDirectoryWithoutFixtureOpens() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try ScratchStorage.open(options(directory: directory, isolated: false))
    #expect(try storage.notes.summaries().isEmpty)
}

@Test func fixtureRunsInTheSystemTemporaryDirectory() throws {
    // Launch arguments as the UI tests pass them, resolved against the real home and the real temporary directory.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ScratchStorageTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let parsed = try LaunchOptions.parse(
        ["-ScratchDataDir", directory.path, "-ScratchFixture", "typical"],
        home: FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: FileManager.default.temporaryDirectory)
    #expect(parsed.isIsolated)
    let storage = try ScratchStorage.open(parsed)
    #expect(try storage.notes.summaries().count == 6)
}
