import AppKit
import Sparkle
import Testing
@testable import Halodeck
import HalodeckCore

@MainActor
final class FakeTerminal: TerminalLaunching {
    var commands: [String] = []
    func run(_ command: String) { commands.append(command) }
}

@MainActor
@Suite struct UpdateServiceTests {
    private func sparkle() -> UpdateService {
        UpdateService(isAvailable: true, channel: .sparkle, makeUpdater: { _ in nil }, terminal: FakeTerminal())
    }

    @Test func aFoundUpdateShowsTheDot() {
        let service = sparkle()
        service.updateFound(version: "0.1.1")
        #expect(service.availableVersion == "0.1.1")
    }

    // A regression here would bring Sparkle's window back over whatever the user is doing.
    @Test func scheduledUpdatesAreLeftToHalodeck() {
        let service = sparkle()
        #expect(service.reminders.supportsGentleScheduledUpdateReminders)
        #expect(!service.reminders.standardUserDriverShouldHandleShowingScheduledUpdate(.empty(), andInImmediateFocus: true))
    }

    @Test func aScheduledUpdateShowsTheDot() {
        let service = sparkle()
        service.updateWillShow(version: "0.1.1", bySparkle: false, userInitiated: false)
        #expect(service.availableVersion == "0.1.1")
    }

    // Check Now shows Sparkle's window right away; the dot would only linger behind it.
    @Test func checkNowDoesNotShowTheDot() {
        let service = sparkle()
        service.updateWillShow(version: "0.1.1", bySparkle: true, userInitiated: true)
        #expect(service.availableVersion == nil)
    }

    @Test func anUpdateSparkleShowsItselfDoesNotShowTheDot() {
        let service = sparkle()
        service.updateWillShow(version: "0.1.1", bySparkle: true, userInitiated: false)
        #expect(service.availableVersion == nil)
    }

    @Test func aNewerVersionReplacesTheOneWaiting() {
        let service = sparkle()
        service.updateFound(version: "0.1.1")
        service.updateFound(version: "0.1.2")
        #expect(service.availableVersion == "0.1.2")
    }

    @Test func theDotComesBackWhenALaterCheckFindsTheUpdateAgain() {
        let service = sparkle()
        service.updateFound(version: "0.1.1")
        service.updateSeen()
        service.updateFound(version: "0.1.1")
        #expect(service.availableVersion == "0.1.1")
    }

    // The session can end without the window ever getting attention (an error, an aborted check).
    @Test func theDotClearsWhenTheUpdateSessionEnds() {
        let service = sparkle()
        service.updateFound(version: "0.1.1")
        service.reminders.standardUserDriverWillFinishUpdateSession()
        #expect(service.availableVersion == nil)
    }

    @Test func sparklesWindowGettingAttentionClearsTheDot() {
        let service = sparkle()
        service.updateFound(version: "0.1.1")
        service.reminders.standardUserDriverDidReceiveUserAttention(forUpdate: .empty())
        #expect(service.availableVersion == nil)
    }

    @Test func openingTheUpdateWindowClearsTheDot() {
        let service = sparkle()
        service.updateFound(version: "0.1.1")
        service.updateSeen()
        #expect(service.availableVersion == nil)
    }

    @Test func aHomebrewInstallNeverShowsTheDot() {
        let service = UpdateService(isAvailable: true, channel: .homebrew, makeUpdater: { _ in nil }, terminal: FakeTerminal())
        service.updateFound(version: "0.1.1")
        #expect(service.availableVersion == nil)
    }

    @Test func aHomebrewInstallNeverCreatesTheSparkleUpdater() {
        var made = 0
        let service = UpdateService(isAvailable: true, channel: .homebrew,
                                    makeUpdater: { _ in made += 1; return nil }, terminal: FakeTerminal())
        #expect(made == 0)
        #expect(!service.hasSparkleUpdater)
        #expect(service.channel == .homebrew)
        #expect(service.isAvailable)
    }

    @Test func updateWithHomebrewRunsTheUpgradeInTerminal() {
        let terminal = FakeTerminal()
        let service = UpdateService(isAvailable: true, channel: .homebrew, makeUpdater: { _ in nil }, terminal: terminal)
        service.updateWithHomebrew()
        #expect(terminal.commands == [Homebrew.upgradeCommand])
    }

    @Test func aSparkleInstallCreatesTheUpdaterOnce() {
        var made = 0
        let terminal = FakeTerminal()
        let service = UpdateService(isAvailable: true, channel: .sparkle,
                                    makeUpdater: { _ in made += 1; return nil }, terminal: terminal)
        #expect(made == 1)
        service.updateWithHomebrew()
        #expect(terminal.commands.isEmpty)
    }

    @Test func aDevelopmentBuildWithoutAFeedCreatesNoUpdater() {
        var made = 0
        let service = UpdateService(isAvailable: false, channel: .sparkle,
                                    makeUpdater: { _ in made += 1; return nil }, terminal: FakeTerminal())
        #expect(made == 0)
        #expect(!service.isAvailable)
    }
}
