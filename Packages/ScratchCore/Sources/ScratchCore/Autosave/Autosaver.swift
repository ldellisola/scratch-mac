import Synchronization

/// When the autosaver saves. A save happens `quietPeriod` after the last change, but never later than `maxDelay`
/// after the first unsaved change, so continuous typing still saves about once a second.
public struct AutosavePolicy: Equatable, Sendable {
    public var quietPeriod: Duration
    public var maxDelay: Duration

    public init(quietPeriod: Duration, maxDelay: Duration) {
        self.quietPeriod = quietPeriod
        self.maxDelay = maxDelay
    }

    /// Spec §6.6: every change is persisted within about one second.
    public static let standard = AutosavePolicy(quietPeriod: .milliseconds(300), maxDelay: .milliseconds(1000))
}

/// Decides when unsaved changes are written, and calls `save` when that time comes.
///
/// ``markDirty()`` says that something changed. The saver then keeps a single one-shot timer, set for
/// `min(now + quietPeriod, dirtySince + maxDelay)` and replaced by each further `markDirty()`. When it fires, or on
/// ``flush()``, the saver becomes clean first and then calls `save`. A change made while `save` runs is therefore never
/// lost: it starts the next cycle. A clean saver has no timer at all, so an idle app wakes nothing.
///
/// Any thread may call ``markDirty()``, ``flush()`` and ``isDirty``. `save` runs outside the saver's lock, on the
/// scheduler's queue or on the thread that called ``flush()``, so two saves can overlap and it must be thread-safe. It
/// should read the latest state when it runs instead of capturing a snapshot, and it may call ``markDirty()`` itself,
/// to retry after a failure for example.
///
/// The saver does not keep itself alive: when its owner drops it while it is dirty, the pending save is skipped. The
/// owner calls ``flush()`` first when the app deactivates or quits.
public final class Autosaver: Sendable {
    private struct State {
        /// When the first change since the last save happened, or nil when there is nothing to save.
        var dirtySince: Duration?
        var timer: (any AutosaveTimer)?
        /// Identifies the timer that is allowed to save. A timer that was cancelled too late to stop its action finds
        /// a newer generation and does nothing.
        var generation: UInt64 = 0
    }

    private let policy: AutosavePolicy
    private let scheduler: any AutosaveScheduler
    private let save: @Sendable () -> Void
    private let state = Mutex(State())

    public init(
        policy: AutosavePolicy = .standard,
        scheduler: any AutosaveScheduler,
        save: @escaping @Sendable () -> Void
    ) {
        self.policy = policy
        self.scheduler = scheduler
        self.save = save
    }

    /// Whether there are changes that have not been handed to `save` yet.
    public var isDirty: Bool { state.withLock { $0.dirtySince != nil } }

    /// Records a change and (re)schedules the save.
    public func markDirty() {
        state.withLock { state in
            let now = scheduler.now
            let dirtySince = state.dirtySince ?? now
            state.dirtySince = dirtySince
            let due = min(now + policy.quietPeriod, dirtySince + policy.maxDelay)

            state.timer?.cancel()
            state.generation &+= 1
            let generation = state.generation
            state.timer = scheduler.schedule(after: due - now) { [weak self] in
                self?.timerFired(generation: generation)
            }
        }
    }

    /// Saves now if there are unsaved changes, and does nothing otherwise.
    public func flush() {
        let shouldSave = state.withLock { state -> Bool in
            guard state.dirtySince != nil else { return false }
            becomeClean(&state)
            return true
        }
        if shouldSave { save() }
    }

    private func timerFired(generation: UInt64) {
        let shouldSave = state.withLock { state -> Bool in
            guard state.generation == generation, state.dirtySince != nil else { return false }
            becomeClean(&state)
            return true
        }
        if shouldSave { save() }
    }

    private func becomeClean(_ state: inout State) {
        state.timer?.cancel()
        state.timer = nil
        state.dirtySince = nil
        state.generation &+= 1
    }
}
