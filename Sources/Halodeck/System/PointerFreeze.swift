import CoreGraphics
import Foundation
import os

/// Thread-safe: the main actor freezes and unfreezes, the event-tap thread pins the pointer and may
/// unfreeze.
///
/// A watchdog on a utility queue re-links the pointer if a freeze outlives the main thread's last
/// `heartbeat` by `watchdogGrace`: a hung main thread must not leave the pointer stuck.
final class PointerFreeze: PointerFreezing {
    static let shared = PointerFreeze()
    static let watchdogGrace: TimeInterval = 2

    private struct State: Sendable {
        var frozenAt: CGPoint?
        var lastBeat: TimeInterval = 0
        /// Counts freezes, so a watchdog check from an earlier freeze does nothing.
        var generation = 0
    }

    private let state = Locked(State())
    private let watchdog = DispatchQueue(label: "io.github.disc.halodeck.pointer-watchdog", qos: .utility)
    private let log = Logger(subsystem: "io.github.disc.halodeck", category: "pointer")

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func location() -> CGPoint? { CGEvent(source: nil)?.location }

    // The CoreGraphics calls run inside the lock so the association always matches `frozenAt`,
    // whichever thread gets there first. They are short WindowServer calls, made once per gesture.

    func freeze(at point: CGPoint) {
        let generation = state.withLock { s in
            s.frozenAt = point
            s.lastBeat = Self.now
            s.generation += 1
            Self.link(false)   // finger movement no longer moves the pointer
            return s.generation
        }
        check(generation, after: Self.watchdogGrace)
    }

    func unfreeze() {
        state.withLock { s in
            guard let point = s.frozenAt else { return }
            s.frozenAt = nil
            CGWarpMouseCursorPosition(point)
            Self.link(true)   // re-link; also cancels the post-warp input pause
        }
    }

    /// Gives the pointer back where it is now (quitting): no warp, just re-linked.
    func release() {
        state.withLock { s in
            s.frozenAt = nil
            Self.link(true)
        }
    }

    /// Links or unlinks the pointer, keeping `CrashCleanup.pointerFrozen` set for as long as it may be
    /// unlinked, so a crash re-links it (set before unlinking, cleared after re-linking).
    private static func link(_ linked: Bool) {
        if linked {
            CGAssociateMouseAndMouseCursorPosition(1)
            CrashCleanup.pointerFrozen.set(false)
        } else {
            CrashCleanup.pointerFrozen.set(true)
            CGAssociateMouseAndMouseCursorPosition(0)
        }
    }

    func pin(_ location: CGPoint) {
        guard let point = state.withLock({ $0.frozenAt }), location != point else { return }
        CGWarpMouseCursorPosition(point)
    }

    func heartbeat() {
        state.withLock { $0.lastBeat = Self.now }
    }

    private func check(_ generation: Int, after delay: TimeInterval) {
        watchdog.asyncAfter(deadline: .now() + delay) { [self] in
            // nil: nothing to do. Otherwise how long until the freeze may expire (0 = expired now).
            let wait: TimeInterval? = state.withLock { s in
                guard s.generation == generation, s.frozenAt != nil else { return nil }
                let left = Self.watchdogGrace - (Self.now - s.lastBeat)
                guard left <= 0 else { return left }
                s.frozenAt = nil
                Self.link(true)
                return 0
            }
            guard let wait else { return }
            if wait > 0 {
                check(generation, after: wait + 0.05)
            } else {
                log.error("main thread silent during a gesture: pointer released")
            }
        }
    }
}
