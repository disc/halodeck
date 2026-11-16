import AppKit
import HalodeckCore
import SwiftUI

/// Pauses macOS's own keyboard shortcuts (screenshots, Spotlight, …) while a recorder listens, so
/// combinations like ⇧⌘4 reach the app instead of firing. Uses the private CoreGraphics call that
/// shortcut-recorder libraries use; does nothing if it's unavailable.
enum SystemHotKeys {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetMode = @convention(c) (Int32, Int32) -> Int32
    nonisolated(unsafe) private static let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
    private static let mainConnection = cg.flatMap { dlsym($0, "CGSMainConnectionID") }.map { unsafeBitCast($0, to: MainConnection.self) }
    private static let setMode = cg.flatMap { dlsym($0, "CGSSetGlobalHotKeyOperatingMode") }.map { unsafeBitCast($0, to: SetMode.self) }

    static func pause(_ paused: Bool) {
        guard let mainConnection, let setMode else { return }
        // CrashCleanup resumes them if Halodeck crashes meanwhile: flag set before pausing, cleared after.
        if paused { CrashCleanup.hotKeysPaused.set(true) }
        _ = setMode(mainConnection(), paused ? 1 : 0)   // 1 = disable system hot keys, 0 = enable
        if !paused { CrashCleanup.hotKeysPaused.set(false) }
    }

    /// Resumes the system hot keys from the fatal-signal handler (`CrashCleanup`). Only called after
    /// `pause(true)`, so the function pointers are already resolved: no dlsym, no lazy initialisation.
    static func resumeAfterCrash() {
        guard let mainConnection, let setMode else { return }
        _ = setMode(mainConnection(), 0)
    }
}

/// The one key recording in progress, shared by every recorder: starting a second one ends the first,
/// so there is never more than one key monitor, and macOS's shortcuts stay paused exactly while some
/// recorder is listening.
@MainActor
final class KeyRecording {
    static let shared = KeyRecording()

    private var owner: UUID?
    private var monitor: Any?
    private var onEnd: (() -> Void)?

    /// Starts listening for `owner`: `handle` sees every key press and modifier change (and returns
    /// the event to let it through, or nil); `onEnd` runs when the recording ends, however it ends.
    func begin(owner: UUID, handle: @escaping (NSEvent) -> NSEvent?, onEnd: @escaping () -> Void) {
        end()
        self.owner = owner
        self.onEnd = onEnd
        SystemHotKeys.pause(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: handle)
    }

    /// Ends the recording (only `owner`'s, when given).
    func end(owner: UUID? = nil) {
        guard self.owner != nil, owner == nil || owner == self.owner else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        self.owner = nil
        SystemHotKeys.pause(false)
        let onEnd = self.onEnd
        self.onEnd = nil
        onEnd?()
    }
}

/// Fn is never recorded: macOS ignores it in key presses that an app sends.
struct CompactKeyRecorder: View {
    @Binding var combo: KeyCombo?
    var placeholder = "Record"
    var clearHelp = "Clear this corner"
    var onClear: () -> Void
    @State private var recording = false
    @State private var held: NSEvent.ModifierFlags = []
    @State private var id = UUID()
    /// The window the recorder is in: recording stops when it stops being the key window.
    @State private var window: NSWindow?

    var body: some View {
        HStack(spacing: 6) {
            Button { recording ? stop() : start() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard").foregroundStyle(.secondary)
                    Text(label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(recording ? Theme.accent : combo == nil ? .secondary : .primary)
                        .frame(minWidth: 70, alignment: .leading)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(recording ? Theme.accent : .clear, lineWidth: 1.2))
            }
            .buttonStyle(.plain)
            .help("Click, then press a key combination (Esc cancels)")
            .accessibilityLabel("Key combination \(combo?.displayString ?? "not set")")

            if !recording && combo != nil {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(clearHelp)
                .accessibilityLabel("Clear key combination")
            }
        }
        .onDisappear(perform: stop)
        // System shortcuts are paused while recording: never leave them paused if the user goes elsewhere.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if recording, let window, note.object as? NSWindow === window { stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private var label: String {
        guard recording else { return combo?.displayString ?? placeholder }
        let glyphs = modifierGlyphs(held)
        return glyphs.isEmpty ? "Press keys…" : glyphs + "…"
    }

    private func modifierGlyphs(_ flags: NSEvent.ModifierFlags) -> String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
    }

    private func start() {
        // The click that started recording came through the key window: the recorder's own.
        window = NSApp.keyWindow
        KeyRecording.shared.begin(owner: id, handle: { event in
            let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
            if event.type == .flagsChanged {
                held = mods
                return nil
            }
            if event.keyCode == 53 && mods.isEmpty { stop(); return nil }   // Esc alone cancels
            combo = KeyCombo(keyCode: event.keyCode, modifiers: UInt64(mods.rawValue))
            stop()
            return nil
        }, onEnd: {
            // Also when another recorder took over.
            recording = false
            held = []
            window = nil
        })
        recording = true
        held = []
    }

    private func stop() {
        KeyRecording.shared.end(owner: id)
    }
}
