import CoreGraphics
import Foundation
import Testing
@testable import HalodeckCore

@Suite struct NotchGeometryTests {
    // A 14" MacBook Pro as macOS reports it: 1710 × 1107 pt, notch 185 × 33.5 pt in the middle.
    let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    let left = CGRect(x: 0, y: 1073.5, width: 762.5, height: 33.5)
    let right = CGRect(x: 947.5, y: 1073.5, width: 762.5, height: 33.5)

    @Test func findsTheNotchBetweenTheTwoMenuBarAreas() throws {
        let g = try #require(NotchGeometry(screenFrame: screen, leftArea: left, rightArea: right))
        #expect(g.notch == CGRect(x: 762.5, y: 1073.5, width: 185, height: 33.5))
    }

    @Test func noNotchWithoutBothAreas() {
        #expect(NotchGeometry(screenFrame: screen, leftArea: nil, rightArea: right) == nil)
        #expect(NotchGeometry(screenFrame: screen, leftArea: left, rightArea: nil) == nil)
        // An external display reports one area spanning the width, or areas that touch: no notch.
        #expect(NotchGeometry(screenFrame: screen, leftArea: left, rightArea: left) == nil)
    }

    @Test func windowWrapsTheNotchWithEarsOnBothSides() throws {
        let g = try #require(NotchGeometry(screenFrame: screen, leftArea: left, rightArea: right))
        let frame = g.windowFrame(earWidth: 100)
        #expect(frame.width == 185 + 2 * 100 + 2 * NotchGeometry.shoulder)
        #expect(frame.midX == g.notch.midX)
        #expect(frame.maxY == screen.maxY)
        #expect(frame.height == 33.5)
    }

    @Test func greetingWindowLeavesRoomForTheGlow() throws {
        let g = try #require(NotchGeometry(screenFrame: screen, leftArea: left, rightArea: right))
        let plain = g.windowFrame(earWidth: 90)
        let frame = g.windowFrame(earWidth: 90, margin: 14)
        #expect(frame == CGRect(x: plain.minX - 14, y: plain.minY - 14, width: plain.width + 28, height: plain.height + 14))
        #expect(frame.maxY == screen.maxY)
    }

    @Test func oneSignSpansTheNotchWithAnEarOnTheRight() throws {
        let g = try #require(NotchGeometry(screenFrame: screen, leftArea: left, rightArea: right))
        let frame = g.earFrame(leftSigns: 0, rightSigns: 1)
        let w = NotchGeometry.muteSignWidth
        #expect(frame.minX == 762.5 - NotchGeometry.shoulder)
        #expect(frame.maxX == 947.5 + w + NotchGeometry.shoulder)
        #expect(frame.width == 185 + w + 2 * NotchGeometry.shoulder)
        #expect(frame.minY == g.notch.minY && frame.maxY == screen.maxY)
    }

    @Test func twoSignsOnTheRightWidenOnlyTheRightEar() throws {
        let g = try #require(NotchGeometry(screenFrame: screen, leftArea: left, rightArea: right))
        let one = g.earFrame(leftSigns: 0, rightSigns: 1)
        let both = g.earFrame(leftSigns: 0, rightSigns: 2)
        #expect(both.minX == one.minX)
        #expect(both.maxX - one.maxX == NotchGeometry.muteSignWidth)
        #expect(both.maxX == 947.5 + 2 * NotchGeometry.muteSignWidth + NotchGeometry.shoulder)
        #expect(both.minY == g.notch.minY && both.maxY == screen.maxY)
    }

    @Test func twoSignsOnTheLeftMirrorTheRight() throws {
        let g = try #require(NotchGeometry(screenFrame: screen, leftArea: left, rightArea: right))
        let frame = g.earFrame(leftSigns: 2, rightSigns: 0)
        #expect(frame.minX == 762.5 - 2 * NotchGeometry.muteSignWidth - NotchGeometry.shoulder)
        #expect(frame.maxX == 947.5 + NotchGeometry.shoulder)
        #expect(frame.minY == g.notch.minY && frame.maxY == screen.maxY)
    }

    @Test func secondScreenOffsetIsKept() throws {
        // A built-in display placed right of a bigger external one.
        let shifted = CGRect(x: 2560, y: 0, width: 1710, height: 1107)
        let g = try #require(NotchGeometry(screenFrame: shifted,
                                           leftArea: left.offsetBy(dx: 2560, dy: 0),
                                           rightArea: right.offsetBy(dx: 2560, dy: 0)))
        #expect(abs(g.windowFrame(earWidth: 100).midX - (2560 + 855)) < 0.001)
    }
}
