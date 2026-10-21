import os

/// Signposts that the performance tests read (spec §7, plan 1 task 10). The subsystem and category are also spelled in
/// `PerfSupport.signpostMetric`, which reads the intervals by name.
enum Signposts {
    static let editor = OSSignposter(subsystem: "io.github.ldellisola.Scratch", category: "editor")

    /// Begins the editor interval `name` and ends it when the main run loop is next about to wait, which is when what
    /// began it (a key press, a click on a note) has been laid out, drawn and committed (`RunLoopIdle`). An interval
    /// that ended when the work returned would leave out the text system's layout and drawing, which TextKit does
    /// lazily and which is where the two TextKit versions differed (ADR 0001).
    ///
    /// The names in use: `keystroke` (`NoteTextView.keyDown`), `switch-note` (`SessionCoordinator.open` and a switch to
    /// another tab) and `paste-code` (`NoteTextView`'s paste, see `beginOpenEditorInterval`).
    static func beginEditorInterval(_ name: StaticString) {
        beginOpenEditorInterval(name).endWhenIdle()
    }

    /// Begins the editor interval `name` and leaves it open: the caller ends it, with `end()` or `endWhenIdle()`, when
    /// what began it is done. `paste-code` runs from a paste until the colours of the block that it made are on screen,
    /// which is several run loop turns after the paste.
    static func beginOpenEditorInterval(_ name: StaticString) -> OpenInterval {
        OpenInterval(name: name, state: editor.beginInterval(name, id: editor.makeSignpostID()))
    }
}

/// A signpost interval that has begun and not ended. A class, so that the closure that ends it needs no Sendable
/// parts: like everything in the app target it belongs to the main actor.
final class OpenInterval {
    private let name: StaticString
    private let state: OSSignpostIntervalState
    private var isEnded = false

    fileprivate init(name: StaticString, state: OSSignpostIntervalState) {
        self.name = name
        self.state = state
    }

    /// Ends the interval now. Ending it again does nothing.
    func end() {
        guard !isEnded else { return }
        isEnded = true
        Signposts.editor.endInterval(name, state)
    }

    /// Ends the interval when the main run loop is next about to wait: what the interval measured has then been laid out,
    /// drawn and committed (`RunLoopIdle`).
    func endWhenIdle() {
        RunLoopIdle.onNext { [self] in end() }
    }
}
