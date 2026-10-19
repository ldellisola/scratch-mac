import Foundation

/// One open tab: which note it shows, where the cursor is and how far it is scrolled (spec §6.6).
public struct TabState: Codable, Equatable, Sendable {
    public var noteID: NoteID
    /// The cursor position as a UTF-16 offset. May be stale when restored, so clamp it with ``TextOffset/clamp(_:in:)``.
    public var selection: Int
    public var scrollY: Double

    public init(noteID: NoteID, selection: Int, scrollY: Double) {
        self.noteID = noteID
        self.selection = selection
        self.scrollY = scrollY
    }

    private enum CodingKeys: String, CodingKey {
        case noteID, selection, scrollY
    }

    /// Only `noteID` is required. A missing `selection` or `scrollY` reads as 0.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noteID = try container.decode(NoteID.self, forKey: .noteID)
        selection = try container.decodeIfPresent(Int.self, forKey: .selection) ?? 0
        scrollY = try container.decodeIfPresent(Double.self, forKey: .scrollY) ?? 0
    }
}

/// What a relaunch restores: the open tabs and which one is active.
///
/// It is stored as JSON and later plans add fields, so decoding ignores unknown keys, and every key except `tabs` may
/// be missing: add each new field with `decodeIfPresent` and a default.
public struct SessionState: Codable, Equatable, Sendable {
    public var tabs: [TabState]
    public var activeTabIndex: Int

    public init(tabs: [TabState], activeTabIndex: Int) {
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
    }

    private enum CodingKeys: String, CodingKey {
        case tabs, activeTabIndex
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try container.decode([TabState].self, forKey: .tabs)
        activeTabIndex = try container.decodeIfPresent(Int.self, forKey: .activeTabIndex) ?? 0
    }
}
