import AppKit
import HalodeckCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private let hud = HUDController()
    private var engine: Engine?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var signalSources: [DispatchSourceSignal] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if HALODECK_SNAPSHOT || DEBUG
        if DebugSnapshot.runIfRequested() {
            NSApp.terminate(nil)
            return
        }
        #endif
        restorePointerOnSignals()
        CrashCleanup.install()   // a crash gives the pointer and the system shortcuts back too
        if !Permissions.accessibilityGranted { Permissions.requestAccessibility() }
        let engine = Engine(store: store, services: .live(hud: hud))
        self.engine = engine
        settingsWindow = SettingsWindowController(store: store, engine: engine)
        menuBar = MenuBarController(engine: engine, store: store) { [weak self] in self?.openSettings() }
        if store.settings.showInNotch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [hud] in hud.greetAtLaunch() }
        }
        hud.refreshMicrophone()   // a microphone muted before launch shows its sign too
        _ = UpdateService.shared   // Sparkle starts with it, at launch even if nothing above touched it yet
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.setEnabled(false)   // also unfreezes the pointer
    }

    /// SIGTERM / SIGINT quit through `terminate` so the engine winds down; the pointer (and system
    /// shortcuts a key recorder paused) are given back first, off the main thread, in case the main
    /// thread is what's stuck. If it is, the signal's default action follows a moment later. Fatal
    /// signals (crashes) go through `CrashCleanup` instead.
    private func restorePointerOnSignals() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global(qos: .userInitiated))
            source.setEventHandler {
                PointerFreeze.shared.release()
                CrashCleanup.releaseHeldInput()
                DispatchQueue.main.async { MainActor.assumeIsolated { NSApp.terminate(nil) } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    signal(sig, SIG_DFL)
                    raise(sig)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func openSettings() {
        settingsWindow?.show()
    }
}
