import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// THROWAWAY, branch spike/textkit only (plan 1 task 10, ADR 0001). Where is the caret, in each TextKit and marker
/// hiding technique, for the text `ab **cd** ef`? With the markers hidden and the text intact, the caret before the
/// markers (index 3), between them (4) and after them (5) is at one x, the caret after `cd` (7) and after the closing
/// markers (9) is at another, and `cd` is two characters wide. The result is attached as `geometry` for the ADR.
@MainActor
final class MarkerHidingGeometryTests: XCTestCase {
    private static let text = "ab **cd** ef"

    private func caretReport(mode: TextKitMode, technique: MarkerHidingSpike.Technique?) -> String {
        let (scrollView, view) = TextViewFactory.makeEditor(mode: mode)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 300), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        var spike: MarkerHidingSpike?
        if let technique { spike = MarkerHidingSpike.install(technique, on: view) }
        view.load(Self.text)
        spike?.apply(to: view)
        scrollView.layoutSubtreeIfNeeded()
        if mode == .one {
            if let layoutManager = view.layoutManager, let container = view.textContainer {
                layoutManager.ensureLayout(for: container)
            }
        } else if let layoutManager = view.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }
        scrollView.layoutSubtreeIfNeeded()

        var line = "TextKit \(mode.rawValue) \(technique?.rawValue ?? "plain"):"
        for index in 0...Self.text.utf16.count {
            let rect = view.firstRect(forCharacterRange: NSRange(location: index, length: 0), actualRange: nil)
            line += String(format: " %ld=%.1f", index, rect.minX - window.frame.minX)
        }
        withExtendedLifetime((window, spike)) {}
        return line
    }

    func testCaretPositions() {
        var report = "text: \(Self.text)\n"
        for (mode, technique) in [
            (TextKitMode.one, nil), (.one, .glyphs), (.one, .tiny),
            (.two, nil), (.two, .paragraph), (.two, .zerowidth), (.two, .tiny),
        ] as [(TextKitMode, MarkerHidingSpike.Technique?)] {
            report += caretReport(mode: mode, technique: technique) + "\n"
        }
        let attachment = XCTAttachment(string: report)
        attachment.name = "geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
