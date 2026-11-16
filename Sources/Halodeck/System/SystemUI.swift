import AppKit
import HalodeckCore
import os

/// Private system calls for corner actions: lock the screen (login.framework) and Dock features
/// (CoreDockSendNotification, exported by HIServices). Each is looked up once; a missing symbol logs
/// and does nothing.
@MainActor
enum SystemUI {
    nonisolated private static let log = Logger(subsystem: "io.github.disc.halodeck", category: "system-ui")

    private typealias LockFn = @convention(c) () -> Int32
    private typealias DockNotifyFn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void

    nonisolated(unsafe) private static let login = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW)
    private static let lock = login.flatMap { dlsym($0, "SACLockScreenImmediate") }.map { unsafeBitCast($0, to: LockFn.self) }
    private static let dockNotify = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification")   // RTLD_DEFAULT
        .map { unsafeBitCast($0, to: DockNotifyFn.self) }

    static func lockScreen() {
        guard let lock else { return log.error("SACLockScreenImmediate unavailable") }
        _ = lock()
    }

    static func missionControl() { dock("com.apple.expose.awake") }
    static func appExpose() { dock("com.apple.expose.front.awake") }
    static func showDesktop() { dock("com.apple.showdesktop.awake") }

    /// The Apps launcher on macOS 26+, Launchpad before.
    static func showApps() {
        let paths = ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"]
        guard let path = paths.first(where: FileManager.default.fileExists(atPath:)) else {
            return log.error("no Apps or Launchpad app found")
        }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { _, error in
            if let error { log.error("opening the apps launcher failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private static func dock(_ notification: String) {
        guard let dockNotify else { return log.error("CoreDockSendNotification unavailable") }
        dockNotify(notification as CFString, nil)
    }
}
