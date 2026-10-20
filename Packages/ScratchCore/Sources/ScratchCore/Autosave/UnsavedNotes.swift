import Foundation
import Synchronization

/// The notes whose last write failed, with the text the owner typed, until a write of them succeeds.
///
/// A failed write must never cost text (the anti-goal "Lost text", spec §4): the note stays here, every save tries it
/// again, and a note that is shown again is shown from here and not from the storage, which has an older copy. The
/// writes run on a private queue and the saves and the reads that use this run on the main thread, so every call takes
/// the lock and any thread may make it. A call is one short critical section and never waits for the disk.
///
/// The copies of one note are ordered by their ``Note/modifiedAt``, which every edit sets. The writes of a note run in
/// the order they were made, but a failure is reported when its write ends, so a report about an older copy can arrive
/// after one about a newer copy. The newer copy always wins: a failure of an older one is ignored, and a success of an
/// older one does not forget a newer failure, whose text is still only in memory.
public final class UnsavedNotes: Sendable {
    private let notes = Mutex<[NoteID: Note]>([:])

    public init() {}

    /// A write of `note` failed. It is remembered, unless a newer copy of the same note is.
    public func writeFailed(_ note: Note) {
        notes.withLock { notes in
            if let remembered = notes[note.id], remembered.modifiedAt > note.modifiedAt { return }
            notes[note.id] = note
        }
    }

    /// A write of `note` succeeded. A remembered copy of the same note that is not newer is forgotten, because what it
    /// holds is stored now or was replaced by `note`.
    public func writeSucceeded(_ note: Note) {
        notes.withLock { notes in
            if let remembered = notes[note.id], remembered.modifiedAt <= note.modifiedAt {
                notes[note.id] = nil
            }
        }
    }

    /// The remembered copy of the note `id`, or nil when its last write worked.
    public func note(_ id: NoteID) -> Note? {
        notes.withLock { $0[id] }
    }

    /// Every remembered note, the oldest edit first.
    public var all: [Note] {
        notes.withLock { $0.values.sorted { $0.modifiedAt < $1.modifiedAt } }
    }

    /// Forgets the note `id`: it is gone from the storage, or was discarded, and writing it again would bring it back.
    public func forget(_ id: NoteID) {
        notes.withLock { $0[id] = nil }
    }
}
