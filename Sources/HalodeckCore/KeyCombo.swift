/// `modifiers` holds a subset of CGEventFlags raw bits
/// (shift 0x20000, control 0x40000, option 0x80000, command 0x100000).
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public extension KeyCombo {
    /// No keys recorded yet (a corner set to Key combination before you record one).
    static let unset = KeyCombo(keyCode: .max, modifiers: 0)
    var isSet: Bool { self != .unset }

    static let shiftFlag: UInt64 = 0x20000
    static let controlFlag: UInt64 = 0x40000
    static let optionFlag: UInt64 = 0x80000
    static let commandFlag: UInt64 = 0x100000
    /// Fn (Globe). macOS ignores it in key presses that an app sends.
    static let fnFlag: UInt64 = 0x800000

    var displayString: String {
        var s = ""
        if modifiers & Self.controlFlag != 0 { s += "⌃" }
        if modifiers & Self.optionFlag != 0 { s += "⌥" }
        if modifiers & Self.shiftFlag != 0 { s += "⇧" }
        if modifiers & Self.commandFlag != 0 { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }
}

/// Names for virtual key codes on a US keyboard layout.
public enum KeyNames {
    public static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    private static let names: [UInt16: String] = {
        var n: [UInt16: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
            40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
            32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
            49: "Space", 36: "↩", 53: "⎋", 48: "⇥", 51: "⌫", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
        ]
        let fKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                               105, 107, 113, 106, 64, 79, 80, 90]
        for (i, code) in fKeys.enumerated() { n[code] = "F\(i + 1)" }
        return n
    }()
}
