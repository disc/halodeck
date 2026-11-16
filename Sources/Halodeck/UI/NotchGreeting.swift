import AppKit
import HalodeckCore
import os
import SwiftUI

@MainActor
final class NotchGreetingPresenter {
    private var panel: NSPanel?
    private var ear: CGFloat = 0
    var reduceMotion = false
    /// Called whenever a greeting appears or goes (the muted signs hide under it).
    var onVisibilityChange: @MainActor () -> Void = {}

    var isShowing: Bool { panel != nil }

    func greet(label: String = NotchGreeting.name, reverse: Bool = false, flipsIcon: Bool = false) {
        panel?.orderOut(nil)
        panel = nil
        guard let geometry = NotchHUD.firstNotch()?.geometry else {
            onVisibilityChange()
            return
        }
        ear = NotchHUD.earWidth(for: .text(label), levelAsNumber: true)
        // Driven by the clock, not by state changes: an animation started right after the window
        // appears can be skipped if SwiftUI hasn't drawn the starting state yet.
        let start = Date().addingTimeInterval(0.15)
        let notchSize = CGSize(width: geometry.notch.width, height: geometry.notch.height)
        let panel = HUDPanel.make(level: .popUpMenu, content: NotchHUD.notchHostingView(
            NotchGreeting(notch: notchSize, ear: ear, margin: NotchHUD.glowMargin, start: start, label: label,
                          reverse: reverse, flipsIcon: flipsIcon, reduceMotion: reduceMotion)))
        panel.setFrame(geometry.windowFrame(earWidth: ear, margin: NotchHUD.glowMargin), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        onVisibilityChange()
        Logger(subsystem: "io.github.disc.halodeck", category: "notch")
            .notice("greeting at the notch \(String(describing: geometry.notch), privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + NotchGreeting.end + 0.1) { [weak self] in
            panel.orderOut(nil)
            guard let self, self.panel === panel else { return }
            self.panel = nil
            onVisibilityChange()
        }
    }

    /// Takes a greeting that is still up off the screen at once: the indicator or a corner's glow is
    /// about to take the notch, and two shapes at the notch must never show together.
    func dismiss() {
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        onVisibilityChange()
    }

    func screensChanged() {
        guard let panel else { return }
        if let geometry = NotchHUD.firstNotch()?.geometry {
            panel.setFrame(geometry.windowFrame(earWidth: ear, margin: NotchHUD.glowMargin), display: true)
        } else {
            dismiss()
        }
    }
}

/// The greeting, as a function of time since `start` (or a fixed `time`, for snapshots).
struct NotchGreeting: View {
    static let name = "Halodeck"
    let notch: CGSize
    let ear: CGFloat
    let margin: CGFloat
    var start = Date()
    var time: Double?
    var label = NotchGreeting.name
    /// The light runs right to left (switching off).
    var reverse = false
    /// The app icon flips in (launch); otherwise it fades in with the label.
    var flipsIcon = false
    /// Fade in and out at full size, the light glowing round the whole outline instead of running.
    var reduceMotion = false

    // The timeline, in seconds.
    static let grown = 0.35, lightStart = 0.3, lightRun = 1.4, shrinkStart = 2.3, end = 2.6
    /// When the ears' content (and the flipping icon) starts to come in.
    static let contentStart = 0.15

    var body: some View {
        TimelineView(.animation(paused: time != nil)) { context in
            frame(at: time ?? context.date.timeIntervalSince(start))
        }
        .ignoresSafeArea()
    }

