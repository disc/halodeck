import Foundation
import Testing
@testable import HalodeckCore

@Suite struct CustomKeysTests {
    let next = KeyCombo(keyCode: 30, modifiers: KeyCombo.commandFlag)   // ⌘]
    let previous = KeyCombo(keyCode: 33, modifiers: KeyCombo.commandFlag)   // ⌘[

    @Test func eachDirectionHasItsOwnShortcut() {
        var s = HalodeckSettings()
        s.customKeys[.top] = CustomKeys(up: next, down: previous)
        #expect(s.customKey(.top, up: true) == next)
        #expect(s.customKey(.top, up: false) == previous)
        #expect(s.customKey(.bottom, up: true) == nil)
    }

    @Test func aDirectionCanBeLeftEmpty() {
        var s = HalodeckSettings()
        s.customKeys[.left] = CustomKeys(up: next, down: nil)
        #expect(s.customKey(.left, up: false) == nil)
    }

    @Test func fnIsNeverSent() {
        // macOS ignores Fn (Globe) when an app sends it, so a stored Fn bit is dropped.
        var s = HalodeckSettings()
        s.customKeys[.right] = CustomKeys(up: KeyCombo(keyCode: 123, modifiers: KeyCombo.controlFlag | KeyCombo.fnFlag), down: nil)
        #expect(s.customKey(.right, up: true) == KeyCombo(keyCode: 123, modifiers: KeyCombo.controlFlag))
    }
}
