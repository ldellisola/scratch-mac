import AppKit
import ScratchCode

/// Colours the code of fenced blocks and keeps their language labels (Plan 4, task 5). This is the interface only: the
/// first commit of the task has the hosted tests (`CodeBlockStylerTests`) fail against it, and the next one implements it.
@MainActor
final class CodeBlockStyler {
    init(textView: NoteTextView, queue: DispatchQueue) {}

    func blocksDidChange(_ blocks: [NSRange], in storage: NSTextStorage) {}

    func language(ofBlockAt location: Int) -> (CodeLanguage?, isDetected: Bool, name: String)? { nil }

    var pendingHighlights: Int { 0 }

    /// The results that were dropped because the text of their block had changed (for tests).
    private(set) var droppedResults = 0
}
