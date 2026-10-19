import Dispatch
import Foundation
import Synchronization
import Testing

@testable import ScratchCore

// Spec §6.6: every change is persisted within about one second, and immediately on deactivate or quit. The
// autosave policy is: save 300 ms after the last change, but never more than 1 s after the first unsaved change,
// with no repeating timers. This file covers both Autosaver.swift and AutosaveScheduler.swift, which share its helpers.

// MARK: Helpers

/// Counts how often the autosaver called `save`.
private final class SaveCounter: Sendable {
    private let value = Mutex(0)
    var count: Int { value.withLock { $0 } }
    func increment() { value.withLock { $0 += 1 } }
}

private func ms(_ milliseconds: Int) -> Duration { .milliseconds(milliseconds) }

private func makeAutosaver(
    scheduler: any AutosaveScheduler,
    policy: AutosavePolicy = .standard
) -> (Autosaver, SaveCounter) {
    let counter = SaveCounter()
    let autosaver = Autosaver(policy: policy, scheduler: scheduler, save: { counter.increment() })
    return (autosaver, counter)
}

/// Wraps a scheduler and counts the timers that are scheduled and still waiting to fire.
private final class RecordingScheduler: AutosaveScheduler, Sendable {
    private let base: ManualAutosaveScheduler
    private let live = Mutex(0)

    init(_ base: ManualAutosaveScheduler) { self.base = base }

    var now: Duration { base.now }
    var liveTimers: Int { live.withLock { $0 } }

    func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void) -> any AutosaveTimer {
        live.withLock { $0 += 1 }
        let pending = Mutex(true)  // true until the timer fires or is cancelled
        let finish: @Sendable () -> Void = { [self] in
            let wasPending = pending.withLock { flag -> Bool in
                defer { flag = false }
                return flag
            }
            if wasPending { live.withLock { $0 -= 1 } }
        }
        let inner = base.schedule(after: delay) {
            finish()
            action()
        }
        return RecordingTimer(inner: inner, onCancel: finish)
    }
}

private struct RecordingTimer: AutosaveTimer {
    let inner: any AutosaveTimer
    let onCancel: @Sendable () -> Void
    func cancel() {
        inner.cancel()
        onCancel()
    }
}

/// A scheduler whose timers cannot be cancelled. It stands in for the real race where a timer's action has already
/// been dequeued when `cancel()` runs, so a stale action still fires.
private final class UncancellableScheduler: AutosaveScheduler, Sendable {
    private struct IgnoredTimer: AutosaveTimer { func cancel() {} }
    private let base: ManualAutosaveScheduler

    init(_ base: ManualAutosaveScheduler) { self.base = base }

    var now: Duration { base.now }

    func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void) -> any AutosaveTimer {
        _ = base.schedule(after: delay, action)
        return IgnoredTimer()
    }
}

// MARK: Autosaver with a manual clock

@Test func savesOnceAfterQuietPeriod() {
    let clock = ManualAutosaveScheduler()
    let (autosaver, saves) = makeAutosaver(scheduler: clock)
    autosaver.markDirty()
    clock.advance(by: ms(299))
    #expect(saves.count == 0)
    clock.advance(by: ms(1))
    #expect(saves.count == 1)
    clock.advance(by: .seconds(5))
    #expect(saves.count == 1)
}

@Test func continuousEditingSavesAtLeastEverySecond() {
    let clock = ManualAutosaveScheduler()
    let (autosaver, saves) = makeAutosaver(scheduler: clock)
    autosaver.markDirty()
    for _ in 1...25 {
        clock.advance(by: ms(100))
        autosaver.markDirty()
    }
    #expect(clock.now == ms(2500))
    #expect(saves.count == 2)
    clock.advance(by: ms(300))
    #expect(saves.count == 3)
}

@Test func continuousEditingNeverWaitsPastMaxDelay() {
    let clock = ManualAutosaveScheduler()
    let (autosaver, saves) = makeAutosaver(scheduler: clock)
    autosaver.markDirty()
    for _ in 1...9 {
        clock.advance(by: ms(100))
        autosaver.markDirty()
    }
    #expect(clock.now == ms(900))
    #expect(saves.count == 0)
    clock.advance(by: ms(99))
    #expect(saves.count == 0)
    clock.advance(by: ms(1))
    #expect(saves.count == 1)
}

