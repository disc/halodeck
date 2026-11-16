import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation
import os

private let log = Logger(subsystem: "io.github.disc.halodeck", category: "levels")

/// Volume (CoreAudio), brightness (private DisplayServices) and the keyboard light (CoreBrightness).
/// The built-in display and the default output device are looked up once and cached: the display
/// until `refreshDisplays()` (screen changes), the output until CoreAudio reports a new default.
@MainActor
final class Levels: LevelControl {
    // Looked up once and never mutated: safe to read from any thread.
    nonisolated(unsafe) private static let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let dsGet = ds.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self) }
    private static let dsSet = ds.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self) }

    /// The active built-in display, or nil (Mac mini, closed lid): brightness is then unavailable.
    private var builtInDisplay: CGDirectDisplayID?
    private let output = AudioOutput()

    init() {
        if Self.dsGet == nil || Self.dsSet == nil { log.error("DisplayServices brightness functions unavailable") }
        builtInDisplay = Self.findBuiltInDisplay()
    }

    var brightnessAvailable: Bool { builtInDisplay != nil }

    func refreshDisplays() {
        builtInDisplay = Self.findBuiltInDisplay()
    }

    private static func findBuiltInDisplay() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    func brightness() -> Double? {
        guard let display = builtInDisplay, let get = Self.dsGet else { return nil }
        var value: Float = 0
        let status = get(display, &value)
        guard status == 0 else {
            log.debug("DisplayServicesGetBrightness failed: \(status, privacy: .public)")
            return nil
        }
        return Double(value)
    }

    func setBrightness(_ value: Double) {
        guard let display = builtInDisplay, let set = Self.dsSet else { return }
        let status = set(display, Float(min(1, max(0, value))))
        if status != 0 { log.error("DisplayServicesSetBrightness failed: \(status, privacy: .public)") }
    }

    var canSetVolume: Bool { output.volumeSettable }
    func volume() -> Double? { output.volume() }
    func setVolume(_ value: Double) { output.setVolume(value) }
    var isMuted: Bool? { output.isMuted }
    func setMuted(_ muted: Bool) { output.setMuted(muted) }
    func watchOutput(_ onChange: @escaping @MainActor @Sendable () -> Void) { output.onChange = onChange }

    var keyboardLightAvailable: Bool { KeyboardLight.isAvailable }
    func keyboardLight() -> Double? { KeyboardLight.level() }
    func setKeyboardLight(_ value: Double) { KeyboardLight.setLevel(value) }
}

@MainActor
private final class AudioOutput {
    /// Channels probed when the main element has no mute switch or volume control.
    private static let maxChannels: UInt32 = 16

    private(set) var device: AudioObjectID?
    private(set) var volumeSettable = false
    private var muteElements: [UInt32] = []
    private var listener: AudioListener?
    /// On the device's mute switch and volume controls (whose changes move the virtual main volume).
    private var deviceListeners: [AudioListener] = []
    var onChange: (@MainActor @Sendable () -> Void)?

    init() {
        refresh()
        listener = AudioListener(object: AudioObjectID(kAudioObjectSystemObject),
                                 selector: kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.onChange?()
            }
        }
    }

    private func refresh() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        if status != noErr { log.error("default output device unreadable: \(status, privacy: .public)") }
        device = status == noErr && id != 0 ? id : nil
        volumeSettable = device.map { device in
            var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            var settable: DarwinBoolean = false
            return AudioObjectHasProperty(device, &addr)
                && AudioObjectIsPropertySettable(device, &addr, &settable) == noErr && settable.boolValue
        } ?? false
        muteElements = device.map { Self.elements(of: $0, with: kAudioDevicePropertyMute) } ?? []
        // Replacing the list removes the old device's listeners.
        deviceListeners = device.map { device in
            let volumeElements = Self.elements(of: device, with: kAudioDevicePropertyVolumeScalar)
            return muteElements.compactMap { listen(device, kAudioDevicePropertyMute, $0) }
                + volumeElements.compactMap { listen(device, kAudioDevicePropertyVolumeScalar, $0) }
        } ?? []
    }

    private func listen(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        _ element: UInt32) -> AudioListener? {
        AudioListener(object: device, selector: selector, scope: kAudioDevicePropertyScopeOutput,
                      element: element) { [weak self] in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    private static func elements(of device: AudioObjectID, with selector: AudioObjectPropertySelector) -> [UInt32] {
        func has(_ element: UInt32) -> Bool {
            var addr = address(selector, element: element)
            return AudioObjectHasProperty(device, &addr)
        }
        if has(kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        return (1...maxChannels).filter(has)
    }

    func volume() -> Double? {
        guard let device else { return nil }
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        guard status == noErr else {
            log.debug("volume unreadable: \(status, privacy: .public)")
            return nil
        }
        return Double(value)
    }

    func setVolume(_ value: Double) {
        guard let device else { return }
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var v = Float32(min(1, max(0, value)))
        let status = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        if status != noErr { log.error("setting the volume failed: \(status, privacy: .public)") }
        if value > 0.001, isMuted == true { setMuted(false) }
    }

    /// The main mute switch, or the first channel's when only the channels have one.
    var isMuted: Bool? {
        guard let device, let element = muteElements.first else { return nil }
        var addr = Self.address(kAudioDevicePropertyMute, element: element)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr ? value != 0 : nil
    }

    func setMuted(_ muted: Bool) {
        guard let device else { return }
        for element in muteElements {
            var addr = Self.address(kAudioDevicePropertyMute, element: element)
            var value = UInt32(muted ? 1 : 0)
            let status = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            if status != noErr { log.error("setting mute failed: \(status, privacy: .public)") }
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }
}

private final class AudioListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(object: AudioObjectID, selector: AudioObjectPropertySelector,
          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
          element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
          _ handler: @escaping @Sendable () -> Void) {
        self.object = object
        address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        block = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, .main, block)
        guard status == noErr else {
            log.error("CoreAudio listener not added: \(status, privacy: .public)")
            return nil
        }
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
    }
}
