import Foundation

/// The notes and the saved session that one ``Fixture`` seeds.
struct FixtureContent {
    var notes: [Note]
    var session: SessionState?

    static func make(_ fixture: Fixture, now: Date) -> FixtureContent {
        switch fixture {
        case .empty: FixtureContent(notes: [], session: nil)
        case .typical: typical(now: now)
        case .hugeNote: hugeNote(now: now)
        case .manyNotes: manyNotes(now: now)
        }
    }

    // MARK: Typical

    /// The six notes of the mockup's sidebar. "Deploy checklist" and the curl note are open.
    private static func typical(now: Date) -> FixtureContent {
        let hour: TimeInterval = 3600
        let day = 24 * hour
        let deploy = note(
            "Deploy checklist", deployChecklistBody, editedAt: now.addingTimeInterval(-hour))
        let curl = note(
            "",
            [
                #"curl -X POST https://api.local/v1/notes \"#,
                #"  -H "Content-Type: application/json" \"#,
                #"  -d '{"title": "hello"}'"#,
            ].joined(separator: "\n"),
            editedAt: now.addingTimeInterval(-2 * hour))
        let notes = [
            note(
                "Snippets I keep reusing",
                [
                    "git log --oneline --graph --all",
                    "git rebase -i HEAD~5",
                    "docker ps --format '{{.Names}}'",
                ].joined(separator: "\n"),
                editedAt: now.addingTimeInterval(-7 * day), pinned: true),
            deploy,
            curl,
            note(
                "Standup",
                ["review PR for the auth fix", "pair with Sam on the import bug", "blockers: none"]
                    .joined(separator: "\n"),
                editedAt: now.addingTimeInterval(-day)),
            note(
                "",
                "SELECT region, sum(volume)\nFROM production GROUP BY region",
                editedAt: now.addingTimeInterval(-day - 3 * hour)),
            note("Groceries", "milk, eggs, coffee beans", editedAt: now.addingTimeInterval(-5 * day)),
        ]
        let session = SessionState(tabs: [tab(on: deploy), tab(on: curl)], activeTabIndex: 0)
        return FixtureContent(notes: notes, session: session)
    }

    /// The mockup's note: tasks, bullets, bold, inline code and a fenced block.
    private static let deployChecklistBody = [
        "[ ] bump version to `2.4.1`",
        "[x] run migrations on staging",
        "[ ] tag the release",
        "",
        "- check error rate in grafana after rollout",
        "- **don't deploy after 4pm on fridays**",
        "",
        "```bash",
        "# watch the rollout",
        "kubectl rollout status deploy/api -n prod",
        #"kubectl logs -l app=api --since=10m | grep -i "error""#,
        "```",
    ].joined(separator: "\n")

    // MARK: Huge note

    private static let hugeLineCount = 10_000
    private static let hugeBlockLength = 50

    /// "Huge" has exactly 10,000 lines. "Small" has 10. The session shows "Huge".
    private static func hugeNote(now: Date) -> FixtureContent {
        let small = note(
            "Small", (1...10).map { "Line \($0) of the small note." }.joined(separator: "\n"),
            editedAt: now.addingTimeInterval(-60))
        let huge = note("Huge", hugeBody(), editedAt: now)
        return FixtureContent(notes: [small, huge], session: SessionState(tabs: [tab(on: huge)], activeTabIndex: 0))
    }

    /// 200 blocks of 50 lines, alternating prose and a fenced `swift` block. The opening and closing fences count
    /// as lines of the block. The text has no trailing newline.
    private static func hugeBody() -> String {
        var lines: [String] = []
        lines.reserveCapacity(hugeLineCount)
        for block in 0..<(hugeLineCount / hugeBlockLength) {
            if block.isMultiple(of: 2) {
                lines.append(contentsOf: proseBlock(block))
            } else {
                lines.append(contentsOf: codeBlock(block))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static let sentences = [
        "The scratchpad keeps every line it is given, and never asks to save.",
        "Open notes come back exactly as they were left, cursor and scroll position included.",
        "Pasted text takes the note's font, so a page copied from a browser looks like everything else.",
        "Copying always puts plain text on the pasteboard, whatever the note shows.",
        "A long note must scroll smoothly and switch in a few milliseconds.",
    ]

    private static func proseBlock(_ block: Int) -> [String] {
        (0..<hugeBlockLength).map { line in
            // Every fifth line is blank, which makes paragraphs.
            if line % 5 == 4 { return "" }
            let sentence = sentences[(block + line) % sentences.count]
            return "Paragraph \(block / 2 + 1), line \(line + 1): \(sentence)"
        }
    }

    private static func codeBlock(_ block: Int) -> [String] {
        // 48 lines of code between the two fences: six functions of eight lines.
        var lines = ["```swift"]
        for line in 0..<(hugeBlockLength - 2) {
            switch line % 8 {
            case 0: lines.append("func block\(block)Step\(line / 8)(_ input: Int) -> Int {")
            case 1...5: lines.append("    let value\(line % 8) = input &* \(line % 8) &+ \(block)")
            case 6: lines.append("    return value5 &+ value4")
            default: lines.append("}")
            }
        }
        lines.append("```")
        return lines
    }

    // MARK: Many notes

    private static let manyNotesCount = 2000

    /// "Note 1" to "Note 2000", one minute apart, with "Note 2000" edited at `now`. The session shows the newest.
    private static func manyNotes(now: Date) -> FixtureContent {
        let notes = (1...manyNotesCount).map { number in
            note(
                "Note \(number)", "This is the body of note \(number).\nIt has a second line.",
                editedAt: now.addingTimeInterval(-60 * TimeInterval(manyNotesCount - number)))
        }
        let newest = notes[notes.count - 1]
        return FixtureContent(notes: notes, session: SessionState(tabs: [tab(on: newest)], activeTabIndex: 0))
    }

    // MARK: Building blocks

    /// A note created and last edited at `editedAt`. A pinned note is pinned at that moment too.
    private static func note(_ title: String, _ body: String, editedAt: Date, pinned: Bool = false) -> Note {
        Note(
            id: NoteID.make(), title: title, body: body, createdAt: editedAt, modifiedAt: editedAt,
            pinnedAt: pinned ? editedAt : nil)
    }

    private static func tab(on note: Note) -> TabState {
        TabState(noteID: note.id, selection: 0, scrollY: 0)
    }
}