    private func frame(at t: Double) -> some View {
        let grey = greyness(t)
        let colours = lightColours(grey)
        let s = NotchGeometry.shoulder
        let growth = Self.growth(t)
        let width = notch.width + 2 * ear * (reduceMotion ? 1 : growth)   // the black shape, shoulders aside
        let total = notch.width + 2 * ear + 2 * s + 2 * margin            // the window
        let run = Self.light(t) * 1.35
        // Reduce Motion: the whole outline, brightest halfway through the light's run.
        let trim = reduceMotion ? (from: 0.0, to: 1.0)
            : reverse ? (from: 1 - min(1, run), to: 1 - max(0, run - 0.35))
            : (from: max(0, run - 0.35), to: min(1, run))
        let lightOpacity = Self.lightOpacity(t) * (reduceMotion ? sin(.pi * min(1, max(0, (t - Self.lightStart) / Self.lightRun))) : 1)
        let iconInset = Metrics.greetingIconInset, labelInset = Metrics.notchEarInset
        return ZStack(alignment: .top) {
            NotchShape()
                .fill(Color.black)
                .frame(width: width + 2 * s, height: notch.height + NotchHUD.bleed)
                .offset(y: -NotchHUD.bleed)
            HStack(spacing: 0) {
                Group {
                    if reverse {
                        Image(nsImage: Self.offGlyph).renderingMode(.template).resizable()
                            .aspectRatio(contentMode: .fit).foregroundStyle(.white)
                    } else {
                        let pose = flipsIcon ? IconFlip.pose(at: t - Self.contentStart, reduceMotion: reduceMotion) : .rest
                        Image(nsImage: NSApp.applicationIconImage).resizable()
                            .rotation3DEffect(.degrees(pose.rotationY), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                            .scaleEffect(pose.scale)
                            .opacity(pose.opacity)
                    }
                }
                .frame(width: 20, height: 20)
                .frame(width: max(0, ear - iconInset), alignment: .leading)
                .padding(.leading, iconInset)
                Spacer().frame(width: notch.width)
                Text(label)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .fixedSize()
                    .frame(width: max(0, ear - labelInset), alignment: .trailing)
                    .padding(.trailing, labelInset)
            }
            .frame(width: notch.width + 2 * ear, height: notch.height)
            .opacity(Self.contentOpacity(t))
            .frame(width: width, height: notch.height)
            .clipped()
            NotchOutline(notch: CGSize(width: width, height: notch.height), margin: (total - width) / 2)
                .trim(from: trim.from, to: trim.to)
                .stroke(LinearGradient(colors: colours, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .shadow(color: colours[0].opacity(0.9), radius: 3)
                .shadow(color: colours[1].opacity(0.7), radius: 8)
                .opacity(lightOpacity)
                .frame(width: total, height: notch.height + margin)
        }
        .opacity(reduceMotion ? growth : 1)
        .frame(width: total, height: notch.height + margin, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @MainActor private static let offGlyph = MenuBarIcon.image(on: false)

    /// 0 = full colour, 1 = grey. Switching on stays in colour; switching off, the light starts in
    /// colour and drains to grey while it runs back.
    private func greyness(_ t: Double) -> Double {
        reverse ? min(1, max(0, (t - Self.lightStart) / (Self.lightRun * 0.8))) : 0
    }

    private func lightColours(_ grey: Double) -> [Color] {
        func mix(_ c: (red: Double, green: Double, blue: Double), _ g: Double) -> Color {
            Color(red: c.red + (g - c.red) * grey, green: c.green + (g - c.green) * grey, blue: c.blue + (g - c.blue) * grey)
        }
        return [mix(Theme.notchLightTealRGB, 0.88), mix(Theme.notchLightBlueRGB, 0.55)]
    }

    func time(_ t: Double) -> NotchGreeting {
        var copy = self
        copy.time = t
        return copy
    }

    /// 0 = the bare notch, 1 = fully grown.
    static func growth(_ t: Double) -> Double {
        if t <= 0 || t >= end { return 0 }
        if t < grown { return 1 - pow(1 - t / grown, 3) }                        // ease out
        if t < shrinkStart { return 1 }
        return 1 - pow((t - shrinkStart) / (end - shrinkStart), 2)                // ease in
    }

    static func contentOpacity(_ t: Double) -> Double {
        let fadeIn = min(1, max(0, (t - contentStart) / 0.2))
        let fadeOut = min(1, max(0, (t - (shrinkStart - 0.1)) / 0.15))
        return fadeIn * (1 - fadeOut)
    }

    /// How far the light has run, 0...1 (eased).
    static func light(_ t: Double) -> Double {
        Easing.inOut(min(1, max(0, (t - lightStart) / lightRun)))
    }

    static func lightOpacity(_ t: Double) -> Double {
        t < lightStart ? 0 : 1 - min(1, max(0, (t - (lightStart + lightRun - 0.2)) / 0.5))
    }
}
