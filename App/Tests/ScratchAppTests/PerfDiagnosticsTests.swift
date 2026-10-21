import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// TEMPORARY diagnostics (plan 4, task 5): measures what the code colours cost on the huge note and reports it as a
/// failure message, because the CI is the only Mac. Removed once the numbers are in.
@MainActor
final class PerfDiagnosticsTests: XCTestCase {
    private func hugeText() -> String {
        let sentences = [
            "The scratchpad keeps every line it is given, and never asks to save.",
            "Open notes come back exactly as they were left, cursor and scroll position included.",
            "Pasted text takes the note's font, so a page copied from a browser looks like everything else.",
            "Copying always puts plain text on the pasteboard, whatever the note shows.",
            "A long note must scroll smoothly and switch in a few milliseconds.",
        ]
        var lines: [String] = []
        for block in 0..<200 {
            if block.isMultiple(of: 2) {
                for line in 0..<50 {
                    if line % 5 == 4 {
                        lines.append("")
                    } else {
                        lines.append("Paragraph \(block / 2 + 1), line \(line + 1): \(sentences[(block + line) % 5])")
                    }
                }
            } else {
                lines.append("```swift")
                for line in 0..<48 {
                    switch line % 8 {
                    case 0: lines.append("func block\(block)Step\(line / 8)(_ input: Int) -> Int {")
                    case 1...5: lines.append("    let value\(line % 8) = input &* \(line % 8) &+ \(block)")
                    case 6: lines.append("    return value5 &+ value4")
                    default: lines.append("}")
                    }
                }
                lines.append("```")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func spin(until condition: () -> Bool, seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    private func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func average(_ count: Int, _ body: () -> Void) -> String {
        var samples: [Double] = []
        for _ in 0..<count { samples.append(milliseconds(body)) }
        samples.sort()
        return String(format: "median %.2f max %.2f", samples[samples.count / 2], samples.last ?? 0)
    }

    /// The heights of the fence lines of a small note for each way of keeping glyphs of a fence line.
    func testFenceHeights() {
        var report: [String] = []
        let text = "- a\n**b**\n\n```bash\n# note\nls -l\n```"
        let nsText = text as NSString
        for (name, keep) in [
            ("noteEnd", MarkupLayoutManager.DiagnosticsKeep.noteEnd), ("first", .first), ("last", .last), ("all", .all),
            ("never", .never),
        ] {
            MarkupLayoutManager.diagnosticsKeep = keep
            for variant in ["fresh", "afterInvalidate", "narrowFirst"] {
                let editor = EditorViewController()
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
                    backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentViewController = editor
                window.setContentSize(NSSize(width: variant == "narrowFirst" ? 40 : 800, height: 600))
                let note = Note(id: NoteID.make(), title: "", body: text, createdAt: Date(), modifiedAt: Date())
                let tab = TabState(noteID: note.id, selection: 0, scrollY: 0, scrollAnchor: nil)
                editor.show(note, tab: tab, undoManager: UndoManager(), isReadOnly: false)
                editor.view.layoutSubtreeIfNeeded()
                if variant == "narrowFirst" {
                    window.setContentSize(NSSize(width: 800, height: 600))
                    editor.view.layoutSubtreeIfNeeded()
                }
                let textView = editor.textView
                let layoutManager = textView.layoutManager!
                if variant == "afterInvalidate" {
                    layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: nsText.length))
                    layoutManager.invalidateLayout(
                        forCharacterRange: NSRange(location: 0, length: nsText.length), actualCharacterRange: nil)
                }
                layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: nsText.length))
                func describe(_ index: Int) -> String {
                    let glyph = layoutManager.glyphIndexForCharacter(at: index)
                    var range = NSRange()
                    let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
                    return String(
                        format: "h %.1f y %.1f glyphs %d+%d", rect.height, rect.minY, range.location, range.length)
                }
                let blank = nsText.range(of: "\n\n```").location + 1
                report.append(
                    "\(name)/\(variant): width \(Int(textView.textContainer?.size.width ?? -1)); blank [\(describe(blank))]; opening [\(describe(nsText.range(of: "```bash").location))]; code [\(describe(nsText.range(of: "# note").location))]; closing [\(describe(nsText.range(of: "```", options: .backwards).location))]"
                )
                withExtendedLifetime(window) {}
            }
        }
        MarkupLayoutManager.diagnosticsKeep = .noteEnd
        XCTFail("FENCE HEIGHTS\n" + report.joined(separator: "\n"))
    }
}
