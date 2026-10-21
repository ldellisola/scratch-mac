import AppKit

/// TEMPORARY diagnostics (plan 4, task 5): a log of what moves the line at the top of the editor after a launch.
@MainActor
enum AnchorTrace {
    static var isOn = false
    private(set) static var lines: [String] = []
    private static let start = ContinuousClock.now

    static func log(_ text: @autoclosure () -> String) {
        guard isOn, lines.count < 220 else { return }
        let parts = (ContinuousClock.now - start).components
        let milliseconds = Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
        lines.append(String(format: "%6.0f ", milliseconds) + text())
    }
}
