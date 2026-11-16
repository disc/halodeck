import Foundation
import os

private let log = Logger(subsystem: "io.github.disc.halodeck", category: "core-brightness")

/// Private CoreBrightness client, loaded once: KeyboardBrightnessClient (the built-in keyboard's
/// backlight, as an exact 0...1 level). Methods are called through
/// their implementations, cast to C function types.
@MainActor
private enum CoreBrightnessKit {
    nonisolated(unsafe) static let handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)

    static func make(_ className: String) -> NSObject? {
        guard handle != nil else {
            log.error("CoreBrightness unavailable")
            return nil
        }
        guard let type = NSClassFromString(className) as? NSObject.Type else {
            log.error("\(className, privacy: .public) unavailable")
            return nil
        }
        return type.init()
    }

    static func method<F>(_ object: NSObject?, _ name: String, as _: F.Type) -> F? {
        let selector = NSSelectorFromString(name)
        guard let object else { return nil }
        guard object.responds(to: selector) else {
            log.error("\(name, privacy: .public) unavailable")
            return nil
        }
        return unsafeBitCast(object.method(for: selector), to: F.self)
    }

    /// Sends a message that returns a +1 object (a `copy…` method), or nil (logged) if the object
    /// doesn't respond to it: `perform` on a missing selector would crash.
    static func copy(_ object: NSObject?, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard let object else { return nil }
        guard object.responds(to: selector) else {
            log.error("\(name, privacy: .public) unavailable")
            return nil
        }
        return object.perform(selector)?.takeRetainedValue()
    }
}

@MainActor
enum KeyboardLight {
    private static let client = CoreBrightnessKit.make("KeyboardBrightnessClient")
    private static let keyboard: UInt64? = {
        let ids = CoreBrightnessKit.copy(client, "copyKeyboardBacklightIDs") as? [NSNumber]
        return ids?.first?.uint64Value
    }()
    private typealias GetFn = @convention(c) (NSObject, Selector, UInt64) -> Float
    private typealias SetFn = @convention(c) (NSObject, Selector, Float, UInt64) -> Bool
    private static let get = CoreBrightnessKit.method(client, "brightnessForKeyboard:", as: GetFn.self)
    private static let set = CoreBrightnessKit.method(client, "setBrightness:forKeyboard:", as: SetFn.self)

    static var isAvailable: Bool { client != nil && keyboard != nil && get != nil && set != nil }

    static func level() -> Double? {
        guard let client, let keyboard, let get else { return nil }
        return Double(get(client, NSSelectorFromString("brightnessForKeyboard:"), keyboard))
    }

    static func setLevel(_ value: Double) {
        guard let client, let keyboard, let set else { return }
        _ = set(client, NSSelectorFromString("setBrightness:forKeyboard:"), Float(min(1, max(0, value))), keyboard)
    }
}
