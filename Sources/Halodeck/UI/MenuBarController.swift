import AppKit
import Combine
import HalodeckCore
import Observation
import SwiftUI

/// The menu-bar icon: one kind of click toggles Halodeck, the other opens the panel
/// (left = toggle by default; Settings → Advanced can swap them).
@MainActor
final class MenuBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let store: SettingsStore
    private let engine: Engine
    private var settingsSink: AnyCancellable?
    /// What the icon and its tooltip were last drawn for.
    private var shown: (enabled: Bool, state: EngineState, update: String?)?

    init(engine: Engine, store: SettingsStore, openSettings: @escaping () -> Void) {
        self.engine = engine
        self.store = store
        super.init()

        popover.behavior = .transient
        let panel = PanelView(store: store, engine: engine, dismiss: { [weak self] in self?.popover.performClose(nil) }) {
            [weak self] in
            self?.popover.performClose(nil)
            openSettings()
        }
        popover.contentViewController = NSHostingController(rootView: panel)

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Only the on/off switch and the engine's state change the icon, not every slider tick.
        settingsSink = store.$settings.map(\.enabled).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in MainActor.assumeIsolated { self?.updateIcon(enabled: enabled) } }
        watchEngineState()
        watchUpdates()
    }

    /// Redraws the icon whenever the engine's state changes (Observation fires once per change, so
    /// this re-arms itself each time).
    private func watchEngineState() {
        withObservationTracking { _ = engine.state } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.updateIcon(enabled: self.store.settings.enabled)
                    self.watchEngineState()
                }
            }
        }
    }

    /// Redraws the icon when a new version starts or stops waiting.
    private func watchUpdates() {
        withObservationTracking { _ = UpdateService.shared.availableVersion } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.updateIcon(enabled: self.store.settings.enabled)
                    self.watchUpdates()
                }
            }
        }
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        let togglesOnPrimary = store.settings.menuBarClick == .toggle
        if secondary == togglesOnPrimary {
            showPanel()
        } else {
            popover.performClose(nil)
            store.settings.enabled.toggle()
        }
    }

    private func showPanel() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateIcon(enabled: Bool) {
        let state = engine.state, update = UpdateService.shared.availableVersion
        if let shown, shown.enabled == enabled, shown.state == state, shown.update == update { return }
        shown = (enabled, state, update)
        let on = enabled && state != .needsAccessibility
        item.button?.image = MenuBarIcon.image(on: on, dot: update != nil)
        let status = switch state {
        case .needsAccessibility: "Halodeck needs Accessibility access"
        case .noTrackpad: "Halodeck: no trackpad found"
        default: enabled ? "Halodeck is on" : "Halodeck is off"
        }
        item.button?.toolTip = update.map { "\(status). Version \($0) is available" } ?? status
    }
}
