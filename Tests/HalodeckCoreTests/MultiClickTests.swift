import Foundation
import Testing
@testable import HalodeckCore

@Suite struct CornerClickSettingsTests {
    @Test func oneClickIsTheExistingCornerAction() {
        var s = HalodeckSettings()
        #expect(s.cornerAction(.topLeft, clicks: 1) == .muteMicrophone)
        #expect(s.cornerAction(.topLeft, clicks: 2) == .nothing)
        #expect(s.maxClicks(.topLeft) == 1)
        s.corners[.bottomLeft] = .nothing
        #expect(s.maxClicks(.bottomLeft) == 0)
    }

    @Test func extraClickActionsAreStoredAndCounted() {
        var s = HalodeckSettings()
        s.setCornerAction(.openLink(url: "https://example.com"), for: .topLeft, clicks: 2)
        #expect(s.maxClicks(.topLeft) == 2)
        #expect(s.cornerAction(.topLeft, clicks: 2) == .openLink(url: "https://example.com"))
        #expect(s.cornerAction(.topLeft, clicks: 1) == .muteMicrophone)
    }

    @Test func cornerWithOnlyExtraClicksCountsAsActive() {
        var s = HalodeckSettings()
        s.setCornerAction(.mute, for: .bottomLeft, clicks: 2)
        #expect(s.maxClicks(.bottomLeft) == 2)
        #expect(s.activeCorners.contains(.bottomLeft))
    }
}

@Suite struct CornerClickCounterTests {
    let interval = 0.3

    @Test func singleActionFiresImmediately() {
        var c = CornerClickCounter()
        #expect(c.click(.topLeft, at: 0, maxClicks: 1, interval: interval) == CornerClick(corner: .topLeft, count: 1))
        #expect(!c.isWaiting)
    }

    @Test func waitsForMoreClicksWhenMultiClickIsSet() {
        var c = CornerClickCounter()
        #expect(c.click(.topLeft, at: 0, maxClicks: 3, interval: interval) == nil)
        #expect(c.isWaiting)
        #expect(c.tick(now: 0.2, interval: interval) == nil)
        #expect(c.tick(now: 0.31, interval: interval) == CornerClick(corner: .topLeft, count: 1))
        #expect(!c.isWaiting)
    }

    @Test func doubleClickCountsTwo() {
        var c = CornerClickCounter()
        _ = c.click(.topLeft, at: 0, maxClicks: 3, interval: interval)
        #expect(c.click(.topLeft, at: 0.2, maxClicks: 3, interval: interval) == nil)
        #expect(c.tick(now: 0.55, interval: interval) == CornerClick(corner: .topLeft, count: 2))
    }

    @Test func reachingTheMaximumFiresAtOnce() {
        var c = CornerClickCounter()
        _ = c.click(.topRight, at: 0, maxClicks: 2, interval: interval)
        #expect(c.click(.topRight, at: 0.15, maxClicks: 2, interval: interval) == CornerClick(corner: .topRight, count: 2))
        #expect(!c.isWaiting)
    }

    @Test func slowSecondClickStartsAgain() {
        var c = CornerClickCounter()
        _ = c.click(.topLeft, at: 0, maxClicks: 2, interval: interval)
        // The first click expired unnoticed (no tick): a late click still reports it, then starts a new count.
        #expect(c.click(.topLeft, at: 0.5, maxClicks: 2, interval: interval) == CornerClick(corner: .topLeft, count: 1))
        #expect(c.isWaiting)
    }

    @Test func clickingAnotherCornerFlushesTheFirst() {
        var c = CornerClickCounter()
        _ = c.click(.topLeft, at: 0, maxClicks: 2, interval: interval)
        #expect(c.click(.topRight, at: 0.1, maxClicks: 1, interval: interval) == CornerClick(corner: .topLeft, count: 1))
        // The top-right click itself is single-action, so it is reported on the next tick.
        #expect(c.tick(now: 0.1, interval: interval) == CornerClick(corner: .topRight, count: 1))
    }
}

/// Corners react to one or two clicks, so a double click runs as soon as it's made.
@Suite struct TwoClickCornersTests {
    @Test func threeClickActionsCannotBeSet() {
        var s = HalodeckSettings()
        s.setCornerAction(.lockScreen, for: .topLeft, clicks: 3)
        #expect(s.cornerAction(.topLeft, clicks: 3) == .nothing)
        #expect(s.maxClicks(.topLeft) == 1)
    }
}
