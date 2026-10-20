import Dispatch
import Synchronization

/// A timer that ``AutosaveScheduler/schedule(after:_:)`` has started. Cancelling after it fired is harmless.
public protocol AutosaveTimer: Sendable {
    /// Stops the timer so its action does not run. An action that is already running is not interrupted.
    func cancel()
}

/// The clock and the one-shot timers an ``Autosaver`` uses. Tests drive it by hand with ``ManualAutosaveScheduler``.
public protocol AutosaveScheduler: Sendable {
    /// A monotonic clock. Its origin is arbitrary, so only differences between two readings mean anything.
    var now: Duration { get }
    /// Runs `action` once, `delay` from now. A delay of zero or less means as soon as possible, but never before this
    /// call returns: the caller may hold a lock that the action takes. For the same reason `cancel()` must not run
    /// the action.
    func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void) -> any AutosaveTimer
}

/// A scheduler whose clock moves only when ``advance(by:)`` says so. It never fires anything by itself.
public final class ManualAutosaveScheduler: AutosaveScheduler, @unchecked Sendable {
    private struct Entry {
        let id: Int
        let due: Duration
        let action: @Sendable () -> Void
    }

    private struct State {
        var now: Duration = .zero
        var nextID = 0
        /// In the order they were scheduled, which breaks ties between actions that are due at the same time.
        var entries: [Entry] = []
    }

    private final class ManualTimer: AutosaveTimer {
        private let id: Int
        private let scheduler: ManualAutosaveScheduler

        init(id: Int, scheduler: ManualAutosaveScheduler) {
            self.id = id
            self.scheduler = scheduler
        }

        func cancel() { scheduler.remove(id) }
    }

    private let state = Mutex(State())

    public init() {}

    public var now: Duration { state.withLock { $0.now } }

    public func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void) -> any AutosaveTimer {
        let id = state.withLock { state -> Int in
            let id = state.nextID
            state.nextID += 1
            state.entries.append(Entry(id: id, due: state.now + max(delay, .zero), action: action))
            return id
        }
        return ManualTimer(id: id, scheduler: self)
    }

    /// Moves the clock forward by `duration` and runs every action that falls due, in due order, each one with
    /// ``now`` set to its own due time. Actions scheduled by a running action run too when they fall due inside the
    /// same advance. Actions run on the calling thread with no lock held.
    public func advance(by duration: Duration) {
        let target = state.withLock { $0.now + max(duration, .zero) }
        while let entry = takeNextDue(upTo: target) { entry.action() }
        state.withLock { $0.now = max($0.now, target) }
    }

    private func takeNextDue(upTo target: Duration) -> Entry? {
        state.withLock { state in
            var next: Int?
            for index in state.entries.indices where state.entries[index].due <= target {
                if next == nil || state.entries[index].due < state.entries[next!].due { next = index }
            }
            guard let index = next else { return nil }
            let entry = state.entries.remove(at: index)
            state.now = max(state.now, entry.due)
            return entry
        }
    }

    private func remove(_ id: Int) {
        state.withLock { state in state.entries.removeAll { $0.id == id } }
    }
}

/// The production scheduler: a `ContinuousClock` and `DispatchWorkItem` timers that run on `queue`.
public final class DispatchAutosaveScheduler: AutosaveScheduler {
    /// `DispatchWorkItem` is not marked `Sendable` on every platform, but `cancel()` may be called from any thread.
    private final class WorkItemTimer: AutosaveTimer, @unchecked Sendable {
        private let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    private let queue: DispatchQueue
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    /// `queue` runs every timer's action. Use a serial queue to keep the actions in order.
    public init(queue: DispatchQueue) {
        self.queue = queue
        self.origin = clock.now
    }

    public var now: Duration { origin.duration(to: clock.now) }

    public func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void) -> any AutosaveTimer {
        let item = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: Self.deadline(after: delay), execute: item)
        return WorkItemTimer(item)
    }

    private static func deadline(after delay: Duration) -> DispatchTime {
        guard delay > .zero else { return .now() }
        let (seconds, attoseconds) = delay.components
        // About 68 years is as far as any delay here can sensibly reach. Clamping keeps `Int` conversions safe.
        let wholeSeconds = Int(min(seconds, Int64(Int32.max)))
        return .now() + .seconds(wholeSeconds) + .nanoseconds(Int(attoseconds / 1_000_000_000))
    }
}