@Test func flushSavesImmediatelyWhenDirty() {
    let clock = ManualAutosaveScheduler()
    let (autosaver, saves) = makeAutosaver(scheduler: clock)
    autosaver.markDirty()
    autosaver.flush()
    #expect(saves.count == 1)
    clock.advance(by: .seconds(2))
    #expect(saves.count == 1)
}

@Test func flushIsNoOpWhenClean() {
    let clock = ManualAutosaveScheduler()
    let (autosaver, saves) = makeAutosaver(scheduler: clock)
    autosaver.flush()
    #expect(saves.count == 0)
    autosaver.markDirty()
    clock.advance(by: ms(300))
    #expect(saves.count == 1)
    autosaver.flush()
    #expect(saves.count == 1)
}

@Test func markAfterSaveStartsNewCycle() {
    let clock = ManualAutosaveScheduler()
    let (autosaver, saves) = makeAutosaver(scheduler: clock)
    autosaver.markDirty()
    clock.advance(by: ms(300))
    #expect(saves.count == 1)

    clock.advance(by: ms(5000))
    autosaver.markDirty()
    clock.advance(by: ms(299))
    #expect(saves.count == 1)
    clock.advance(by: ms(1))
    #expect(saves.count == 2)
}

@Test func markAfterFlushStartsNewCycle() {
    let clock = ManualAutosaveScheduler()
    let (autosaver, saves) = makeAutosaver(scheduler: clock)
    autosaver.markDirty()
    clock.advance(by: ms(200))
    autosaver.flush()
    #expect(saves.count == 1)

    // The new cycle is measured from this mark, not from the first one, and not from the flush.
    autosaver.markDirty()
    clock.advance(by: ms(299))
    #expect(saves.count == 1)
    clock.advance(by: ms(1))
    #expect(saves.count == 2)
}

@Test func isDirtyFollowsTheCycle() {
    let clock = ManualAutosaveScheduler()
    let (autosaver, _) = makeAutosaver(scheduler: clock)
    #expect(!autosaver.isDirty)
    autosaver.markDirty()
    #expect(autosaver.isDirty)
    clock.advance(by: ms(300))
    #expect(!autosaver.isDirty)
    autosaver.markDirty()
    autosaver.flush()
    #expect(!autosaver.isDirty)
}

@Test func isCleanWhenSaveRuns() {
    let clock = ManualAutosaveScheduler()
    let observed = Mutex<[Bool]>([])
    let box = Mutex<Autosaver?>(nil)
    let autosaver = Autosaver(
        scheduler: clock,
        save: {
            observed.withLock { $0.append(box.withLock { $0 }?.isDirty ?? true) }
        })
    box.withLock { $0 = autosaver }

    autosaver.markDirty()
    clock.advance(by: ms(300))
    autosaver.markDirty()
    autosaver.flush()
    #expect(observed.withLock { $0 } == [false, false])
}

@Test func markDirtyInsideSaveStartsAnotherCycle() {
    // The save closure may fail and mark the saver dirty again to retry. That must neither deadlock nor lose the mark.
    let clock = ManualAutosaveScheduler()
    let counter = SaveCounter()
    let box = Mutex<Autosaver?>(nil)
    let autosaver = Autosaver(
        scheduler: clock,
        save: {
            counter.increment()
            if counter.count == 1 { box.withLock { $0 }?.markDirty() }
        })
    box.withLock { $0 = autosaver }

    autosaver.markDirty()
    clock.advance(by: ms(300))
    #expect(counter.count == 1)
    #expect(autosaver.isDirty)
    clock.advance(by: ms(300))
    #expect(counter.count == 2)
    #expect(!autosaver.isDirty)
}

@Test func customPolicyIsUsed() {
    let clock = ManualAutosaveScheduler()
    let policy = AutosavePolicy(quietPeriod: ms(50), maxDelay: ms(120))
    let (autosaver, saves) = makeAutosaver(scheduler: clock, policy: policy)
    autosaver.markDirty()
    clock.advance(by: ms(50))
    #expect(saves.count == 1)

    autosaver.markDirty()
    for _ in 1...2 {
        clock.advance(by: ms(40))
        autosaver.markDirty()
    }
    clock.advance(by: ms(39))
    #expect(saves.count == 1)
    clock.advance(by: ms(1))
    #expect(saves.count == 2)
}

