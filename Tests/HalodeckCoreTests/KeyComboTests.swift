import Testing
@testable import HalodeckCore

@Suite struct KeyComboTests {
    let cmd: UInt64 = 0x100000, shift: UInt64 = 0x20000, ctrl: UInt64 = 0x40000, option: UInt64 = 0x80000

    @Test func screenshotCombo() {
        #expect(KeyCombo(keyCode: 21, modifiers: cmd | shift).displayString == "⇧⌘4")
    }

    @Test func modifierOrder() {
        #expect(KeyCombo(keyCode: 0, modifiers: ctrl | option).displayString == "⌃⌥A")
        #expect(KeyCombo(keyCode: 0, modifiers: cmd | shift | option | ctrl).displayString == "⌃⌥⇧⌘A")
    }

    @Test func namedKeys() {
        #expect(KeyNames.name(for: 49) == "Space")
        #expect(KeyNames.name(for: 36) == "↩")
        #expect(KeyNames.name(for: 53) == "⎋")
        #expect(KeyNames.name(for: 122) == "F1")
        #expect(KeyNames.name(for: 126) == "↑")
    }

    @Test func unknownKey() {
        #expect(KeyNames.name(for: 999) == "Key 999")
    }
}
