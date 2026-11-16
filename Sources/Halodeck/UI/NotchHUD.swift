import AppKit
import HalodeckCore
import SwiftUI

/// The indicator on a MacBook with a notch: a black shape that grows sideways out of the notch, with
/// the icon in the left "ear" and the value in the right one, then shrinks back into it. Same black as
/// the notch, so it reads as the hardware lighting up.
///
/// Everything is driven by the clock (a TimelineView reading times kept in `NotchModel`), not by
/// SwiftUI state animations, so the shape, its contents and the light always move together.
@MainActor
final class NotchHUD {
    static let maxEar: CGFloat = 190
    /// The window always has room for the widest ear plus a bump's push, so the shape can grow without
    /// resizing it.
    static let windowEar = maxEar + ceil(NotchBump.reach)
    /// The black shape reaches this far above the top of its window (off the screen), so no hairline
    /// of the menu bar can show between it and the screen's edge, whatever the rounding.
    static let bleed: CGFloat = 2
    static let glowMargin: CGFloat = 16
    static let bareEar: CGFloat = 40
    /// Same rhythm as the pill.
    private static let stayDuration = 0.9

    let model = NotchModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// Set by a corner click and used up by the next show: a notch opened for a corner plays the
    /// corner's glow instead of the run light.
    private var cornerShowing = false
    /// Called whenever the indicator appears or disappears (the muted signs hide under it).
    var onVisibilityChange: @MainActor () -> Void = {}

    var isVisible: Bool { panel?.isVisible == true }

    static func geometry(for screen: NSScreen) -> NotchGeometry? {
        guard var left = screen.auxiliaryTopLeftArea, var right = screen.auxiliaryTopRightArea else { return nil }
        // The areas are documented loosely: treat them as screen-relative if they don't lie on the screen.
        if !screen.frame.insetBy(dx: -1, dy: -1).contains(CGPoint(x: left.minX, y: left.minY)) {
            left = left.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
            right = right.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        }
        return NotchGeometry(screenFrame: screen.frame, leftArea: left, rightArea: right)
    }

    static func firstNotch() -> (screen: NSScreen, geometry: NotchGeometry)? {
        for screen in NSScreen.screens {
            if let geometry = geometry(for: screen) { return (screen, geometry) }
        }
        return nil
    }

    /// A hosting view with no safe area: over the notch macOS reports one, and SwiftUI would push the
    /// shape down out of it, leaving a see-through strip at the top.
    static func notchHostingView<V: View>(_ view: V) -> NSHostingView<V> {
        let host = NSHostingView(rootView: view)
        host.safeAreaRegions = []
        return host
    }

    /// Both ears get the width the value needs, so the shape stays centred.
    static func earWidth(for content: HUDContent, levelAsNumber: Bool) -> CGFloat {
        switch content {
        case .level: return levelAsNumber ? 64 : 104
        case let .text(text):
            let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            return min(maxEar, max(64, ceil(width) + 26))
        }
    }

    /// Shows the indicator in `screen`'s notch; false when that screen has none. `direction` is the
    /// step's (+1 up/right, -1 down/left), for the lights that run with it.
    func show(symbol: String, content: HUDContent, image: NSImage?, direction: Int, on screen: NSScreen) -> Bool {
        guard let geometry = Self.geometry(for: screen) else { return false }
        let panel = place(on: geometry)
        let now = Date()
        let ear = Self.earWidth(for: content, levelAsNumber: model.levelAsNumber)
        model.symbol = symbol
        model.image = image
        model.content = content
        model.showsContent = true
        defer { cornerShowing = false }
        if !panel.isVisible {
            if !cornerShowing { model.lightStep(at: now, direction: direction, content: content, opening: true) }
            open(panel, ear: ear, at: now)
        } else {
            if model.closingAt != nil {   // it was shrinking back: grow again from where it is
                let open = model.openness(at: now)
                model.closingAt = nil
                model.openedAt = now.addingTimeInterval(-NotchModel.growTime * open)
            }
            model.earFrom = model.ear(at: now)
            model.earTo = ear
            model.earChangedAt = now
            if !cornerShowing { model.lightStep(at: now, direction: direction, content: content, opening: false) }
            model.active = true
        }
        scheduleHide()
        return true
    }

    /// A slide ran into 100% (`atTop`) or 0%.
    func bump(atTop: Bool) {
        guard isVisible, model.closingAt == nil else { return }
        model.bump = NotchBump(at: Date(), top: atTop)
    }

