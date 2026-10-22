import Foundation

/// A file that a fixture's note holds: the row's facts and the bytes of the file.
struct FixtureAttachment {
    var id: AttachmentID
    var noteID: NoteID
    var fileName: String
    var typeIdentifier: String
    var data: Data
    var pixelSize: (width: Int, height: Int)?
}

/// The notes, the saved session and the attachments that one ``Fixture`` seeds.
struct FixtureContent {
    var notes: [Note]
    var session: SessionState?
    var attachments: [FixtureAttachment] = []

    static func make(_ fixture: Fixture, now: Date) -> FixtureContent {
        switch fixture {
        case .empty: FixtureContent(notes: [], session: nil)
        case .typical: typical(now: now)
        case .hugeNote: hugeNote(now: now)
        case .manyNotes: manyNotes(now: now)
        case .recentlyDeleted: recentlyDeleted(now: now)
        case .formatting: formatting(now: now)
        case .code: code(now: now)
        case .attachments: attachments(now: now)
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

    // MARK: Recently deleted

    /// One live note and two deleted ones, one of them past the 30-day retention. The session shows "Groceries".
    private static func recentlyDeleted(now: Date) -> FixtureContent {
        let hour: TimeInterval = 3600
        let day = 24 * hour
        let groceries = note("Groceries", "milk, eggs, coffee beans", editedAt: now.addingTimeInterval(-hour))
        let meeting = note(
            "Old meeting notes", "agenda: roadmap review\naction: send the summary to the team",
            editedAt: now.addingTimeInterval(-3 * day), deletedAt: now.addingTimeInterval(-2 * day))
        let ancient = note(
            "Ancient", "notes from a project that no longer exists",
            editedAt: now.addingTimeInterval(-40 * day), deletedAt: now.addingTimeInterval(-31 * day))
        return FixtureContent(
            notes: [groceries, meeting, ancient], session: SessionState(tabs: [tab(on: groceries)], activeTabIndex: 0))
    }

    // MARK: Formatting

    /// The note "Formatting", edited at `now` and open in the only tab. Each line is one case of the marker table, and
    /// the fenced block at the end holds markers that must not render.
    private static func formatting(now: Date) -> FixtureContent {
        let body = [
            "- first bullet",
            "  - nested bullet",
            "[ ] open task",
            "[x] done task",
            "Some **bold** text, `inline **code**` and https://example.com/a_(b)?q=1.",
            "Unclosed **star and a lone ` tick stay plain.",
            "```sh",
            "- not a bullet",
            "**not bold**",
            "```",
        ].joined(separator: "\n")
        let formatting = note("Formatting", body, editedAt: now)
        return FixtureContent(
            notes: [formatting], session: SessionState(tabs: [tab(on: formatting)], activeTabIndex: 0))
    }

    // MARK: Code

    /// The note "Code", edited at `now` and open in the only tab: a fenced block for each of five languages and one with
    /// no name on its fence, with a line of prose between the blocks. Every line is short enough not to wrap in a window
    /// of 1,024 points.
    private static func code(now: Date) -> FixtureContent {
        let body = [
            "Snippets, one block for each language.",
            "```swift",
            "struct Note {",
            "    let id: UUID",
            #"    var title = "Untitled"  // shown in the sidebar"#,
            "    var edits = 0",
            "}",
            "```",
            "A route in Python, and the query behind it.",
            "```python",
            #"@app.route("/notes")"#,
            "def notes(limit: int = 20):",
            "    return [n.title for n in recent(limit)]  # newest first",
            "```",
            "```sql",
            "SELECT title, modified_at FROM notes",
            "WHERE deleted_at IS NULL -- live notes only",
            "ORDER BY modified_at DESC LIMIT 20;",
            "```",
            "What the route answers, and a shell loop to check it.",
            "```json",
            "{",
            #"  "title": "Standup","#,
            #"  "pinned": true,"#,
            #"  "edits": 3"#,
            "}",
            "```",
            "```bash",
            "# poll the endpoint",
            "for i in 1 2 3; do",
            "  curl -s localhost:8080/notes | head -c 80",
            "done",
            "```",
            "A fence with no name: the language is detected from the code.",
            "```",
            #"const notes = await fetch("/notes").then((r) => r.json());"#,
            "// the newest note comes first",
            #"console.log(notes[0]?.title ?? "none", notes.length);"#,
            "```",
        ].joined(separator: "\n")
        let code = note("Code", body, editedAt: now)
        return FixtureContent(notes: [code], session: SessionState(tabs: [tab(on: code)], activeTabIndex: 0))
    }

    // MARK: Attachments

    /// The note "Screenshots", edited at `now` and open in the only tab: a line of text, an image, a line of text and a
    /// text file. The image is 64 x 40 pixels, so it draws at its own size in a window of any width.
    private static func attachments(now: Date) -> FixtureContent {
        let noteID = NoteID.make()
        let image = FixtureAttachment(
            id: dashboardID, noteID: noteID, fileName: "dashboard.png", typeIdentifier: "public.png",
            data: dashboardPNG, pixelSize: (width: 64, height: 40))
        let plan = FixtureAttachment(
            id: rollbackPlanID, noteID: noteID, fileName: "rollback-plan.txt",
            typeIdentifier: "public.plain-text", data: Data(rollbackPlan.utf8), pixelSize: nil)
        let body = [
            "The dashboard after the deploy.",
            AttachmentToken.line(for: image.id),
            "The steps to roll it back.",
            AttachmentToken.line(for: plan.id),
        ].joined(separator: "\n")
        let screenshots = Note(
            id: noteID, title: "Screenshots", body: body, createdAt: now, modifiedAt: now)
        return FixtureContent(
            notes: [screenshots], session: SessionState(tabs: [tab(on: screenshots)], activeTabIndex: 0),
            attachments: [image, plan])
    }

    /// The ids of the two attachments are fixed, so that the note's body is the same on every run (spec §9.4).
    private static let dashboardID = AttachmentID(rawValue: "5c1f0a7e-3b2d-4c8e-9a41-0d6e7f8a9b01")
    private static let rollbackPlanID = AttachmentID(rawValue: "5c1f0a7e-3b2d-4c8e-9a41-0d6e7f8a9b02")

    /// The text of "rollback-plan.txt".
    private static let rollbackPlan = [
        "Rollback plan",
        "",
        "1. Stop the rollout: kubectl rollout pause deploy/api -n prod",
        "2. Go back one revision: kubectl rollout undo deploy/api -n prod",
        "3. Check the error rate in grafana for ten minutes",
        "4. Tell the team in the release channel",
        "",
    ].joined(separator: "\n")

    /// A PNG of 64 x 40 pixels (304 bytes): a window with three buttons and a bar chart, on a blue gradient. It is a
    /// palette image, small enough to keep in the source, and it is the same bytes on every run.
    private static let dashboardPNG: Data = {
        let base64 = [
            "iVBORw0KGgoAAAANSUhEUgAAAEAAAAAoCAMAAAB5EAzbAAAAJFBMVEUYNG4cPXYgRn4kT4YoWI4sYZYwap40c6b////W4Oz1nkIk",
            "QGiCmUtoAAAAx0lEQVR42uWQ0RLCIAwEq6Vqzv//X0MSLPAgBJzpWPehhUuy02Z5TrJ8RQAUjwMEx+7gMskZBFc/D8EufyEo2jUB",
            "MsHaQgV5AhHYZUAg4xMCmx8QkACsUwKerwShRItFAiEEna972gLs8Dy5BbYz81C/QFeW5jUBuQX8z7WyFmwlWuSDzdcJ5T0RE7yL",
            "ti5N4tsnAKqd+wRAWtmWdu4R6Jdn7aAuwU2QeeKDFiWJfE4iu6DZ3hDQ7wrughb5oMXOJGKCcU4geAGbYT0ahNvQBAAAAABJRU5E",
            "rkJggg==",
        ].joined()
        return Data(base64Encoded: base64) ?? Data()
    }()

    // MARK: Building blocks

    /// A note created and last edited at `editedAt`. A pinned note is pinned at that moment too, and a note with a
    /// `deletedAt` is in Recently Deleted.
    private static func note(
        _ title: String, _ body: String, editedAt: Date, pinned: Bool = false, deletedAt: Date? = nil
    ) -> Note {
        Note(
            id: NoteID.make(), title: title, body: body, createdAt: editedAt, modifiedAt: editedAt,
            pinnedAt: pinned ? editedAt : nil, deletedAt: deletedAt)
    }

    private static func tab(on note: Note) -> TabState {
        TabState(noteID: note.id, selection: 0, scrollY: 0)
    }
}
