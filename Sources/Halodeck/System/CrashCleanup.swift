import CoreGraphics
import Darwin

/// A flag a signal handler can read: one aligned `sig_atomic_t` on the heap, allocated once and never
/// freed. Plain loads and stores of it are single-copy atomic on arm64, need no lock and no
/// allocation, so a crash on any thread can read it whatever state the other threads are in.
struct SignalFlag: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<sig_atomic_t>

    init() {
        storage = .allocate(capacity: 1)
        storage.initialize(to: 0)
    }

    var isSet: Bool { storage.pointee != 0 }

    func set(_ on: Bool) { storage.pointee = on ? 1 : 0 }
}

/// Last-ditch cleanup when Halodeck crashes: a fatal signal (abort, bad access, a Swift trap, …)
/// would otherwise leave the pointer frozen or macOS's own keyboard shortcuts paused.
///
/// Nothing documents that WindowServer re-links the pointer (`CGAssociateMouseAndMouseCursorPosition`)
/// or resumes the system hot keys (`CGSSetGlobalHotKeyOperatingMode`) when the process that changed
/// them dies: the header and Apple's "Controlling the Mouse Cursor" guide only say the calls must be
/// balanced. So Halodeck undoes both itself.
enum CrashCleanup {
    static let pointerFrozen = SignalFlag()
    /// Set while `SystemHotKeys` has macOS's keyboard shortcuts paused (a key recorder is listening).
    static let hotKeysPaused = SignalFlag()

    static let fatalSignals = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]

    /// Call once, early, on the main thread.
    static func install() {
        // Touch the flags now, so the handler never runs their one-time initialisation.
        _ = (pointerFrozen.isSet, hotKeysPaused.isSet)
        var action = sigaction()
        action.__sigaction_u.__sa_handler = handleFatalSignal
        // SA_RESETHAND: the default action is back in place before the handler runs, so a second
        // fault inside it, or the re-raise below, ends the process the ordinary way.
        action.sa_flags = SA_RESETHAND
        sigemptyset(&action.sa_mask)
        for sig in fatalSignals {
            sigaction(sig, &action, nil)
        }
    }

    /// Used by the signal handler and by the SIGTERM / SIGINT path.
    ///
    /// Not strictly async-signal-safe: both are short WindowServer calls (Mach messages) that POSIX
    /// doesn't list as safe. They run only while their flag is set, as a last-ditch attempt before the
    /// process dies anyway; the flags themselves are plain loads with no locks or allocation.
    static func releaseHeldInput() {
        if pointerFrozen.isSet {
            CGAssociateMouseAndMouseCursorPosition(1)
            pointerFrozen.set(false)
        }
        if hotKeysPaused.isSet {
            SystemHotKeys.resumeAfterCrash()
            hotKeysPaused.set(false)
        }
    }
}

/// The fatal-signal handler: releases the pointer and the shortcuts, then re-raises the signal. Its
/// default action is already restored (SA_RESETHAND), so the process still dies with that signal and
/// macOS still writes the crash report.
private func handleFatalSignal(_ sig: Int32) {
    CrashCleanup.releaseHeldInput()
    raise(sig)
}
