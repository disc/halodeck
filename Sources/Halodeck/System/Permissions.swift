import AppKit
import ApplicationServices

@MainActor
enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt"   // kAXTrustedCheckOptionPrompt (a C global, not concurrency-safe)
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Watches the Accessibility permission: macOS posts `com.apple.accessibility.api` when an app's
/// entry in the Accessibility list changes, and a slow poll catches anything that notification misses.
/// The app's one `Engine` owns it for the app's lifetime; the timer only holds the engine weakly.
@MainActor
final class AccessibilityWatcher: AccessibilityAccess {
    private static let pollInterval: TimeInterval = 2
    /// The trust database is written just after the notification: look a moment later.
    private static let settleDelay: TimeInterval = 0.3
    private var timer: Timer?
    private let observers = ObserverBag()

    var isGranted: Bool { Permissions.accessibilityGranted }

    func watch(_ onChange: @escaping @MainActor @Sendable () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            MainActor.assumeIsolated { onChange() }
        }
        observers.removeAll()
        observers.observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.accessibility.api")) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) {
                MainActor.assumeIsolated { onChange() }
            }
        }
    }
}
