import HalodeckCore
import SwiftUI

struct BindingsPage: View {
    @ObservedObject var store: SettingsStore
    let engine: Engine
    /// Switches the window to the Advanced tab, where feedback is set up (from the Feedback column when nothing can play).
    var openFeedback: () -> Void = {}
    @State private var selection: ZoneSelection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 14) {
                TrackpadMapView(settings: store.settings, brightnessAvailable: engine.brightnessAvailable,
                                size: .large, selection: $selection)
                    .frame(maxHeight: 250)
                    .frame(maxWidth: .infinity)

                SectionHeader(title: "Sides")
                SidesSection(store: store, engine: engine, selection: $selection, openFeedback: openFeedback)

                SectionHeader(title: "Corners")
                CornersSection(store: store, selection: $selection)
            }
            .onChange(of: selection) { _, zone in
                guard let zone else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(zone, anchor: .center) }
            }
        }
    }
}
