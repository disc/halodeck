import Foundation
import Testing
@testable import HalodeckCore

@Suite struct UpdateChannelTests {
    private static let installed = "/Applications/Halodeck.app"

    private func detect(_ appPath: String, existing: Set<String>) -> UpdateChannel {
        UpdateChannel.detect(appPath: appPath, fileExists: { existing.contains($0) })
    }

    @Test func appleSiliconCaskroomMeansHomebrew() {
        #expect(detect(Self.installed, existing: ["/opt/homebrew/Caskroom/halodeck"]) == .homebrew)
    }

    @Test func intelPrefixCaskroomMeansHomebrew() {
        #expect(detect(Self.installed, existing: ["/usr/local/Caskroom/halodeck"]) == .homebrew)
    }

    @Test func withoutACaskroomEntryItIsSparkle() {
        #expect(detect(Self.installed, existing: []) == .sparkle)
        #expect(detect(Self.installed, existing: ["/opt/homebrew/Caskroom/other"]) == .sparkle)
    }

    @Test func aCopyOutsideApplicationsIsSparkleEvenWithACaskroomEntry() {
        let caskrooms: Set<String> = ["/opt/homebrew/Caskroom/halodeck", "/usr/local/Caskroom/halodeck"]
        #expect(detect("/Users/me/Applications/Halodeck.app", existing: caskrooms) == .sparkle)
        #expect(detect("/Users/me/Downloads/Halodeck.app", existing: caskrooms) == .sparkle)
        #expect(detect("/Applications/Halodeck Copy.app", existing: caskrooms) == .sparkle)
    }

    @Test func aTrailingSlashOnTheAppPathStillMatches() {
        #expect(detect(Self.installed + "/", existing: ["/opt/homebrew/Caskroom/halodeck"]) == .homebrew)
    }

    @Test func theUpgradeCommandUpgradesTheCaskAndReopensTheApp() {
        #expect(Homebrew.upgradeCommand == "brew upgrade --cask disc/tap/halodeck && open -b io.github.disc.halodeck")
    }

    @Test func theCommandFileIsALoginZshScriptThatRunsTheCommand() {
        let script = Homebrew.commandFile(running: "brew upgrade --cask x")
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.first == "#!/bin/zsh -l")
        #expect(lines.contains("brew upgrade --cask x"))
        #expect(script.hasSuffix("\n"))
    }

    /// The cask and the bundle identifier come from version.env, which the release script uses,
    /// and agree with the cask it publishes (packaging/halodeck.rb).
    @Test func caskAndBundleIDMatchVersionEnv() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let env = try String(contentsOf: root.appendingPathComponent("version.env"), encoding: .utf8)
        func value(_ key: String) -> String? {
            env.split(separator: "\n").first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) }
        }
        // TAP_REPOSITORY=owner/homebrew-name is tapped as owner/name.
        let tap = try #require(value("TAP_REPOSITORY")).replacingOccurrences(of: "/homebrew-", with: "/")
        #expect(Homebrew.cask == "\(tap)/halodeck")
        let bundleID = try #require(value("BUNDLE_ID"))
        #expect(Homebrew.bundleID == bundleID)

        let cask = try String(contentsOf: root.appendingPathComponent("packaging/halodeck.rb"), encoding: .utf8)
        let lines = Set(cask.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        #expect(lines.contains("cask \"\(Homebrew.cask.split(separator: "/").last ?? "")\" do"))
        #expect(lines.contains("app \"\(URL(fileURLWithPath: UpdateChannel.caskAppPath).lastPathComponent)\""))
        #expect(UpdateChannel.caskAppPath.hasPrefix("/Applications/"))
        #expect(lines.contains("uninstall quit: \"\(bundleID)\""))
        #expect(lines.contains("\"~/Library/Preferences/\(bundleID).plist\","))
        let repository = try #require(value("GITHUB_REPOSITORY"))
        #expect(lines.contains("url \"https://github.com/\(repository)/releases/download/v#{version}/Halodeck-#{version}.zip\""))
        // Homebrew owns updates of a cask install; `auto_updates true` would make `brew upgrade` skip it.
        #expect(!cask.contains("auto_updates"))
        // The template's checksum is an obviously fake placeholder that release.sh replaces: a copy made
        // by hand fails Homebrew's check instead of installing an unverified download (`:no_check`).
        #expect(lines.contains("sha256 \"\(String(repeating: "0", count: 64))\""))
        #expect(!cask.contains(":no_check"))
    }
}
