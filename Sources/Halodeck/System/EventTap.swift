import CoreGraphics
import Foundation
import os

/// Marks events Halodeck posts itself (replayed clicks, key combinations) so its own tap lets them through.
let halodeckEventTag: Int64 = 0x48414C4F   // "HALO"

extension CGEvent {
    var isFromHalodeck: Bool { getIntegerValueField(.eventSourceUserData) == halodeckEventTag }
    func tagAsHalodeck() { setIntegerValueField(.eventSourceUserData, value: halodeckEventTag) }
}

/// Every mouse event in the session waits for the tap's answer, so the tap runs on its own thread
/// with its own run loop: a busy main thread (SwiftUI, animations, CoreAudio, corner actions) must
/// not lag the pointer, nor get the tap disabled by macOS for being slow. The handler therefore
/// runs on that thread; it returns true to let an event through and false to swallow it.
@MainActor
final class EventTap: EventTapControl {
    /// The event's type, the event, and a function that posts an event so it arrives before the
    /// one being handled. Runs on the tap thread.
    typealias Handler = @Sendable (CGEventType, CGEvent, (CGEvent) -> Void) -> Bool

    /// What the C callback reaches through its refcon. Retained for as long as the tap exists
    /// (`start` to `stop`), so the refcon can't dangle.
    fileprivate final class Context: Sendable {
        let handler: Handler
        let onDisabled: @Sendable () -> Void
        /// Set right after the tap is created, to re-enable it after macOS disabled it.
        let port = Locked<MachPort?>(nil)

        init(handler: @escaping Handler, onDisabled: @escaping @Sendable () -> Void) {
            self.handler = handler
            self.onDisabled = onDisabled
        }
    }

    /// CoreFoundation objects aren't `Sendable`, but these are only used through thread-safe calls:
    /// `CGEvent.tapEnable` and `CFRunLoopStop` may be called from any thread, and the source is
    /// added and removed only on the tap thread.
    fileprivate struct MachPort: @unchecked Sendable { let port: CFMachPort }
    private struct RunLoop: @unchecked Sendable { let loop: CFRunLoop }
    private struct Source: @unchecked Sendable { let source: CFRunLoopSource }

    private struct Running {
        let port: CFMachPort
        let loop: CFRunLoop
        let finished: DispatchSemaphore
        let context: Unmanaged<Context>
    }

    private var running: Running?
    private let log = Logger(subsystem: "io.github.disc.halodeck", category: "event-tap")

    /// False when the tap can't be created (usually: no Accessibility permission).
    func start(handler: @escaping Handler, onDisabled: @escaping @Sendable () -> Void) -> Bool {
        guard running == nil else { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let context = Unmanaged.passRetained(Context(handler: handler, onDisabled: onDisabled))
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: eventTapCallback, userInfo: context.toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            context.release()
            return false
        }
        context.takeUnretainedValue().port.withLock { $0 = MachPort(port: port) }

        let ready = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let loopBox = Locked<RunLoop?>(nil)
        let sourceBox = Source(source: source)
        let thread = Thread {
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, sourceBox.source, .commonModes)
            loopBox.withLock { $0 = RunLoop(loop: loop) }
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, sourceBox.source, .commonModes)
            finished.signal()
        }
        thread.name = "io.github.disc.halodeck.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        guard let loop = loopBox.withLock({ $0 }) else { fatalError("event-tap thread signalled without a run loop") }

        CGEvent.tapEnable(tap: port, enable: true)
        running = Running(port: port, loop: loop.loop, finished: finished, context: context)
        log.debug("event tap started")
        return true
    }

    func stop() {
        guard let running else { return }
        self.running = nil
        CGEvent.tapEnable(tap: running.port, enable: false)
        // A stop before the thread entered `CFRunLoopRun` is kept and ends that run at once.
        CFRunLoopStop(running.loop)
        // Once the thread has left its run loop no callback can be in flight: only then may the
        // port go and the context be released.
        running.finished.wait()
        CFMachPortInvalidate(running.port)
        running.context.release()
        log.debug("event tap stopped")
    }

    fileprivate nonisolated static func handle(_ context: Context, _ proxy: CGEventTapProxy,
                                               _ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            context.onDisabled()
            if let port = context.port.withLock({ $0 }) { CGEvent.tapEnable(tap: port.port, enable: true) }
            return true
        default:
            if event.isFromHalodeck { return true }
            return context.handler(type, event) { $0.tapPostEvent(proxy) }
        }
    }
}

/// Runs on the tap thread.
private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<EventTap.Context>.fromOpaque(refcon).takeUnretainedValue()
    return EventTap.handle(context, proxy, type, event) ? Unmanaged.passUnretained(event) : nil
}
