import AppKit

enum MediaKey: Int32 {
    case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    case next = 17, previous = 18, keyboardLightUp = 21, keyboardLightDown = 22
}

/// Presses a media key the way the keyboard does, so macOS shows its own indicator.
@MainActor
enum MediaKeys {
    /// `fine`: send Shift+Option with the key, which macOS turns into a quarter step.
    static func press(_ key: MediaKey, fine: Bool) {
        post(key, down: true, fine: fine)
        post(key, down: false, fine: fine)
    }

    private static func post(_ key: MediaKey, down: Bool, fine: Bool) {
        var flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        if fine { flags.formUnion([.shift, .option]) }
        let data1 = Int((key.rawValue << 16) | ((down ? 0xA : 0xB) << 8))
        NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                           timestamp: 0, windowNumber: 0, context: nil,
                           subtype: 8,   // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                           data1: data1, data2: -1)?
            .cgEvent?.post(tap: .cghidEventTap)
    }
}

@MainActor
enum KeyPress {
    static let leftArrow: UInt16 = 123, rightArrow: UInt16 = 124, tab: UInt16 = 48

    /// Tagged so Halodeck's own event tap ignores it.
    static func post(keyCode: UInt16, flags: CGEventFlags = []) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.tagAsHalodeck()
            event.post(tap: .cghidEventTap)
        }
    }
}
