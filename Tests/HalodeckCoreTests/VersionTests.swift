import Foundation
import Testing
@testable import HalodeckCore

/// The version a release is built with lives in version.env; the source tree carries the same one
/// for runs without a bundle. A release bumps both.
@Suite struct VersionTests {
    @Test func sourceVersionMatchesVersionEnv() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let env = try String(contentsOf: root.appendingPathComponent("version.env"), encoding: .utf8)
        let line = env.split(separator: "\n").first { $0.hasPrefix("MARKETING_VERSION=") }
        #expect(line.map { String($0.dropFirst("MARKETING_VERSION=".count)) } == HalodeckVersion.marketing)
    }
}