    /// A corner was clicked: a burst of light from the notch's matching corner (two for a double
    /// click). Starts once the notch has grown out (the corner's action usually opens it right now).
    func burst(left: Bool, top: Bool, clicks: Int) {
        let open = isVisible && model.closingAt == nil
        cornerShowing = true
        model.bursts.add(left: left, top: top, clicks: clicks,
                         at: Date().addingTimeInterval(open ? 0 : NotchModel.growTime * 0.8))
    }

    /// After a corner's action: if it put nothing in the notch, open the notch with small empty ears
    /// for a moment so the corner's glow has somewhere to show.
    func hostBursts(on screen: NSScreen?) {
        defer { cornerShowing = false }   // used up even when the action showed nothing
        guard !isVisible, let screen, let geometry = Self.geometry(for: screen) else { return }
        model.showsContent = false
        open(place(on: geometry), ear: Self.bareEar, at: Date())
        scheduleHide()
    }

    private func open(_ panel: NSPanel, ear: CGFloat, at now: Date) {
        model.openedAt = now
        model.closingAt = nil
        model.earFrom = ear
        model.earTo = ear
        model.earChangedAt = now
        model.active = true
        panel.orderFrontRegardless()
        onVisibilityChange()
    }

    func screensChanged(main screen: NSScreen?) {
        guard isVisible else { return }
        guard let screen, let geometry = Self.geometry(for: screen) else {
            hideNow()
            return
        }
        place(on: geometry)
    }

    @discardableResult
    private func place(on geometry: NotchGeometry) -> NSPanel {
        let panel = self.panel ?? HUDPanel.make(level: .popUpMenu,   // above the menu bar and its items
                                                content: Self.notchHostingView(NotchIndicator(model: model)))
        self.panel = panel
        panel.setFrame(geometry.windowFrame(earWidth: Self.windowEar, margin: Self.glowMargin), display: false)
        model.notchWidth = geometry.notch.width
        model.height = geometry.notch.height
        return panel
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let closing = Date()
            model.closingAt = closing
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchModel.shrinkTime + 0.05) { [weak self] in
                guard let self, model.closingAt == closing else { return }   // shown again meanwhile
                hideNow()
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stayDuration, execute: work)
    }

    private func hideNow() {
        hideWork?.cancel()
        panel?.orderOut(nil)
        model.active = false
        onVisibilityChange()
    }
}

/// The shape, its contents and the light, at the moment the timeline gives (or `date`, for snapshots).
struct NotchIndicator: View {
    let model: NotchModel
    var date: Date?