@Test func standardPolicyMatchesTheSpec() {
    #expect(AutosavePolicy.standard.quietPeriod == ms(300))
    #expect(AutosavePolicy.standard.maxDelay == ms(1000))
}

// MARK: Timers

@Test func holdsAtMostOnePendingTimer() {
    let manual = ManualAutosaveScheduler()
    let clock = RecordingScheduler(manual)
    let (autosaver, saves) = makeAutosaver(scheduler: clock)
    #expect(clock.liveTimers == 0)
    for _ in 1...10 {
        autosaver.markDirty()
        manual.advance(by: ms(10))
        #expect(clock.liveTimers == 1)
    }
    manual.advance(by: ms(300))
    #expect(saves.count == 1)
    // Nothing is left behind once it has saved: an idle app has no timer at all.
    #expect(clock.liveTimers == 0)
}

@Test func flushCancelsThePendingTimer() {
    let manual = ManualAutosaveScheduler()
    let clock = RecordingScheduler(manual)
    let (autosaver, _) = makeAutosaver(scheduler: clock)
    autosaver.markDirty()
    #expect(clock.liveTimers == 1)
    autosaver.flush()
    #expect(clock.liveTimers == 0)
}

@Test func staleTimerDoesNotSave() {
    let manual = ManualAutosaveScheduler()
    let (autosaver, saves) = makeAutosaver(scheduler: UncancellableScheduler(manual))
    autosaver.markDirty()  // timer A, due at 300
    manual.advance(by: ms(100))
    autosaver.markDirty()  // timer B, due at 400. A cannot be cancelled and will still fire.
    manual.advance(by: ms(200))
    #expect(manual.now == ms(300))
    #expect(saves.count == 0)
    #expect(autosaver.isDirty)
    manual.advance(by: ms(100))
    #expect(saves.count == 1)
}

@Test func staleTimerAfterFlushDoesNotSave() {
    let manual = ManualAutosaveScheduler()
    let (autosaver, saves) = makeAutosaver(scheduler: UncancellableScheduler(manual))
    autosaver.markDirty()
    autosaver.flush()
    #expect(saves.count == 1)
    manual.advance(by: .seconds(1))
    #expect(saves.count == 1)
}

// MARK: ManualAutosaveScheduler

@Test func manualSchedulerFiresDueActionsInOrder() {
    let clock = ManualAutosaveScheduler()
    let log = Mutex<[String]>([])
    _ = clock.schedule(after: ms(30)) { log.withLock { $0.append("c") } }
    _ = clock.schedule(after: ms(10)) { log.withLock { $0.append("a") } }
    _ = clock.schedule(after: ms(10)) { log.withLock { $0.append("b") } }
    clock.advance(by: ms(29))
    #expect(log.withLock { $0 } == ["a", "b"])
    clock.advance(by: ms(1))
    #expect(log.withLock { $0 } == ["a", "b", "c"])
}

@Test func manualSchedulerReportsFiringTimeInsideTheAction() {
    let clock = ManualAutosaveScheduler()
    let seen = Mutex<[Duration]>([])
    _ = clock.schedule(after: ms(10)) { seen.withLock { $0.append(clock.now) } }
    _ = clock.schedule(after: ms(70)) { seen.withLock { $0.append(clock.now) } }
    clock.advance(by: ms(100))
    #expect(seen.withLock { $0 } == [ms(10), ms(70)])
    #expect(clock.now == ms(100))
}

@Test func manualSchedulerRunsActionsScheduledWhileAdvancing() {
    let clock = ManualAutosaveScheduler()
    let fired = Mutex<[Duration]>([])
    _ = clock.schedule(after: ms(10)) {
        fired.withLock { $0.append(clock.now) }
        _ = clock.schedule(after: ms(10)) { fired.withLock { $0.append(clock.now) } }
    }
    clock.advance(by: ms(25))
    #expect(fired.withLock { $0 } == [ms(10), ms(20)])
}

@Test func manualSchedulerHonoursCancel() {
    let clock = ManualAutosaveScheduler()
    let fired = SaveCounter()
    let timer = clock.schedule(after: ms(10)) { fired.increment() }
    let kept = clock.schedule(after: ms(10)) { fired.increment() }
    timer.cancel()
    clock.advance(by: ms(10))
    #expect(fired.count == 1)
    kept.cancel()  // cancelling after it fired is harmless
}

