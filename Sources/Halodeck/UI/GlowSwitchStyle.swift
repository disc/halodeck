import SwiftUI

struct GlowSwitchStyle: ToggleStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        GlowSwitch(configuration: configuration, compact: compact)
    }
}

/// The switch itself: a button, so it takes keyboard focus (Full Keyboard Access) and Space toggles it.
private struct GlowSwitch: View {
    let configuration: ToggleStyleConfiguration
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let on = configuration.isOn
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? Theme.accent : Color.primary.opacity(0.13))
                    .shadow(color: Theme.glow.opacity(on && isEnabled ? 0.45 : 0), radius: 4)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                    .padding(2)
            }
            .frame(width: compact ? 32 : 40, height: compact ? 19 : 23)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: on)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
