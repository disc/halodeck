import os

/// A value guarded by an unfair lock: state shared between the MultitouchSupport callback thread,
/// the event-tap thread and the main actor.
final class Locked<Value: Sendable>: Sendable {
    private let lock: OSAllocatedUnfairLock<Value>

    init(_ value: Value) {
        lock = OSAllocatedUnfairLock(initialState: value)
    }

    /// `body` runs synchronously on the caller's thread while the lock is held and its result is
    /// returned to that same thread, so nothing crosses an isolation boundary: that is why the
    /// unchecked variant (no `@Sendable` body, no `Sendable` result) is sound here.
    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try lock.withLockUnchecked(body)
    }
}
