import HalodeckCore
import ServiceManagement
import SwiftUI

struct AdvancedPage: View {
    @ObservedObject var store: SettingsStore
    let engine: Engine
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        SectionHeader(title: "General")
        general
        SectionHeader(title: "Feedback")
        feedback
        SectionHeader(title: "Indicator")
        indicator
        SectionHeader(title: "Tuning")
        tuning
    }

    private var general: some View {
        SettingsBox {
            SettingsRow(title: "Launch at login", subtitle: loginError) {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)).labelsHidden()
            }
            SettingsRow(title: "Clicking the menu-bar icon",
                        subtitle: store.settings.menuBarClick == .toggle ? "Right-click opens the panel" : "Right-click switches Halodeck on or off") {
                Picker("Clicking the menu-bar icon", selection: $store.settings.menuBarClick) {
                    Text("Toggle Halodeck").tag(MenuBarClick.toggle)
                    Text("Open panel").tag(MenuBarClick.openPanel)
                }
                .labelsHidden().settingsPopUp()
            }
            SettingsRow(title: "Accessibility", subtitle: "Needed to see trackpad clicks and to press keys") {
                if engine.state == .needsAccessibility {
                    HStack(spacing: 8) {
                        Text("Missing").foregroundStyle(.orange)
                        Button("Grant…") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                } else {
                    Label("Granted", systemImage: "circle.fill")
                        .labelStyle(DotLabelStyle(color: .green))
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    @ViewBuilder private var feedback: some View {
        SettingsBox {
            SettingsRow(title: "Haptic feedback",
                        subtitle: "A light tap at every step. It stops at 0% and 100%") {
                HStack(spacing: 8) {
                    Picker("Haptic feedback", selection: $store.settings.hapticStrength) {
                        Text("Off").tag(HapticStrength.off)
                        Text("Soft").tag(HapticStrength.soft)
                        Text("Medium").tag(HapticStrength.medium)
                        Text("Strong").tag(HapticStrength.strong)
                    }
                    .labelsHidden().settingsPopUp()
                    Button("Try") { Haptics.tickAll(id: store.settings.hapticTick) }
                        .disabled(!store.settings.hapticsEnabled)
                }
            }
        }
        SettingsBox {
            SettingsRow(title: "Sound feedback",
                        subtitle: "A short sound at every step, higher as the level goes up. Try plays it from 0% to 100%") {
                HStack(spacing: 8) {
                    Picker("Sound feedback", selection: $store.settings.soundChoice) {
                        Text("Off").tag(SoundStyle?.none)
                        Divider()
                        ForEach(SoundStyle.allCases, id: \.self) { Text($0.title).tag(SoundStyle?.some($0)) }
                    }
                    .labelsHidden().settingsPopUp()
                    .onChange(of: store.settings.soundChoice) { _, choice in if let choice { SoundTicks.preview(choice) } }
                    Button("Try") { if let choice = store.settings.soundChoice { SoundTicks.preview(choice) } }
                        .disabled(store.settings.soundChoice == nil)
                }
            }
        }
    }

    private var indicator: some View {
        SettingsBox {
            SettingsRow(title: "On-screen indicator",
                        subtitle: "A pill under the menu bar for tabs, seek and tracks, which macOS has no indicator for") {
                Toggle("On-screen indicator", isOn: $store.settings.showIndicator).labelsHidden()
            }
            SettingsRow(title: "Show in the notch",
                        subtitle: "On a MacBook with a notch, show volume, brightness and actions in the notch instead of the pill") {
                Toggle("Show in the notch", isOn: $store.settings.showInNotch).labelsHidden()
            }
            SettingsRow(title: "Notch light", subtitle: "A light around the notch while it shows something") {
                Picker("Notch light", selection: $store.settings.notchEffect) {
                    Text("Level gauge").tag(NotchEffect.levelGauge)
                    Text("Every step").tag(NotchEffect.everyStep)
                    Divider()
                    Text("Off").tag(NotchEffect.off)
                }
                .labelsHidden().settingsPopUp()
            }
            .disabled(!store.settings.showInNotch)
            SettingsRow(title: "Mute signs", subtitle: "Which side of the notch the sound and microphone signs sit on") {
                Picker("Mute signs", selection: $store.settings.muteSignsSide) {
                    Text("Right of the notch").tag(MuteSignsSide.right)
                    Text("Left of the notch").tag(MuteSignsSide.left)
                }
                .labelsHidden().settingsPopUp()
            }
            .disabled(!store.settings.showInNotch)
        }
    }

    private var tuning: some View {
        SettingsBox {
            SettingsRow(title: "Side width",
                        subtitle: "\(Int((store.settings.sideWidthFraction * 100).rounded()))% of the trackpad") {
                Slider(value: $store.settings.sideWidthFraction, in: HalodeckSettings.sideWidthRange, step: 0.01)
                    .frame(width: 180)
            }
            SettingsRow(title: "Slide per step",
                        subtitle: String(format: "%g mm", store.settings.slidePerStepMM)) {
                Slider(value: $store.settings.slidePerStepMM, in: HalodeckSettings.slidePerStepRange, step: 0.5)
                    .frame(width: 180)
            }
            SettingsRow(title: "Fine control", subtitle: "Hold for steps four times smaller") {
                Picker("Fine control", selection: $store.settings.fineControlKey) {
                    Text("⌥ Option").tag(FineControlKey.option)
                    Text("Off").tag(FineControlKey.off)
                }
                .labelsHidden().settingsPopUp()
            }
            SettingsRow(title: "Coarse control", subtitle: "Hold to jump by eighths") {
                Picker("Coarse control", selection: $store.settings.coarseControlKey) {
                    Text("⇧ Shift").tag(CoarseControlKey.shift)
                    Text("Off").tag(CoarseControlKey.off)
                }
                .labelsHidden().settingsPopUp()
            }
        }
    }
}

struct DotLabelStyle: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            configuration.title.fontWeight(.semibold)
        }
    }
}
