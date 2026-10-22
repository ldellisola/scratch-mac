import Foundation

/// The two moments the launch log measures from, as the kernel knows them: when this process started and when the Mac did.
/// Reading either is one `sysctl`, a few microseconds, and `LaunchTimer` reads them on its background queue, after the
/// first frame (docs/features/launch-times.md).
enum LaunchClock {
    /// When this process was started (`kinfo_proc`'s `p_starttime`: the exec, before dyld and `main`), or nil when the
    /// kernel does not say. The launch budgets of the spec (§7) count from here.
    nonisolated static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        guard start.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    /// When the Mac started (`kern.boottime`), or nil when the kernel does not say. Launches with the same boot time are
    /// launches of one session of the Mac, and the first of them is the cold one.
    nonisolated static func bootTime() -> Date? {
        var name: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctl(&name, UInt32(name.count), &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
    }
}
