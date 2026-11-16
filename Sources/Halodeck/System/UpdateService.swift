// Updates for release builds. A copy downloaded from GitHub updates itself with Sparkle from the public
// release feed (`SUFeedURL` in Info.plist): updates are accepted only with the EdDSA signature matching
// `SUPublicEDKey`, and Apple's code signature checks still apply. A copy installed with Homebrew never
// starts Sparkle: Homebrew updates it, so its records stay right, and the About page offers to run
// `brew upgrade` in Terminal.
import AppKit
import HalodeckCore
import Observation
import os
import Sparkle

@MainActor
@Observable
final class UpdateService {
    static let shared: UpdateService = {
        let info = Bundle.main.infoDictionary ?? [:]
        let hasFeed = (info["SUFeedURL"] as? String)?.isEmpty == false
        let hasKey = (info["SUPublicEDKey"] as? String)?.isEmpty == false
        let available = hasFeed && hasKey
        // Only release builds (with a feed) can update at all, so only they need to know who updates them.
        let channel = available
            ? UpdateChannel.detect(appPath: Bundle.main.bundlePath, fileExists: { FileManager.default.fileExists(atPath: $0) })
            : .sparkle
        return UpdateService(isAvailable: available, channel: channel)
    }()

    /// False for development builds without a feed: the update controls are hidden then.
    let isAvailable: Bool
    let channel: UpdateChannel
    /// The version a scheduled check found and the user hasn't looked at yet: the menu-bar icon shows a
    /// dot and the panel an Update… button while it is set.
    private(set) var availableVersion: String?
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private let terminal: any TerminalLaunching
    @ObservationIgnored let reminders = GentleReminders()

    /// `makeUpdater` creates and starts Sparkle with the given user-driver delegate; it is called only
    /// for an available Sparkle channel.
    init(isAvailable: Bool, channel: UpdateChannel,
         makeUpdater: (SPUStandardUserDriverDelegate) -> SPUStandardUpdaterController? = {
             SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: $0)
         },
         terminal: any TerminalLaunching = TerminalCommandFile()) {
        self.isAvailable = isAvailable
        self.channel = channel
        self.terminal = terminal
        controller = isAvailable && channel == .sparkle ? makeUpdater(reminders) : nil
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
        reminders.service = self
    }

    var hasSparkleUpdater: Bool { controller != nil }

    /// Mirrors Sparkle's own preference, which Sparkle keeps in the app's user defaults.
    var automaticallyChecks: Bool {
        didSet {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != automaticallyChecks else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }

    /// A scheduled check found `version`. Sparkle doesn't open its window for it: the menu-bar icon
    /// shows a dot instead, and the panel and Settings offer Update….
    func updateFound(version: String) {
        guard channel == .sparkle else { return }
        availableVersion = version
    }

    /// Sparkle is about to show `version`. A scheduled check leaves that to Halodeck (the dot); Check
    /// Now and anything Sparkle shows itself go straight to Sparkle's window.
    func updateWillShow(version: String, bySparkle: Bool, userInitiated: Bool) {
        guard !bySparkle, !userInitiated else { return }
        updateFound(version: version)
    }

    /// Sparkle's window for the update got the user's attention, or the update session ended.
    func updateSeen() { availableVersion = nil }

    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    /// Opens Terminal running `brew upgrade` for the cask, then Halodeck again (the upgrade quits it).
    func updateWithHomebrew() {
        guard channel == .homebrew else { return }
        terminal.run(Homebrew.upgradeCommand)
    }
}

/// Sparkle's gentle reminders: a scheduled check that finds an update leaves showing it to Halodeck
/// (a dot on the menu-bar icon) instead of opening the update window over whatever the user is doing.
@MainActor
final class GentleReminders: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    weak var service: UpdateService?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        service?.updateWillShow(version: update.displayVersionString, bySparkle: handleShowingUpdate,
                                userInitiated: state.userInitiated)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        service?.updateSeen()
    }

    func standardUserDriverWillFinishUpdateSession() {
        service?.updateSeen()
    }
}

/// Runs a shell command where the user can watch it.
@MainActor
protocol TerminalLaunching {
    func run(_ command: String)
}

/// Writes the command to an executable `.command` file in the temporary directory and opens it with
/// Terminal (no AppleScript, so no Automation permission). The file deletes itself when it runs.
struct TerminalCommandFile: TerminalLaunching {
    nonisolated private static let log = Logger(subsystem: "io.github.disc.halodeck", category: "updates")

    func run(_ command: String) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("halodeck-update-\(UUID().uuidString).command")
        do {
            try Homebrew.commandFile(running: command).write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        } catch {
            Self.log.error("Couldn't write \(file.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
            return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            NSWorkspace.shared.open(file)   // whatever opens .command files
            return
        }
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Self.log.error("Couldn't open Terminal: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
