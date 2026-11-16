import AppKit
import HalodeckCore
import IOKit
import os

// MARK: - Private MultitouchSupport bindings

struct MTPoint { var x: Float; var y: Float }
struct MTVector { var pos: MTPoint; var vel: MTPoint }

/// One contact as delivered by MultitouchSupport (96 bytes).
struct MTFinger {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32          // 4 = make touch, 5 = touching; others are hover/lift
    var fingerID: Int32
    var handID: Int32
    var normalized: MTVector  // 0...1, origin bottom-left
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var mm: MTVector
    var zero2a: Int32
    var zero2b: Int32
    var unk2: Float
}

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

/// Symbols looked up at runtime; any of them may be nil on an unexpected macOS build.
/// Each is written once at first use and never mutated, so sharing them across threads is safe.
enum MT {
    nonisolated(unsafe) static let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)

    static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let h = handle, let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: type)
    }

    static let createList = symbol("MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFMutableArray>?).self)
    static let registerCallback = symbol("MTRegisterContactFrameCallback",
        (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self)
    static let unregisterCallback = symbol("MTUnregisterContactFrameCallback",
        (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self)
    static let start = symbol("MTDeviceStart", (@convention(c) (MTDeviceRef, Int32) -> Int32).self)
    static let stop = symbol("MTDeviceStop", (@convention(c) (MTDeviceRef) -> Int32).self)
    static let surfaceDimensions = symbol("MTDeviceGetSensorSurfaceDimensions",
        (@convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32).self)
    static let deviceID = symbol("MTDeviceGetDeviceID",
        (@convention(c) (MTDeviceRef, UnsafeMutablePointer<UInt64>) -> Int32).self)
    static let actuatorCreate = symbol("MTActuatorCreateFromDeviceID",
        (@convention(c) (UInt64) -> Unmanaged<CFTypeRef>?).self)
    static let actuatorOpen = symbol("MTActuatorOpen", (@convention(c) (CFTypeRef) -> Int32).self)
    static let actuatorClose = symbol("MTActuatorClose", (@convention(c) (CFTypeRef) -> Int32).self)
    static let actuatorActuate = symbol("MTActuatorActuate",
        (@convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32).self)
}

// MARK: - I/O registry

/// Each AppleMultitouchDevice's product name and HID usages, keyed by its "Multitouch ID"
/// (the value `MTDeviceGetDeviceID` returns). Empty if the registry can't be read.
enum MultitouchRegistry {
    static func devices() -> [UInt64: MultitouchDeviceInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"),
                                           &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var result: [UInt64: MultitouchDeviceInfo] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let id = (property(service, "Multitouch ID") as? NSNumber)?.uint64Value else { continue }
            result[id] = MultitouchDeviceInfo(product: property(service, "Product") as? String,
                                              usagePairs: usagePairs(property(service, "DeviceUsagePairs")))
        }
        return result
    }

    private static func property(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// nil when the list or any entry is unreadable, so a malformed entry can't hide a touch pad.
    private static func usagePairs(_ value: Any?) -> [HIDUsagePair]? {
        guard let entries = value as? [[String: Any]] else { return nil }
        var pairs: [HIDUsagePair] = []
        for entry in entries {
            guard let page = (entry["DeviceUsagePage"] as? NSNumber)?.intValue,
                  let usage = (entry["DeviceUsage"] as? NSNumber)?.intValue else { return nil }
            pairs.append(HIDUsagePair(page: page, usage: usage))
        }
        return pairs
    }
}

// MARK: - Device manager

/// Finds every trackpad (skipping multitouch mice), streams its touches as `TouchFrame`s while started, and re-discovers
/// devices after sleep/wake and when a trackpad is connected or disconnected.
///
/// Threading: discovery runs on the main actor; MultitouchSupport delivers frames on its own thread
/// through `contactCallback`, which only reads the lock-protected `delivery` and calls its `onFrame`.
/// MultitouchSupport's callback carries no context pointer, so `delivery` is per process: there is
/// one manager, owned by the app's `Engine`.
@MainActor
final class MultitouchManager: TouchStream {
    struct Device: Sendable { var widthMM: Double; var heightMM: Double }

    private struct Delivery: Sendable {
        var devices: [Int: Device] = [:]
        /// Called on the MultitouchSupport thread; nil while stopped.
        var onFrame: (@Sendable (TouchFrame) -> Void)?
    }
    nonisolated private static let delivery = Locked(Delivery())

    private var onDevicesChanged: (@MainActor ([Int: MTDeviceRef]) -> Void)?
    private var running = false
    private var refs: [Int: MTDeviceRef] = [:]
    private var list: CFMutableArray?
    /// Device lists already stopped, kept alive a moment longer: MultitouchSupport's thread may
    /// still be inside a callback for one of their devices.
    private var retiredLists: [CFMutableArray] = []
    private static let retireDelay: TimeInterval = 1
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private let observers = ObserverBag()
    private var rediscoverPending = false
    private let log = Logger(subsystem: "io.github.disc.halodeck", category: "multitouch")

    var hasDevices: Bool { Self.delivery.withLock { !$0.devices.isEmpty } }

    init() {
        precondition(MemoryLayout<MTFinger>.stride == 96, "MTFinger layout mismatch")
    }

    func start(onFrame: @escaping @Sendable (TouchFrame) -> Void,
               onDevicesChanged: @escaping @MainActor ([Int: MTDeviceRef]) -> Void) {
        guard !running else { return }
        running = true
        Self.delivery.withLock { $0.onFrame = onFrame }
        self.onDevicesChanged = onDevicesChanged
        discover()
        observers.observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { [weak self] in
            self?.scheduleRediscover()
        }
        watchIOKit()
    }

    func stop() {
        guard running else { return }
        running = false
        observers.removeAll()
        unwatchIOKit()
        stopAll()
        Self.delivery.withLock { $0.onFrame = nil }
        onDevicesChanged?([:])
        onDevicesChanged = nil
    }

    private func rediscover() {
        guard running else { return }
        stopAll()
        discover()
    }

    /// Coalesces bursts of IOKit / wake notifications into one rediscovery.
    private func scheduleRediscover() {
        guard running, !rediscoverPending else { return }
        rediscoverPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated {
                self?.rediscoverPending = false
                self?.rediscover()
            }
        }
    }

    private func discover() {
        guard let createList = MT.createList, let register = MT.registerCallback, let start = MT.start,
              let newList = createList()?.takeRetainedValue() else {
            log.error("MultitouchSupport unavailable")
            return
        }
        list = newList
        let registry = MultitouchRegistry.devices()
        var found: [Int: Device] = [:]
        var foundRefs: [Int: MTDeviceRef] = [:]
        for i in 0..<CFArrayGetCount(newList) {
            guard let raw = CFArrayGetValueAtIndex(newList, i) else { continue }
            let ref = UnsafeMutableRawPointer(mutating: raw)
            // A Magic Mouse is multitouch too; a device we can't identify stays a trackpad.
            var id: UInt64 = 0
            if let getID = MT.deviceID, getID(ref, &id) == 0, let info = registry[id], info.kind == .mouse {
                log.info("skipping a mouse: \(info.product ?? "unnamed", privacy: .public)")
                continue
            }
            let key = Int(bitPattern: ref)
            var w: Int32 = 0, h: Int32 = 0
            _ = MT.surfaceDimensions?(ref, &w, &h)   // hundredths of a millimetre
            let size = (w > 0 && h > 0) ? (Double(w) / 100, Double(h) / 100) : (130.0, 85.0)
            found[key] = Device(widthMM: size.0, heightMM: size.1)
            foundRefs[key] = ref
        }
        // Publish the device table before starting delivery, so the first frames find their device.
        Self.delivery.withLock { $0.devices = found }
        refs = foundRefs
        for ref in foundRefs.values {
            register(ref, contactCallback)
            _ = start(ref, 0)
        }
        log.notice("multitouch devices: \(found.count)")
        onDevicesChanged?(foundRefs)
    }

    private func stopAll() {
        for ref in refs.values {
            MT.unregisterCallback?(ref, contactCallback)
            _ = MT.stop?(ref)
        }
        Self.delivery.withLock { $0.devices = [:] }
        refs = [:]
        if let list {
            retiredLists.append(list)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.retireDelay) { [weak self] in
                MainActor.assumeIsolated { _ = self?.retiredLists.removeFirst() }
            }
        }
        list = nil
    }

    /// The IOKit callback's refcon is this manager, unretained: the notifications are removed in
    /// `stop` (`unwatchIOKit`), and the manager lives as long as the app's `Engine`, i.e. the app.
    private func watchIOKit() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        // The source is on the main run loop, so the callback runs on the main thread.
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            while case let obj = IOIteratorNext(iterator), obj != 0 { IOObjectRelease(obj) }
            guard let refcon else { return }
            let manager = Unmanaged<MultitouchManager>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { manager.scheduleRediscover() }
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            if IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"),
                                                callback, refcon, &iterator) == KERN_SUCCESS {
                while case let obj = IOIteratorNext(iterator), obj != 0 { IOObjectRelease(obj) }   // arm it
                iterators.append(iterator)
            }
        }
    }

    private func unwatchIOKit() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators = []
        if let notifyPort {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .defaultMode)
            IONotificationPortDestroy(notifyPort)
        }
        notifyPort = nil
    }

    /// MultitouchSupport thread.
    nonisolated fileprivate static func handle(device ref: MTDeviceRef, fingers: UnsafeMutableRawPointer?, count: Int32) {
        let key = Int(bitPattern: ref)
        guard let (device, onFrame) = delivery.withLock({ d in d.devices[key].flatMap { dev in d.onFrame.map { (dev, $0) } } })
        else { return }
        var touches: [TouchPoint] = []
        if let fingers, count > 0 {
            // The framework's buffer already holds `MTFinger`s: no rebinding, just a typed view.
            let list = fingers.assumingMemoryBound(to: MTFinger.self)
            for i in 0..<Int(count) {
                let f = list[i]
                guard f.state == 4 || f.state == 5 else { continue }
                let x = Double(f.normalized.pos.x), y = Double(f.normalized.pos.y)
                touches.append(TouchPoint(id: f.identifier, normalizedX: x,
                                          xMM: x * device.widthMM, yMM: y * device.heightMM))
            }
        }
        onFrame(TouchFrame(device: key, padHeightMM: device.heightMM, touches: touches,
                           time: ProcessInfo.processInfo.systemUptime))
    }
}

private let contactCallback: MTContactCallback = { device, fingers, count, _, _ in
    if let device { MultitouchManager.handle(device: device, fingers: fingers, count: count) }
    return 0
}
