import Foundation

/// Stores the ``SessionState`` as JSON under the key `state` in the `session` table.
///
/// Any thread may call a `SessionStore`. The ``Database`` serialises the calls.
public final class SessionStore: Sendable {
    private static let key = "state"
    private let database: Database

    /// Brings the schema up to date with `Schema.migrate`, then uses `database`.
    public init(database: Database) throws {
        self.database = database
        try Schema.migrate(database)
    }

    /// The saved session, or nil when nothing was saved or what is stored cannot be decoded. A damaged session must
    /// never keep the app from launching, so the caller starts a fresh one.
    public func load() throws -> SessionState? {
        let rows = try database.query("SELECT value FROM session WHERE key = ?", [.text(Self.key)])
        let bytes: [UInt8]
        switch rows.first?["value"] {
        case .blob(let stored)?: bytes = stored
        case .text(let stored)?: bytes = Array(stored.utf8)
        default: return nil
        }
        return try? JSONDecoder().decode(SessionState.self, from: Data(bytes))
    }

    /// Replaces the saved session.
    public func save(_ state: SessionState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(state)
        try database.execute(
            """
            INSERT INTO session (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            [.text(Self.key), .blob(Array(json))])
    }
}
