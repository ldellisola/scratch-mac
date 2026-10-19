import os

/// Signposts that the performance tests read (spec §7, plan 1 task 10).
enum Signposts {
    static let editor = OSSignposter(subsystem: "io.github.ldellisola.Scratch", category: "editor")
}
