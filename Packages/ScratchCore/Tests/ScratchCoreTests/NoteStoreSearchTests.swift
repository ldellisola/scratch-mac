import Foundation
import Testing

@testable import ScratchCore

// Spec §6.2: a search field at the top of the sidebar filters the list live, matching titles and note text across all
// notes. Plan 2, Review Focus 3: whatever is typed, search never errors and matches the words literally.

private func date(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds) }

/// Runs `body` on a store backed by a temporary database file, which is removed afterwards.
private func withTemporaryStore(_ body: (NoteStore, Database) throws -> Void) throws {
    let file = "scratch-search-\(UUID().uuidString).sqlite"
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(file).path
    defer {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
    }
    let database = try Database(path: path)
    try body(try NoteStore(database: database), database)
}

@discardableResult
private func add(_ store: NoteStore, title: String = "", body: String = "", at seconds: Double = 0) throws -> Note {
    var note = try store.create(now: date(seconds))
    note.title = title
    note.body = body
    try store.save(note)
    return note
}

private func ids(_ summaries: [NoteSummary]) -> [NoteID] { summaries.map(\.id) }

@Test func findsWordsInTitle() throws {
    try withTemporaryStore { store, _ in
        let note = try add(store, title: "Deploy checklist", body: "nothing else")
        try add(store, body: "unrelated")
        #expect(ids(try store.search("checklist")) == [note.id])
    }
}

@Test func findsWordsInBody() throws {
    try withTemporaryStore { store, _ in
        let note = try add(store, title: "Notes", body: "restart the ingress controller\nthen wait")
        try add(store, body: "unrelated")
        #expect(ids(try store.search("ingress")) == [note.id])
        #expect(ids(try store.search("wait")) == [note.id])
    }
}

@Test func matchesPrefixes() throws {
    try withTemporaryStore { store, _ in
        let note = try add(store, body: "run kubectl apply")
        #expect(ids(try store.search("kube")) == [note.id])
        #expect(ids(try store.search("kubectl")) == [note.id])
        #expect(try store.search("ubectl").isEmpty)  // a prefix, not a substring
    }
}

@Test func requiresEveryWord() throws {
    try withTemporaryStore { store, _ in
        let both = try add(store, body: "kubectl rollout status")
        try add(store, body: "kubectl get pods")
        try add(store, body: "rollout plan")
        #expect(ids(try store.search("kube roll")) == [both.id])
        #expect(ids(try store.search("roll kube")) == [both.id])  // in any order
    }
}

@Test func findsOneWordInTheTitleAndAnotherInTheBody() throws {
    try withTemporaryStore { store, _ in
        let note = try add(store, title: "Groceries", body: "oat milk")
        #expect(ids(try store.search("grocer milk")) == [note.id])
    }
}

@Test func isCaseAndDiacriticInsensitive() throws {
    try withTemporaryStore { store, _ in
        let note = try add(store, body: "Meet at the Café")
        #expect(ids(try store.search("cafe")) == [note.id])
        #expect(ids(try store.search("CAFÉ")) == [note.id])
        #expect(ids(try store.search("MEET")) == [note.id])
    }
}

@Test func excludesDeletedNotes() throws {
    try withTemporaryStore { store, database in
        let kept = try add(store, body: "shared word kept")
        let deleted = try add(store, body: "shared word deleted")
        try database.execute(
            "UPDATE notes SET deleted_at = ? WHERE id = ?", [.date(date(5)), .text(deleted.id.rawValue)])
        #expect(ids(try store.search("shared")) == [kept.id])
        #expect(try store.search("deleted").isEmpty)
    }
}

@Test func followsEdits() throws {
    try withTemporaryStore { store, _ in
        var note = try add(store, title: "Plan", body: "alpha beta")
        #expect(ids(try store.search("alpha")) == [note.id])
        note.body = "gamma beta"
        try store.save(note)
        #expect(try store.search("alpha").isEmpty)
        #expect(ids(try store.search("gamma")) == [note.id])
        #expect(ids(try store.search("beta")) == [note.id])
        note.title = "Roadmap"
        try store.save(note)
        #expect(try store.search("plan").isEmpty)
        #expect(ids(try store.search("roadmap")) == [note.id])
    }
}

@Test func discardRemovesTheNoteFromTheIndex() throws {
    try withTemporaryStore { store, database in
        let note = try add(store, body: "ephemeral words")
        #expect(ids(try store.search("ephemeral")) == [note.id])
        try store.discard(note.id)
        #expect(try store.search("ephemeral").isEmpty)
        // The index agrees with the table after inserts, updates and a delete.
        try database.execute("INSERT INTO notes_fts(notes_fts, rank) VALUES ('integrity-check', 1)")
    }
}