@Test func manualSchedulerStartsAtZeroAndOnlyMovesWhenAdvanced() {
    let clock = ManualAutosaveScheduler()
    #expect(clock.now == .zero)
    clock.advance(by: ms(250))
    #expect(clock.now == ms(250))
}

// MARK: DispatchAutosaveScheduler

@Test func dispatchSchedulerFiresOnItsQueueAfterTheDelay() throws {
    let queue = DispatchQueue(label: "autosave.test.fires")
    let scheduler = DispatchAutosaveScheduler(queue: queue)
    let fired = DispatchSemaphore(value: 0)
    let firedAt = Mutex<Duration?>(nil)
    let start = scheduler.now
    let timer = scheduler.schedule(after: ms(40)) {
        dispatchPrecondition(condition: .onQueue(queue))
        firedAt.withLock { $0 = scheduler.now }
        fired.signal()
    }
    #expect(fired.wait(timeout: .now() + .seconds(10)) == .success)
    let elapsed = try #require(firedAt.withLock { $0 }) - start
    #expect(elapsed >= ms(35))
    timer.cancel()  // harmless after firing
}

@Test func dispatchSchedulerCancelPreventsTheAction() {
    let queue = DispatchQueue(label: "autosave.test.cancel")
    let scheduler = DispatchAutosaveScheduler(queue: queue)
    let fired = SaveCounter()
    let timer = scheduler.schedule(after: ms(200)) { fired.increment() }
    timer.cancel()
    Thread.sleep(forTimeInterval: 0.5)
    queue.sync {}
    #expect(fired.count == 0)
}

@Test func dispatchSchedulerClockIsMonotonic() {
    let scheduler = DispatchAutosaveScheduler(queue: DispatchQueue(label: "autosave.test.clock"))
    let first = scheduler.now
    Thread.sleep(forTimeInterval: 0.02)
    let second = scheduler.now
    #expect(second > first)
    #expect(second - first < .seconds(5))
}

@Test func dispatchSchedulerRunsAnOverdueDelayPromptly() {
    let queue = DispatchQueue(label: "autosave.test.overdue")
    let scheduler = DispatchAutosaveScheduler(queue: queue)
    let fired = DispatchSemaphore(value: 0)
    _ = scheduler.schedule(after: ms(-50)) { fired.signal() }
    #expect(fired.wait(timeout: .now() + .seconds(10)) == .success)
}

@Test func autosaverSavesThroughTheDispatchScheduler() {
    let queue = DispatchQueue(label: "autosave.test.autosaver")
    let policy = AutosavePolicy(quietPeriod: ms(30), maxDelay: ms(100))
    let saved = DispatchSemaphore(value: 0)
    let autosaver = Autosaver(
        policy: policy, scheduler: DispatchAutosaveScheduler(queue: queue), save: { saved.signal() })
    autosaver.markDirty()
    #expect(saved.wait(timeout: .now() + .seconds(10)) == .success)
    #expect(!autosaver.isDirty)
    // Exactly one save per cycle, and no timer is left running afterwards.
    #expect(saved.wait(timeout: .now() + .milliseconds(300)) == .timedOut)
}

@Test func concurrentMarkAndFlushEndsCleanAndQuiet() {
    let queue = DispatchQueue(label: "autosave.test.stress")
    let policy = AutosavePolicy(quietPeriod: ms(5), maxDelay: ms(20))
    let (autosaver, saves) = makeAutosaver(
        scheduler: DispatchAutosaveScheduler(queue: queue), policy: policy)

    DispatchQueue.concurrentPerform(iterations: 8) { worker in
        for index in 0..<500 {
            autosaver.markDirty()
            if worker == 0 && index % 50 == 0 { autosaver.flush() }
            if index % 100 == 0 { Thread.sleep(forTimeInterval: 0.005) }
        }
    }
    autosaver.flush()
    #expect(!autosaver.isDirty)
    // A timer that fired just before the flush may still be saving on the queue. Let it finish first.
    queue.sync {}
    let settled = saves.count
    #expect(settled >= 1)
    // Cancelled timers that were already running must not save again.
    Thread.sleep(forTimeInterval: 0.3)
    queue.sync {}
    #expect(saves.count == settled)
}
