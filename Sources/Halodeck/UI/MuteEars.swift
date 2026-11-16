import AppKit
import HalodeckCore
import SwiftUI

/// Drawn as the whole notch shape plus the ears, so its bottom corners match the notch indicator's on
/// both sides. A static sign that appears and goes without animation (nothing for Reduce Motion to calm).
@MainActor
final class MuteEars {
    private var panel: NSPanel?
    private var host: NSHostingView<MuteEarsView>?

    /// Also re-places the panel, so a call after the screens changed puts it on the notch's new position.
    func update(sound: Bool, microphone: Bool, side: MuteSignsSide) {
        let layout = side.layout(sound: sound, microphone: microphone)
        guard !layout.isEmpty, let geometry = NotchHUD.firstNotch()?.geometry else {
            panel?.orderOut(nil)
            return
        }
        let view = MuteEarsView(notchWidth: geometry.notch.width, notchHeight: geometry.notch.height, layout: layout)
        if let host {
            host.rootView = view
        } else {
            let host = NotchHUD.notchHostingView(view)
            // Above the menu bar, just under the notch indicator (which covers it while it's open).
            panel = HUDPanel.make(level: NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1), content: host)
            self.host = host
        }
        guard let panel else { return }
        panel.setFrame(geometry.earFrame(leftSigns: layout.left.count, rightSigns: layout.right.count), display: true)
        panel.orderFrontRegardless()
    }
}

struct MuteSign: View {
    let kind: MuteSignKind

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
    }

    private var symbol: String {
        switch kind {
        case .sound: "speaker.slash.fill"
        case .microphone: "mic.slash.fill"
        }
    }
}

struct MuteEarsView: View {
    let notchWidth: CGFloat
    /// The notch's exact height: the window's own may be rounded to whole points.
    let notchHeight: CGFloat
    let layout: MuteSignsLayout

    var leftEar: CGFloat { CGFloat(layout.left.count) * NotchGeometry.muteSignWidth }
    var rightEar: CGFloat { CGFloat(layout.right.count) * NotchGeometry.muteSignWidth }

    var width: CGFloat { 2 * NotchGeometry.shoulder + leftEar + notchWidth + rightEar }

    var body: some View {
        GeometryReader { proxy in
            let h = notchHeight
            ZStack(alignment: .topLeading) {
                NotchShape()
                    .fill(Color.black)
                    .frame(width: proxy.size.width, height: h + NotchHUD.bleed)
                    .offset(y: -NotchHUD.bleed)
                ear(layout.left).offset(x: NotchGeometry.shoulder)
                ear(layout.right).offset(x: NotchGeometry.shoulder + leftEar + notchWidth)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func ear(_ signs: [MuteSignKind]) -> some View {
        HStack(spacing: 0) {
            ForEach(signs, id: \.self) { kind in
                MuteSign(kind: kind).frame(width: NotchGeometry.muteSignWidth, height: notchHeight)
            }
        }
    }

    private var accessibilityText: String {
        let signs = layout.left + layout.right
        return switch (signs.contains(.sound), signs.contains(.microphone)) {
        case (true, true): "Sound off and microphone muted"
        case (true, false): "Sound off"
        default: "Microphone muted"
        }
    }
}