    var body: some View {
        TimelineView(.animation(paused: date != nil || !model.active)) { context in
            frame(at: date ?? context.date)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }

    private func frame(at now: Date) -> some View {
        let s = NotchGeometry.shoulder, m = NotchHUD.glowMargin, h = model.height
        let open = model.openness(at: now)
        // Reduce Motion: fully grown from the start, the whole indicator fading in and out instead.
        let still = model.reduceMotion
        let fade = still ? 1 : open
        let ear = still ? model.earTo : model.ear(at: now) * open
        // The end-of-range bump widens one ear for a moment; the notch's centre stays put.
        let bump = model.bump(at: now)
        let pushLeft = bump?.left ?? 0, pushRight = bump?.right ?? 0
        let width = model.notchWidth + 2 * ear + pushLeft + pushRight
        let shift = (pushRight - pushLeft) / 2
        let total = model.notchWidth + 2 * NotchHUD.windowEar + 2 * s + 2 * m
        let inset = Metrics.notchEarInset
        return ZStack(alignment: .top) {
            if model.effect == .levelGauge, case .level = model.content {
                // Behind the black shape, so the line's glow only spreads outward, not into the notch.
                NotchGlowStroke(from: 0, to: model.gauge.value(at: now), bottomOnly: true)
                    .opacity(fade)
                    .frame(width: width + 2 * s, height: h)
            }
            if let bump, bump.light > 0 {
                // Behind the black shape, over the gauge's line, so only the outside of the pushed side's corner glows.
                NotchBumpLight(right: bump.rightCorner)
                    .opacity(bump.light)
                    .frame(width: width + 2 * s, height: h)
            }
            NotchShape()
                .fill(Color.black)
                .frame(width: width + 2 * s, height: h + NotchHUD.bleed)
                .offset(y: -NotchHUD.bleed)
            cornerGlow(at: now)
                .frame(width: width + 2 * s, height: h)
                .clipShape(NotchShape())
            HStack(spacing: 0) {
                // A pushed ear's content rides out with its edge.
                icon
                    .frame(width: max(0, model.earTo + pushLeft - inset), alignment: .leading)
                    .padding(.leading, inset)
                Spacer().frame(width: model.notchWidth)
                value
                    .frame(width: max(0, model.earTo + pushRight - inset), alignment: .trailing)
                    .padding(.trailing, inset)
            }
            .frame(width: model.notchWidth + 2 * model.earTo + pushLeft + pushRight, height: h)
            .foregroundStyle(.white)
            .opacity(model.showsContent ? fade : 0)
            .frame(width: width, height: h)
            .clipped()
            light(at: now, open: fade)
                .frame(width: width + 2 * s, height: h)
        }
        .offset(x: shift)
        .opacity(still ? open : 1)
        .frame(width: total, height: h + m, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func cornerGlow(at now: Date) -> some View {
        let live = model.bursts.live(at: now)
        return ZStack {
            ForEach(live.indices, id: \.self) { i in
                let burst = live[i]
                let colour = burst.left ? Theme.notchLightTeal : Theme.notchLightBlue
                let p = burst.progress
                let strength = 0.7 * pow(1 - p, 1.2) * (p < 0.12 ? p / 0.12 : 1)
                GeometryReader { proxy in
                    Rectangle()
                        .fill(LinearGradient(stops: [.init(color: colour.opacity(strength), location: 0),
                                                     .init(color: colour.opacity(0), location: 0.6)],
                                             startPoint: burst.top ? .top : .bottom,
                                             endPoint: burst.top ? .bottom : .top))
                        // Fades out sideways too, so it has no hard inner edge.
                        .mask(LinearGradient(colors: [.black, .black, .black.opacity(0)],
                                             startPoint: burst.left ? .leading : .trailing,
                                             endPoint: burst.left ? .trailing : .leading))
                        .frame(width: proxy.size.width / 4)   // the ear on the clicked side
                        .frame(maxWidth: .infinity, alignment: burst.left ? .leading : .trailing)
                }
            }
        }
    }

    @ViewBuilder private func light(at now: Date, open: Double) -> some View {
        switch model.effect {
        case .off:
            EmptyView()
        case .everyStep:
            // Every step's streak runs to the end; a fast slide shows several chasing each other.
            let live = model.streaks.live(at: now)
            if model.reduceMotion {
                glowInPlace(live.map { 1 - pow($0.progress, 3) }, open: open)
            } else {
                ZStack {
                    ForEach(live.indices, id: \.self) { i in
                        run(progress: live[i].progress, direction: live[i].direction, tail: 0.3, open: open)
                    }
                }
            }
        case .levelGauge:
            if case .level = model.content {
                EmptyView()   // the gauge is drawn behind the shape, in `frame(at:)`
            } else if model.reduceMotion {
                let live = model.comets.live(at: now)
                glowInPlace(live.map { 1 - pow($0.progress, 3) }, open: open,
                            lineWidth: live.map { CGFloat($0.lineWidth) }.max() ?? 2.5)
            } else {
                let live = model.comets.live(at: now)
                ZStack {
                    ForEach(live.indices, id: \.self) { i in
                        let comet = live[i]
                        run(progress: comet.progress, direction: comet.direction, tail: comet.tail, open: open,
                            lineWidth: comet.lineWidth)
                    }
                }
            }
        }
    }

    /// One light running along the outline, its head `progress` of the way and its tail `tail` long,
    /// fading as it ends. Up/right runs left to right along the outline; down/left the other way.
    private func run(progress: Double, direction: Int, tail: Double, open: Double,
                     lineWidth: CGFloat = 2.5) -> some View {
        let head = Easing.inOut(progress) * (1 + tail)
        let from = max(0, head - tail), to = min(1, head)
        return NotchGlowStroke(from: direction >= 0 ? from : 1 - to, to: direction >= 0 ? to : 1 - from,
                               lineWidth: lineWidth)
            .opacity(min(open, 1 - pow(progress, 3)))
    }

    /// Reduce Motion's stand-in for lights that run: the whole outline glows as brightly as the
    /// brightest of them would, and fades with it.
    @ViewBuilder private func glowInPlace(_ strengths: [Double], open: Double, lineWidth: CGFloat = 2.5) -> some View {
        if let strongest = strengths.max() {
            NotchGlowStroke(from: 0, to: 1, lineWidth: lineWidth).opacity(min(open, strongest))
        }
    }

    @ViewBuilder private var icon: some View {
        if let image = model.image {
            Image(nsImage: image).resizable().frame(width: 20, height: 20)
        } else {
            Image(systemName: model.symbol).font(.system(size: 15, weight: .semibold))
        }
    }

    @ViewBuilder private var value: some View {
        switch model.content {
        case let .level(level):
            if model.levelAsNumber {
                Text("\(Int((level * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit().lineLimit(1).fixedSize()
            } else {
                SegmentBar(level: level).frame(width: 78)
            }
        case let .text(text):
            Text(text).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
        }
    }
}
