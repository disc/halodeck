import Foundation
import Testing
@testable import HalodeckCore

/// "Open link" opens only web and mail links: a `file:` link (a .command file runs in Terminal),
/// `javascript:` or another app's custom scheme is refused.
@Suite struct OpenLinkTests {
    @Test func acceptsWebAndMailLinksInAnyCase() {
        #expect(OpenLink.url("https://example.com")?.absoluteString == "https://example.com")
        #expect(OpenLink.url("http://example.com/path?q=1") != nil)
        #expect(OpenLink.url("mailto:someone@example.com") != nil)
        #expect(OpenLink.url("HTTPS://Example.com") != nil)
        #expect(OpenLink.url("Http://example.com") != nil)
        #expect(OpenLink.url("MailTo:someone@example.com") != nil)
    }

    @Test func ignoresSurroundingWhitespace() {
        #expect(OpenLink.url("  https://example.com \n")?.absoluteString == "https://example.com")
    }

    @Test func rejectsLocalFilesScriptsAndOtherSchemes() {
        #expect(OpenLink.url("file:///Users/me/run.command") == nil)
        #expect(OpenLink.url("FILE:///Applications/Calculator.app") == nil)
        #expect(OpenLink.url("javascript:alert(1)") == nil)
        #expect(OpenLink.url("ssh://host") == nil)
        #expect(OpenLink.url("x-apple.systempreferences:com.apple.preference.security") == nil)
        #expect(OpenLink.url("someapp://do/something") == nil)
        #expect(OpenLink.url("ftp://example.com") == nil)
    }

    @Test func rejectsEmptyAndGarbage() {
        #expect(OpenLink.url("") == nil)
        #expect(OpenLink.url("   ") == nil)
        #expect(OpenLink.url("example.com") == nil)
        #expect(OpenLink.url("not a link") == nil)
        #expect(OpenLink.url("https://") == nil)
        #expect(OpenLink.url("https:example.com") == nil)
        #expect(OpenLink.url("mailto:") == nil)
        #expect(OpenLink.url("://example.com") == nil)
    }

    @Test func aCornerWithARefusedLinkIsNotReady() {
        #expect(CornerAction.openLink(url: "https://example.com").isReady)
        #expect(!CornerAction.openLink(url: "file:///tmp/run.command").isReady)
        #expect(!CornerAction.openLink(url: "example").isReady)
    }
}
