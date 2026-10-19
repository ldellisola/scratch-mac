import os

/// Signposts that the performance tests read (spec §7, plan 1 task 10). The subsystem and category are also spelled in
/// `PerfSupport.signpostMetric`, which reads the intervals by name.
enum Signposts {
    static let editor = OSSignposter(subsystem: "io.github.ldellisola.Scratch", category: "editor")

    /// Begins the editor interval `name` and ends it when the main run loop is next about to wait, which is when what
    /// began it (a key press, a click on a note) has been laid out, drawn and committed (`RunLoopIdle`). An interval
    /// that ended when the work returned would leave out the text system's layout and drawing, which TextKit does
    /// lazily and which is where the two TextKit versions differ.
    ///
    /// The names in use: `keystroke` (`NoteTextView.keyDown`) and `switch-note` (`SessionCoordinator.open`).
    static func beginEditorInterval(_ name: StaticString) {
        let interval = OpenInterval(name: name, state: editor.beginInterval(name, id: editor.makeSignpostID()))
        RunLoopIdle.onNext { interval.end() }
    }
}

/// A signpost interval that has begun and not ended. A class, so that the closure that ends it needs no Sendable
/// parts: like everything in the app target it belongs to the main actor.
private final class OpenInterval {
    private let name: StaticString
    private let state: OSSignpostIntervalState

    init(name: StaticString, state: OSSignpostIntervalState) {
        self.name = name
        self.state = state
    }

    func end() {
        Signposts.editor.endInterval(name, state)
    }
}
