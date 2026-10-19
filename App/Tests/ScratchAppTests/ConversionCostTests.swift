import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// THROWAWAY, branch spike/textkit only (plan 1 task 10, ADR 0001). What does the text pay on each keystroke in a
/// 10,000-line note, in each TextKit: `insertText`, reading `string` (a bridged NSString), the derived title and
/// preview of the Swift string, and the clamp of a saved cursor. Milliseconds, attached as `conversion-cost`.
@MainActor
final class ConversionCostTests: XCTestCase {
    private func hugeText() -> String {
        (1...10_000).map { "Paragraph \($0): The scratchpad keeps every line it is given, and never asks to save." }
            .joined(separator: "\n")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    func testConversionCost() {
        let text = hugeText()
        let clock = ContinuousClock()
        var report = "10,000 lines, \(text.utf16.count) UTF-16 units\n"
        for mode in [TextKitMode.one, .two] {
            let (scrollView, view) = TextViewFactory.makeEditor(mode: mode)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered,
                defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = scrollView
            scrollView.layoutSubtreeIfNeeded()

            let load = clock.measure {
                view.load(text)
                scrollView.layoutSubtreeIfNeeded()
            }
            view.setSelectedRange(NSRange(location: text.utf16.count / 3, length: 0))

            let iterations = 100
            var insertTotal = 0.0
            var stringTotal = 0.0
            var titleTotal = 0.0
            var clampTotal = 0.0
            for _ in 0..<iterations {
                insertTotal += milliseconds(
                    clock.measure {
                        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
                        scrollView.layoutSubtreeIfNeeded()
                    })
                var bridged = ""
                stringTotal += milliseconds(clock.measure { bridged = view.string })
                let now = Date()
                var note = Note(id: NoteID.make(), title: "", body: bridged, createdAt: now, modifiedAt: now)
                note.body = bridged
                titleTotal += milliseconds(clock.measure { _ = note.displayTitle + note.preview })
                clampTotal += milliseconds(
                    clock.measure { _ = TextOffset.clamp(text.utf16.count / 3, in: bridged) })
            }
            report += String(
                format:
                    "TextKit %@: load %.2f ms; per keystroke: insertText %.3f ms, string %.3f ms, title+preview %.3f ms, clamp %.3f ms\n",
                mode.rawValue, milliseconds(load), insertTotal / Double(iterations), stringTotal / Double(iterations),
                titleTotal / Double(iterations), clampTotal / Double(iterations))
            withExtendedLifetime(window) {}
        }
        let attachment = XCTAttachment(string: report)
        attachment.name = "conversion-cost"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
