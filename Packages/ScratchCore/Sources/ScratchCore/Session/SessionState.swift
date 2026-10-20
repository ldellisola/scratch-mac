import Foundation

/// One open tab: which note it shows, where the cursor is and how far it is scrolled (spec §6.6).
public struct TabState: Codable, Equatable, Sendable {
    public var noteID: NoteID
    /// The cursor position as a UTF-16 offset. May be stale when restored, so clamp it with ``TextOffset/clamp(_:in:)``.
    public var selection: Int
    public var scrollY: Double
    /// The UTF-16 offset of the first visible character. Unlike `scrollY` it keeps its meaning when the window or the
    /// font size changes, so a restore prefers it. Nil when nothing recorded one (a session saved by Scratch 0.1.0),
    /// and the restore then falls back to `scrollY`. Like `selection`, it may be stale, so clamp it with
    /// ``TextOffset/clamp(_:in:)``.
    public var scrollAnchor: Int?

    public init(noteID: NoteID, selection: Int, scrollY: Double, scrollAnchor: Int? = nil) {
        self.noteID = noteID
        self.selection = selection
        self.scrollY = scrollY
        self.scrollAnchor = scrollAnchor
    }

    private enum CodingKeys: String, CodingKey {
        case noteID, selection, scrollY, scrollAnchor
    }

    /// Only `noteID` is required. A missing `selection` or `scrollY` reads as 0, and a missing `scrollAnchor` as nil.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noteID = try container.decode(NoteID.self, forKey: .noteID)
        selection = try container.decodeIfPresent(Int.self, forKey: .selection) ?? 0
        scrollY = try container.decodeIfPresent(Double.self, forKey: .scrollY) ?? 0
        scrollAnchor = try container.decodeIfPresent(Int.self, forKey: .scrollAnchor)
    }
}

/// What a relaunch restores: the open tabs, which one is active and the font size.
///
/// It is stored as JSON and later plans add fields, so decoding ignores unknown keys, and every key except `tabs` may
/// be missing: add each new field with `decodeIfPresent` and a default.
public struct SessionState: Codable, Equatable, Sendable {
    public var tabs: [TabState]
    public var activeTabIndex: Int
    /// The note font size in points, the same for every note (spec §6.4).
    public var fontSize: Double

    public init(tabs: [TabState], activeTabIndex: Int, fontSize: Double = FontSize.standard) {
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
        self.fontSize = fontSize
    }

    private enum CodingKeys: String, CodingKey {
        case tabs, activeTabIndex, fontSize
    }

    /// A missing `fontSize` reads as ``FontSize/standard``. A stored one outside the allowed range is moved into it,
    /// so a damaged file cannot make the text unreadable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try container.decode([TabState].self, forKey: .tabs)
        activeTabIndex = try container.decodeIfPresent(Int.self, forKey: .activeTabIndex) ?? 0
        fontSize =
            try container.decodeIfPresent(Double.self, forKey: .fontSize).map(FontSize.clamped) ?? FontSize.standard
    }
}
