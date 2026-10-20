import Foundation
import Testing

@testable import ScratchCore

// Spec §6.6: launching restores the previous session exactly, including open tabs, the active tab, and the
// cursor and scroll position in each tab. Spec §6.4: the font size is remembered.

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

@Test func decodesPlan1SessionWithDefaults() throws {
    let (store, db) = try sessionStore()
    let id = NoteID.make()
    // What Scratch 0.1.0 wrote: no `fontSize` in the session and no `scrollAnchor` in the tab.
    try storeRawState(
        #"{"tabs": [{"noteID": "\#(id.rawValue)", "selection": 6, "scrollY": 48.5}], "activeTabIndex": 0}"#, in: db)
    let state = try #require(try store.load())
    #expect(state.fontSize == 13)
    #expect(state.fontSize == FontSize.standard)
    #expect(state.tabs.first?.scrollAnchor == nil)
    #expect(state.tabs == [TabState(noteID: id, selection: 6, scrollY: 48.5)])
}

@Test func roundTripsFontSizeAndAnchor() throws {
    let (store, _) = try sessionStore()
    let state = SessionState(
        tabs: [
            TabState(noteID: NoteID.make(), selection: 12, scrollY: 0, scrollAnchor: 1_234),
            TabState(noteID: NoteID.make(), selection: 0, scrollY: 0, scrollAnchor: 0),
            TabState(noteID: NoteID.make(), selection: 3, scrollY: 8),
        ],
        activeTabIndex: 1,
        fontSize: 17)
    try store.save(state)
    let loaded = try #require(try store.load())
    #expect(loaded == state)
    #expect(loaded.fontSize == 17)
    #expect(loaded.tabs.map(\.scrollAnchor) == [1_234, 0, nil])
}

@Test func newFieldsHaveDefaultsInTheInitialisers() {
    let tab = TabState(noteID: NoteID.make(), selection: 1, scrollY: 2)
    #expect(tab.scrollAnchor == nil)
    #expect(SessionState(tabs: [tab], activeTabIndex: 0).fontSize == FontSize.standard)
}

@Test func decodesAnOutOfRangeFontSizeIntoRange() throws {
    let (store, db) = try sessionStore()
    for (stored, expected) in [("500", 32.0), ("0", 9.0), ("-3", 9.0), ("16.5", 16.5)] {
        try storeRawState(#"{"tabs": [], "fontSize": \#(stored)}"#, in: db)
        #expect(try store.load()?.fontSize == expected, "\(stored)")
    }
}