@Test func indexStaysConsistentWithTheTable() throws {
    try withTemporaryStore { store, database in
        var notes: [Note] = []
        for index in 0..<20 {
            notes.append(try add(store, title: "T\(index)", body: "body \(index) word", at: Double(index)))
        }
        for index in stride(from: 0, to: 20, by: 2) {
            notes[index].body = "changed \(index)"
            try store.save(notes[index])
        }
        try store.saveAll(
            notes.suffix(5).map { note in
                var copy = note
                copy.title = "again"
                return copy
            })
        for note in notes.prefix(3) { try store.discard(note.id) }
        try database.execute("INSERT INTO notes_fts(notes_fts, rank) VALUES ('integrity-check', 1)")
    }
}

@Test func savingWithTheSameTextKeepsTheNoteFindable() throws {
    try withTemporaryStore { store, _ in
        let note = try add(store, title: "Same", body: "unchanging")
        try store.save(note)
        try store.save(note)
        #expect(ids(try store.search("unchanging")) == [note.id])
        #expect(ids(try store.search("same")) == [note.id])
    }
}

@Test func blankSearchReturnsAllSummaries() throws {
    try withTemporaryStore { store, _ in
        try add(store, body: "one", at: 1)
        try add(store, body: "two", at: 2)
        let all = try store.summaries()
        #expect(all.count == 2)
        #expect(try store.search("") == all)
        #expect(try store.search("   ") == all)
        #expect(try store.search("-- ( *") == all)  // nothing left to match, so nothing is filtered
        #expect(try store.search("😀") == all)
    }
}

@Test func resultsAreOrderedLikeTheSidebar() throws {
    try withTemporaryStore { store, _ in
        let old = try add(store, body: "match old", at: 1)
        let recent = try add(store, body: "match recent", at: 3)
        var pinned = try add(store, body: "match pinned", at: 0)
        pinned.pinnedAt = date(9)
        try store.save(pinned)
        #expect(ids(try store.search("match")) == [pinned.id, recent.id, old.id])
        #expect(try store.search("match") == (try store.summaries()))
    }
}

@Test func searchResultsCarryTheSidebarColumns() throws {
    try withTemporaryStore { store, _ in
        let note = try add(store, title: "Deploy", body: "first line\nsecond line", at: 7)
        let result = try #require(try store.search("second").first)
        #expect(result.id == note.id)
        #expect(result.displayTitle == note.displayTitle && result.hasTitle)
        #expect(result.preview == note.preview)
        #expect(result.modifiedAt == note.modifiedAt)
    }
}

@Test func searchToleratesQuerySyntax() throws {
    try withTemporaryStore { store, _ in
        let note = try add(store, body: "salt and pepper")
        try add(store, body: "or else")
        let inputs = [
            "\"", "*", "-x", "(a", "NEAR(a b)", "a AND", "OR", "AND", "NOT", "😀", "\"unbalanced", "a\"b", "title:x",
            "body: y", "^a", "a +b", "{a}", "a*", "'", "\\", ";", "--", "a OR", "(", ")", ":", "x:", "NEAR/2",
            "a\u{0}\"b", "\u{0}", "ā", "e\u{301}", "\u{FFFD}",
        ]
        for input in inputs {
            do {
                _ = try store.search(input)
            } catch {
                Issue.record("search(\(input.debugDescription)) threw \(error)")
            }
        }
        // FTS5 keywords are only words here.
        #expect(ids(try store.search("AND")) == [note.id])
        #expect(ids(try store.search("salt AND pepper")) == [note.id])
        #expect(try store.search("OR").count == 1)
        #expect(ids(try store.search("OR")) != [note.id])
    }
}

@Test func searchMatchesTextThatLooksLikeSyntaxLiterally() throws {
    try withTemporaryStore { store, _ in
        let note = try add(store, body: "the quote \"hi\" and a star*")
        #expect(ids(try store.search("\"hi")) == [note.id])
        #expect(ids(try store.search("star*")) == [note.id])
        #expect(try store.search("-hi star").count == 1)
    }
}

@Test func searchToleratesEveryUnicodeScalarOnItsOwn() throws {
    try withTemporaryStore { store, _ in
        try add(store, body: "anything")
        for value in UInt32(1)..<0x3_0000 {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let text = String(Character(scalar))
            guard SearchQuery.ftsExpression(text) != nil else { continue }  // only these ever reach FTS5
            do { _ = try store.search(text) } catch {
                Issue.record("search(U+\(String(value, radix: 16))) threw \(error)")
                return
            }
        }
    }
}
