import CoreAudio
import Foundation
import os

/// Mutes or unmutes the default input device. Uses the device's mute switch when it has one,
/// otherwise sets its input volume to 0 (and restores the previous volume on unmute). Either control
/// may exist only per channel (elements 1…n) rather than on the main element: then every channel is set.
enum Microphone {
    private static let savedVolumeKey = "halodeck.micVolumeBeforeMute"
    private static let log = Logger(subsystem: "io.github.disc.halodeck", category: "microphone")
    /// Channels probed when the main element has no control.
    private static let maxChannels: UInt32 = 16

    /// Returns the new state (true = muted), or nil if the input device can't be muted.
    static func toggleMute() -> Bool? {
        guard let device = defaultInput() else { return nil }
        let mute = settableElements(device, kAudioDevicePropertyMute)
        if !mute.isEmpty {
            guard let value: UInt32 = read(device, kAudioDevicePropertyMute, mute[0]) else { return nil }
            let newValue: UInt32 = value == 0 ? 1 : 0
            guard write(device, kAudioDevicePropertyMute, mute, newValue) else { return nil }
            return newValue == 1
        }

        let volume = settableElements(device, kAudioDevicePropertyVolumeScalar)
        guard !volume.isEmpty, let current: Float32 = read(device, kAudioDevicePropertyVolumeScalar, volume[0])
        else { return nil }
        let target: Float32
        if current > 0.001 {
            UserDefaults.standard.set(current, forKey: savedVolumeKey)
            target = 0
        } else {
            let saved = UserDefaults.standard.float(forKey: savedVolumeKey)
            target = saved > 0.001 ? saved : 0.75
        }
        guard write(device, kAudioDevicePropertyVolumeScalar, volume, target) else { return nil }
        return target == 0
    }

    /// Whether the default input is muted now (its mute switch, or its input volume at 0); nil when
    /// there is no input or it can be neither.
    static var isMuted: Bool? {
        guard let device = defaultInput() else { return nil }
        let mute = settableElements(device, kAudioDevicePropertyMute)
        if !mute.isEmpty {
            let value: UInt32? = read(device, kAudioDevicePropertyMute, mute[0])
            return value.map { $0 != 0 }
        }
        let volume = settableElements(device, kAudioDevicePropertyVolumeScalar)
        guard !volume.isEmpty else { return nil }
        let current: Float32? = read(device, kAudioDevicePropertyVolumeScalar, volume[0])
        return current.map { $0 <= 0.001 }
    }

    private static func defaultInput() -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static func settableElements(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [UInt32] {
        if isSettable(device, selector, kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        return (1...maxChannels).filter { isSettable(device, selector, $0) }
    }

    private static func address(_ selector: AudioObjectPropertySelector, _ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
    }

    private static func isSettable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ element: UInt32) -> Bool {
        var addr = address(selector, element)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &addr, &settable) == noErr && settable.boolValue
    }

    private static func read<T: BitwiseCopyable>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                _ element: UInt32) -> T? {
        var addr = address(selector, element)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, value)
        guard status == noErr else {
            log.error("input control unreadable: \(status, privacy: .public)")
            return nil
        }
        return value.pointee
    }

    /// Sets `value` on every element; false if any of them failed.
    private static func write<T: BitwiseCopyable>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                 _ elements: [UInt32], _ value: T) -> Bool {
        var ok = true
        for element in elements {
            var addr = address(selector, element)
            var v = value
            let status = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &v)
            if status != noErr {
                log.error("setting an input control failed: \(status, privacy: .public)")
                ok = false
            }
        }
        return ok
    }
}
