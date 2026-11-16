/// A HID usage page/usage pair, as listed in an I/O registry entry's "DeviceUsagePairs".
public struct HIDUsagePair: Hashable, Sendable {
    public var page: Int
    public var usage: Int

    public init(page: Int, usage: Int) {
        self.page = page
        self.usage = usage
    }

    /// Digitizer page (0x0D), Touch Pad usage.
    public static let touchPad = HIDUsagePair(page: 13, usage: 5)
    /// Generic Desktop page, Mouse usage.
    public static let mouse = HIDUsagePair(page: 1, usage: 2)
}

/// What MultitouchSupport's device is: Halodeck drives trackpads and leaves mice alone.
public enum MultitouchDeviceKind: Sendable, Equatable {
    case trackpad
    case mouse
}

/// The I/O registry facts about one multitouch device; nil means missing or unreadable.
public struct MultitouchDeviceInfo: Sendable, Equatable {
    public var product: String?
    public var usagePairs: [HIDUsagePair]?

    public init(product: String?, usagePairs: [HIDUsagePair]?) {
        self.product = product
        self.usagePairs = usagePairs
    }

    /// A trackpad unless we can tell it is a mouse: no Digitizer Touch Pad usage, and either the
    /// generic Mouse usage or "Mouse" in the product name. Without readable usage pairs we can't
    /// rule out a touch pad, so an unknown device stays a trackpad.
    public var kind: MultitouchDeviceKind {
        guard let usagePairs, !usagePairs.contains(.touchPad) else { return .trackpad }
        let namedMouse = product?.lowercased().contains("mouse") ?? false
        return usagePairs.contains(.mouse) || namedMouse ? .mouse : .trackpad
    }
}
