import HalodeckCore
import SwiftUI

struct SidesSection: View {
    @ObservedObject var store: SettingsStore
    let engine: Engine
    @Binding var selection: ZoneSelection?
    /// Switches the window to the Advanced tab, where feedback is set up (from the Feedback column when nothing can play).
    var openFeedback: () -> Void

    private let order: [Side] = [.left, .right, .top, .bottom]

    var body: some View {
        sidesTable
        Text("With Swipe off, press until the trackpad clicks, then slide. With Swipe on, a plain swipe along the side is enough; on the top and bottom it has to start right at the edge.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        if !store.settings.anyFeedback {
            HStack(spacing: 6) {
                Image(systemName: "speaker.slash").foregroundStyle(.secondary)
                Text("Haptic and sound feedback are both off.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Feedback settings", action: openFeedback)
                    .buttonStyle(.link)
            }
            .font(.caption)
            .padding(.horizontal, 4)
        }
    }

    private var sidesTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
            GridRow {
                TableHeader(title: "Side")
                TableHeader(title: "Action")
                columnHeader("Swipe", symbol: "hand.draw", isOn: allOn(\.swipeWithoutClick))
                    .help("Start with a plain swipe, without clicking. Click to set every side.")
                columnHeader("Feedback", symbol: "waveform", isOn: allOn(\.ticksEnabled),
                             inEffect: store.settings.anyFeedback, whenOff: openFeedback)
                    .help(store.settings.anyFeedback
                          ? "A tap and a sound at each step, as set in Advanced. Click to set every side."
                          : "Haptic and sound feedback are both off. Click to open the Feedback settings.")
            }
            .padding(.vertical, 10)

            ForEach(order, id: \.self) { side in
                Divider().gridCellUnsizedAxes(.horizontal)
                sideRow(side)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)   // same width as the boxes below
        .settingsCard(clipsContent: true)
    }

    /// A header that sets the column for every side. When the column has no effect (`inEffect` false)
    /// it is dimmed and a click runs `whenOff` instead.
    private func columnHeader(_ title: String, symbol: String, isOn: Binding<Bool>,
                              inEffect: Bool = true, whenOff: @escaping () -> Void = {}) -> some View {
        Button { if inEffect { isOn.wrappedValue.toggle() } else { whenOff() } } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue && inEffect ? Theme.accent : Color.secondary)
                TableHeader(title: title)
            }
            .opacity(inEffect ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .gridColumnAlignment(.center)
        .accessibilityLabel("\(title) for every side")
    }

    private func allOn(_ key: WritableKeyPath<HalodeckSettings, [Side: Bool]>) -> Binding<Bool> {
        Binding(get: { Side.allCases.allSatisfy { store.settings[keyPath: key][$0] ?? true } },
                set: { on in for side in Side.allCases { store.settings[keyPath: key][side] = on } })
    }

    private func flag(_ key: WritableKeyPath<HalodeckSettings, [Side: Bool]>, _ side: Side) -> Binding<Bool> {
        Binding(get: { store.settings[keyPath: key][side] ?? true },
                set: { store.settings[keyPath: key][side] = $0 })
    }

    @ViewBuilder private func sideRow(_ side: Side) -> some View {
        SideTableRow(store: store, engine: engine, side: side, selected: selection == .side(side),
                     swipe: flag(\.swipeWithoutClick, side), ticks: flag(\.ticksEnabled, side),
                     feedbackOn: store.settings.anyFeedback)
            .id(ZoneSelection.side(side))
            .onTapGesture { selection = .side(side) }
    }
}

private struct SideTableRow: View {
    @ObservedObject var store: SettingsStore
    let engine: Engine
    let side: Side
    let selected: Bool
    @Binding var swipe: Bool
    @Binding var ticks: Bool
    /// False when haptic and sound are both off: the Feedback chip then has nothing to switch.
    let feedbackOn: Bool

    var body: some View {
        let function = store.settings.sides[side] ?? .nothing
        let live = store.settings.activeSides[side] != nil && store.settings.enabled && isOn(function)
        mainRow(function: function, live: live)
        if function == .customKeys {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                HStack(spacing: 14) {
                    shortcut(up: true)
                    shortcut(up: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridCellColumns(3)
            }
            .padding(.bottom, 10)
        }
    }

    private func shortcut(up: Bool) -> some View {
        let arrow = side.isVertical ? (up ? "arrow.up" : "arrow.down") : (up ? "arrow.right" : "arrow.left")
        let slide = side.isVertical ? (up ? "Slide up" : "Slide down") : (up ? "Slide right" : "Slide left")
        let combo = Binding<KeyCombo?>(
            get: { up ? store.settings.customKeys[side]?.up : store.settings.customKeys[side]?.down },
            set: { value in
                var keys = store.settings.customKeys[side] ?? CustomKeys()
                if up { keys.up = value } else { keys.down = value }
                store.settings.customKeys[side] = keys
            })
        return HStack(spacing: 6) {
            Image(systemName: arrow).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .help(slide)
            CompactKeyRecorder(combo: combo, placeholder: "Record", clearHelp: "Clear this shortcut",
                               onClear: { combo.wrappedValue = nil })
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(slide) presses")
    }

    @ViewBuilder private func mainRow(function: SideAction, live: Bool) -> some View {
        GridRow {
            HStack(spacing: 10) {
                SideGlyph(sides: [side], highlight: live ? Theme.accent : .secondary)
                    .shadow(color: Theme.glow.opacity(live ? 0.5 : 0), radius: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(side.rawValue.capitalized).fontWeight(.medium)
                        .foregroundStyle(selected ? Theme.accent : .primary)
                    if function == .brightness && !engine.brightnessAvailable {
                        Text("Needs a built-in display").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minWidth: 120, alignment: .leading)

            actionMenu(function)

            ChipToggle(symbol: "hand.draw", isOn: $swipe, help: side.isVertical
                       ? "Swipe without clicking" : "Swipe without clicking (start at the edge)")
                .disabled(function == .nothing)
                .gridColumnAlignment(.center)
            ChipToggle(symbol: "waveform", isOn: $ticks, help: feedbackOn
                       ? "A tap and a sound at each step, as set in Advanced"
                       : "Haptic and sound feedback are both off in Advanced")
                .disabled(function == .nothing || !feedbackOn)
                .gridColumnAlignment(.center)
        }
        .padding(.vertical, 9)
    }

    private func isOn(_ function: SideAction) -> Bool {
        function != .brightness || engine.brightnessAvailable
    }

    private func actionMenu(_ function: SideAction) -> some View {
        Menu {
            ForEach(SideAction.allCases, id: \.self) { f in
                if f == .nothing { Divider() }
                Button { store.settings.sides[side] = f } label: { Label(f.title, systemImage: f.symbol) }
            }
        } label: {
            Label(function.title, systemImage: function.symbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(function == .nothing ? .secondary : Theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 10).padding(.trailing, 26).padding(.vertical, 5)
        .frame(minWidth: 210, maxWidth: .infinity)   // the Action column takes the spare width
        .actionMenuChrome()
        .accessibilityLabel("\(side.rawValue.capitalized) side action: \(function.title)")
    }
}

private struct ChipToggle: View {
    let symbol: String
    @Binding var isOn: Bool
    var help: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? (isEnabled ? Color.white : Theme.accent) : Color.secondary)
                .frame(width: 36, height: 24)
                .background(Capsule().fill(isOn && isEnabled ? Theme.accent : Color.primary.opacity(0.07)))
                .shadow(color: Theme.glow.opacity(isOn && isEnabled ? 0.4 : 0), radius: 3)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(isOn ? "On" : "Off")
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
