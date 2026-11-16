import AppKit
import HalodeckCore
import os

/// The actuator's two trailing float arguments are always 0 (other values made the trackpad
/// produce a strange sound).
@MainActor
enum Haptics {
    private static var actuators: [Int: CFTypeRef] = [:]
    nonisolated private static let log = Logger(subsystem: "io.github.disc.halodeck", category: "haptics")
    private static var loggedMissing = false

    static func prepare(devices: [Int: MTDeviceRef]) {
        for actuator in actuators.values { _ = MT.actuatorClose?(actuator) }
        actuators = [:]
        for (key, ref) in devices { prepare(device: key, ref: ref) }
    }

    private static func prepare(device: Int, ref: MTDeviceRef) {
        guard let getID = MT.deviceID, let create = MT.actuatorCreate, let open = MT.actuatorOpen,
              MT.actuatorActuate != nil else {
            if !loggedMissing {
                loggedMissing = true
                log.error("MultitouchSupport actuator functions unavailable: system haptics only")
            }
            return
        }
        var id: UInt64 = 0
        guard getID(ref, &id) == 0, let actuator = create(id)?.takeRetainedValue() else {
            log.debug("no actuator for a trackpad")
            return
        }
        let status = open(actuator)
        if status == 0 { actuators[device] = actuator } else { log.error("MTActuatorOpen failed: \(status, privacy: .public)") }
    }

    static func tick(device: Int, id: Int32) {
        if let actuator = actuators[device], let actuate = MT.actuatorActuate,
           actuate(actuator, id, 0, 0, 0) == 0 {
            return
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    static func tickAll(id: Int32) {
        for device in actuators.keys { tick(device: device, id: id) }
        if actuators.isEmpty { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
    }
}
