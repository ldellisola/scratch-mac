import XCTest

@testable import Scratch

/// TEMPORARY diagnostic: reports what draws the line under the toolbar. Fails on purpose, so that the report is in the
/// test summary. Removed in the next commit.
@MainActor
final class SeparatorDiagnosticTests: XCTestCase {
    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func typeName(_ object: Any?) -> String {
        guard let object else { return "nil" }
        return String(describing: type(of: object))
    }

    private func box(_ view: NSView, in root: NSView) -> String {
        let rect = view.convert(view.bounds, to: root)
        let top = root.bounds.height - rect.maxY
        return "top=\(Int(top)) h=\(String(format: "%.1f", rect.height)) x=\(Int(rect.minX)) w=\(Int(rect.width))"
    }

    private func viewTree(_ view: NSView, root: NSView, depth: Int, into lines: inout [String]) {
        var line = String(repeating: " ", count: depth) + typeName(view) + " " + box(view, in: root)
        if view.isHidden { line += " HIDDEN" }
        if view.alphaValue < 1 { line += " alpha=\(view.alphaValue)" }
        if let sublayers = view.layer?.sublayers, !sublayers.isEmpty { line += " sublayers=\(sublayers.count)" }
        lines.append(line)
        if view is NSTextView || view is NSTableView || view is NSTextField { return }
        for sub in view.subviews { viewTree(sub, root: root, depth: depth + 1, into: &lines) }
    }

    private func hairlines(_ view: NSView, root: NSView, into lines: inout [String]) {
        let rect = view.convert(view.bounds, to: root)
        let cls = typeName(view)
        if (rect.height <= 2.5 && rect.width > 50)
            || ["Separator", "Pocket", "Effect", "Edge"].contains(where: { cls.contains($0) })
        {
            lines.append("  VIEW \(cls) \(box(view, in: root)) hidden=\(view.isHidden) alpha=\(view.alphaValue)")
        }
        if let layer = view.layer, !(view is NoteTextView), !(view is NSTableView) {
            for sub in layer.sublayers ?? [] where !((sub.delegate as Any) is NSView) {
                let frame = sub.frame
                if (frame.height <= 2.5 && frame.width > 50) || sub.name != nil {
                    lines.append(
                        "  LAYER \(typeName(sub)) in \(cls) \(frame) name=\(sub.name ?? "-") hidden=\(sub.isHidden) "
                            + "opacity=\(sub.opacity)")
                }
            }
        }
        if view is NSTextView || view is NSTableView { return }
        for sub in view.subviews { hairlines(sub, root: root, into: &lines) }
    }

    private func snapshot(_ label: String, window: NSWindow, split: NSSplitViewController, tree: Bool) -> String {
        var lines = ["=== \(label)"]
        lines.append(
            "window titlebarSeparatorStyle=\(window.titlebarSeparatorStyle.rawValue) "
                + "transparent=\(window.titlebarAppearsTransparent) toolbarStyle=\(window.toolbarStyle.rawValue) "
                + "contentLayoutRect=\(window.contentLayoutRect) isKey=\(window.isKeyWindow) "
                + "visible=\(window.isVisible)")
        for item in split.splitViewItems {
            lines.append(
                "item \(typeName(item.viewController)) behavior=\(item.behavior.rawValue) "
                    + "separator=\(item.titlebarSeparatorStyle.rawValue) collapsed=\(item.isCollapsed) "
                    + "adjustsSafe=\(item.automaticallyAdjustsSafeAreaInsets) "
                    + "safeAreaInsets=\(item.viewController.view.safeAreaInsets)")
        }
        if let root = window.contentView?.superview {
            if tree { viewTree(root, root: root, depth: 0, into: &lines) }
            lines.append("hairlines and suspicious classes:")
            hairlines(root, root: root, into: &lines)
        }
        return lines.joined(separator: "\n")
    }

    func testReportTheLineUnderTheToolbar() throws {
        let window = try XCTUnwrap(NSApp.windows.first { $0.contentViewController is MainSplitViewController })
        let split = try XCTUnwrap(window.contentViewController as? NSSplitViewController)
        var report: [String] = []
        spin(1.5)
        report.append(snapshot("A as launched", window: window, split: split, tree: true))

        window.titlebarSeparatorStyle = .line
        spin(0.8)
        report.append(snapshot("B window .line", window: window, split: split, tree: false))

        window.titlebarSeparatorStyle = .none
        spin(0.8)
        report.append(snapshot("C window .none again", window: window, split: split, tree: false))

        let sidebar = split.splitViewItems[0]
        sidebar.isCollapsed = true
        spin(0.8)
        sidebar.isCollapsed = false
        spin(0.8)
        report.append(
            snapshot("D after collapsing and expanding the sidebar", window: window, split: split, tree: false))

        window.titlebarSeparatorStyle = .automatic
        spin(0.8)
        report.append(snapshot("E window .automatic", window: window, split: split, tree: false))

        XCTFail("DIAGNOSTIC REPORT\n" + report.joined(separator: "\n"))
    }
}
