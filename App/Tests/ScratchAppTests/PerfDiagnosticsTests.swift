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

    func testReport() {
        var report: [String] = []
        let editor = EditorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 800, height: 600))
        defer { withExtendedLifetime(window) {} }
        let text = hugeText()
        let note = Note(id: NoteID.make(), title: "", body: text, createdAt: Date(), modifiedAt: Date())
        let tab = TabState(noteID: note.id, selection: 0, scrollY: 0, scrollAnchor: nil)
        let showMs = milliseconds { editor.show(note, tab: tab, undoManager: UndoManager(), isReadOnly: false) }
        editor.view.layoutSubtreeIfNeeded()
        report.append(String(format: "show %.1f ms", showMs))

        let textView = editor.textView
        let styler = textView.styler.codeBlockStyler
        let started = DispatchTime.now().uptimeNanoseconds
        spin(until: { styler.pendingHighlights == 0 && textView.styler.isFullyStyled }, seconds: 60)
        report.append(
            String(
                format: "styled and coloured after %.0f ms, pending %d",
                Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000,
                styler.pendingHighlights))
        let layoutManager = textView.layoutManager!
        let whole = NSRange(location: 0, length: (text as NSString).length)
        report.append(
            String(
                format: "ensureLayout of the whole note: %.0f ms",
                milliseconds { layoutManager.ensureLayout(forCharacterRange: whole) }))

        // A strip of 60 pt at the top (prose), one over the first block, and one in the middle (prose).
        let nsText = text as NSString
        func rect(ofCharacter index: Int) -> NSRect {
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            return NSRect(
                x: 0, y: fragment.minY + textView.textContainerOrigin.y, width: textView.bounds.width, height: 60)
        }
        let proseRect = rect(ofCharacter: 100)
        let codeRect = rect(ofCharacter: nsText.range(of: "func block1Step1").location)
        let middleRect = rect(ofCharacter: nsText.range(of: "Paragraph 31, line 3:").location)
        func draw(_ strip: NSRect) -> String {
            average(30) {
                if let rep = textView.bitmapImageRepForCachingDisplay(in: strip) {
                    textView.cacheDisplay(in: strip, to: rep)
                }
            }
        }
        func lookups() -> String {
            average(20) {
                for step in 0..<50 {
                    _ = layoutManager.temporaryAttribute(
                        .foregroundColor, atCharacterIndex: (step * 13_751) % whole.length, effectiveRange: nil)
                }
            }
        }
        func typing() -> String {
            let at = nsText.range(of: "Paragraph 31, line 3:").location + 3
            textView.setSelectedRange(NSRange(location: at, length: 0))
            return average(20) { textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }
        report.append(
            "1 coloured, blocks drawn: prose strip \(draw(proseRect)); code strip \(draw(codeRect)); middle \(draw(middleRect))"
        )
        report.append("1 temporary attribute lookups (50 per sample): \(lookups())")
        report.append("1 typing in prose: \(typing())")

        MarkupLayoutManager.diagnosticsDrawsCodeBlocks = false
        report.append(
            "2 coloured, blocks NOT drawn: prose strip \(draw(proseRect)); code strip \(draw(codeRect)); middle \(draw(middleRect))"
        )
        MarkupLayoutManager.diagnosticsDrawsCodeBlocks = true

        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        report.append(
            "3 no temporary attributes, blocks drawn: prose strip \(draw(proseRect)); code strip \(draw(codeRect)); middle \(draw(middleRect))"
        )
        report.append("3 temporary attribute lookups (50 per sample): \(lookups())")
        report.append("3 typing in prose: \(typing())")

        // A few blocks coloured only: 3 blocks' worth of temporary attributes.
        MarkupLayoutManager.diagnosticsDrawsCodeBlocks = false
        report.append(
            "4 no temporary attributes, blocks NOT drawn: prose strip \(draw(proseRect)); code strip \(draw(codeRect)); middle \(draw(middleRect))"
        )
        MarkupLayoutManager.diagnosticsDrawsCodeBlocks = true

        let blocks = textView.styler.codeBlockList.map(\.range)
        let reapply = milliseconds {
            styler.blocksDidChange(blocks, in: textView.textStorage!)
            spin(until: { styler.pendingHighlights == 0 }, seconds: 60)
        }
        report.append(String(format: "5 colours all %d blocks again (cached results): %.0f ms", blocks.count, reapply))
        report.append(
            "5 coloured again: prose strip \(draw(proseRect)); code strip \(draw(codeRect)); middle \(draw(middleRect))"
        )
        report.append("5 temporary attribute lookups (50 per sample): \(lookups())")
        report.append("5 typing in prose: \(typing())")
        XCTFail("DIAGNOSTICS\n" + report.joined(separator: "\n"))
    }
}
