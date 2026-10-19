import Foundation
import Testing

@testable import ScratchCore

// Spec §6.6: launching restores the previous session exactly, including open tabs, the active tab, and the
// cursor and scroll position in each tab.

private func sessionStore() throws -> (SessionStore, Database) {
    let db = try Database(path: ":memory:")
    return (try SessionStore(database: db), db)
}

private func storeRawState(_ json: String, in db: Database) throws {
    try db.execute(
        "INSERT OR REPLACE INTO session (key, value) VALUES ('state', ?)", [.blob(Array(json.utf8))])
}

@Test func loadReturnsNilWhenAbsent() throws {
    let (store, _) = try sessionStore()
    #expect(try store.load() == nil)
}

@Test func roundTrips() throws {
    let (store, _) = try sessionStore()
    let state = SessionState(
        tabs: [
            TabState(noteID: NoteID.make(), selection: 12, scrollY: 340.5),
            TabState(noteID: NoteID.make(), selection: 0, scrollY: 0),
        ],
        activeTabIndex: 1)
    try store.save(state)
    #expect(try store.load() == state)
}

@Test func saveReplacesThePreviousState() throws {
    let (store, db) = try sessionStore()
    let first = SessionState(tabs: [TabState(noteID: NoteID.make(), selection: 1, scrollY: 2)], activeTabIndex: 0)
    let second = SessionState(tabs: [], activeTabIndex: 0)
    try store.save(first)
    try store.save(second)
    #expect(try store.load() == second)
    #expect(try db.query("SELECT COUNT(*) AS n FROM session").first?.int("n") == 1)
}

@Test func stateSurvivesReopeningTheStore() throws {
    let db = try Database(path: ":memory:")
    let state = SessionState(tabs: [TabState(noteID: NoteID.make(), selection: 5, scrollY: 9)], activeTabIndex: 0)
    try SessionStore(database: db).save(state)
    #expect(try SessionStore(database: db).load() == state)
}

@Test func decodesStateWrittenWithExtraKeys() throws {
    let (store, db) = try sessionStore()
    let id = NoteID.make()
    try storeRawState(
        """
        {"future": 1, "tabs": [{"noteID": "\(id.rawValue)", "selection": 4, "scrollY": 2.5, "pinned": true}],
         "activeTabIndex": 0, "sidebar": {"width": 240}}
        """, in: db)
    #expect(
        try store.load()
            == SessionState(tabs: [TabState(noteID: id, selection: 4, scrollY: 2.5)], activeTabIndex: 0))
}

@Test func decodesStateWrittenWithoutKeysAddedLater() throws {
    let (store, db) = try sessionStore()
    let id = NoteID.make()
    try storeRawState(#"{"tabs": [{"noteID": "\#(id.rawValue)"}]}"#, in: db)
    #expect(
        try store.load()
            == SessionState(tabs: [TabState(noteID: id, selection: 0, scrollY: 0)], activeTabIndex: 0))
}

@Test func loadReturnsNilForUndecodableState() throws {
    let (store, db) = try sessionStore()
    for json in ["not json", "{}", #"{"tabs": "nope"}"#, #"{"tabs": [{"selection": 1}]}"#] {
        try storeRawState(json, in: db)
        #expect(try store.load() == nil, "\(json)")
    }
}

@Test func loadReadsStateStoredAsText() throws {
    let (store, db) = try sessionStore()
    try db.execute("INSERT INTO session (key, value) VALUES ('state', ?)", [.text(#"{"tabs": []}"#)])
    #expect(try store.load() == SessionState(tabs: [], activeTabIndex: 0))
}
