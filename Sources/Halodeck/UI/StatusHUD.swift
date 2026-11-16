import AppKit
import QuartzCore
import SwiftUI

/// A pill under the menu bar, top right, styled like the macOS volume/brightness indicator, for things
/// macOS shows no indicator for (the microphone, direct brightness).
///
/// Built like Control Center builds its own: a Core Animation backdrop layer (private CABackdropLayer)
/// that blurs what is behind the window only lightly, a faint white wash and a bright hairline rim.
/// Liquid Glass (NSGlassEffectView) blurs far more and never looked the same.
@MainActor
final class StatusHUD {
    /// The look, measured from a screen recording of the system pill (2x pixels, grey levels: a 1 px
    /// line behind it spreads over ~6 px, flat areas lift from 22 to 41, the edge peaks at 134), then
    /// matched by eye side by side with it.
    struct Look {
        /// Backdrop blur radius, points.
        let blur = 1.35
        /// White wash over the blurred backdrop.
        let wash = 0.08
        /// Opacity of the 0.5 pt edge highlight.
        let rim = 0.48
        /// Opacity of the soft 1.5 pt band just inside the edge.
        let glow = 0.18
    }
    static let look = Look()

    /// The pill's size, measured from the system indicator.
    static let pillSize = NSSize(width: 306, height: 59)
    /// Gap between the menu bar / screen edge and the pill.
    private static let inset: CGFloat = 10
    /// Appearing and disappearing like the system pill.
    private static let appearDuration = 0.1, stayDuration = 0.9, disappearDuration = 0.25, smallScale = 0.94

    private var panel: NSPanel?
    private var host: NSHostingView<HUDPill>?
    private var backdrop: BackdropView?
    private var hideWork: DispatchWorkItem?
    /// True from the moment the pill starts appearing until it starts disappearing.
    private var isShown = false

    /// Reduce Motion: the pill only fades, without the scale.
    var reduceMotion = false
    /// Reduce Transparency: an opaque dark pill instead of the blurred backdrop.
    var reduceTransparency = false {
        didSet {
            guard reduceTransparency != oldValue, let host else { return }
            backdrop?.isHidden = reduceTransparency
            host.rootView = HUDPill(symbol: host.rootView.symbol, content: host.rootView.content,
                                    background: background)
        }
    }

    /// The pill is up, or on its way out.
    var isVisible: Bool { panel?.isVisible == true }

    private var background: HUDPill.Background {
        reduceTransparency ? .opaque : backdrop?.isLive == true ? .backdrop : .material
    }

    func show(symbol: String, content: HUDContent) {
        let panel = self.panel ?? HUDPanel.make(level: .statusBar, size: Self.pillSize, stationary: false)
        self.panel = panel
        let backdrop = self.backdrop ?? BackdropView(frame: NSRect(origin: .zero, size: Self.pillSize))
        self.backdrop = backdrop
        backdrop.isHidden = reduceTransparency
        let view = HUDPill(symbol: symbol, content: content, background: background)
        if let host {
            host.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: Self.pillSize)
            let container = NSView(frame: NSRect(origin: .zero, size: Self.pillSize))
            container.wantsLayer = true
            container.addSubview(backdrop)
            container.addSubview(host)
            panel.contentView = container
            self.host = host
        }
        place(on: NSScreen.main)
        hideWork?.cancel()
        let small = reduceMotion ? 1 : Self.smallScale
        // When it is already showing, only the content changes, like the system pill.
        if !isShown {
            isShown = true
            if !panel.isVisible {
                panel.alphaValue = 0
                setScale(small, animated: false)
            }
            panel.orderFrontRegardless()
            animate(alpha: 1, scale: 1, duration: Self.appearDuration, timing: .easeOut)
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            isShown = false
            animate(alpha: 0, scale: small, duration: Self.disappearDuration, timing: .easeIn) { [weak self] in
                guard let self, !isShown else { return }
                panel.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stayDuration, execute: work)
    }

    /// Takes the pill away at once (the indicator moved to the notch).
    func hide() {
        guard isShown || isVisible else { return }
        hideWork?.cancel()
        isShown = false
        panel?.orderOut(nil)
    }

    func screensChanged(main screen: NSScreen?) {
        guard isVisible else { return }
        place(on: screen)
    }

    private func place(on screen: NSScreen?) {
        guard let panel, let screen else { return }
        let top = screen.visibleFrame.maxY
        panel.setFrameOrigin(NSPoint(x: screen.frame.maxX - Self.pillSize.width - Self.inset,
                                     y: top - Self.pillSize.height - Self.inset))
    }

    private func animate(alpha: CGFloat, scale: CGFloat, duration: TimeInterval,
                         timing: CAMediaTimingFunctionName, completion: (@MainActor () -> Void)? = nil) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: timing)
            panel.animator().alphaValue = alpha
        }, completionHandler: { MainActor.assumeIsolated { completion?() } })
        setScale(scale, animated: true, duration: duration, timing: timing)
    }

    /// Scales the pill about its centre (the panel keeps its frame).
    private func setScale(_ scale: CGFloat, animated: Bool, duration: TimeInterval = 0,
                          timing: CAMediaTimingFunctionName = .default) {
        guard let layer = panel?.contentView?.layer else { return }
        let cx = Self.pillSize.width / 2, cy = Self.pillSize.height / 2
        var t = CATransform3DMakeTranslation(cx, cy, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        t = CATransform3DTranslate(t, -cx, -cy, 0)
        let from = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = t
        CATransaction.commit()
        guard animated else { return }
        let anim = CABasicAnimation(keyPath: "sublayerTransform")
        anim.fromValue = NSValue(caTransform3D: from)
        anim.toValue = NSValue(caTransform3D: t)
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: timing)
        layer.add(anim, forKey: "scale")
    }
}

/// A view whose layer blurs whatever is behind its window (other apps included): CABackdropLayer with a
/// gaussian blur, as NSVisualEffectView uses internally, but with a radius we choose. `isLive` is false
/// if the private classes are missing, and the pill then draws a SwiftUI material instead.
final class BackdropView: NSView {
    private(set) var isLive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = frame.height / 2
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        applyBlur()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func makeBackingLayer() -> CALayer {
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else { return CALayer() }
        let layer = backdropClass.init()
        layer.setValue(true, forKey: "windowServerAware")   // see content of other apps' windows
        isLive = true
        return layer
    }

    /// Sets the gaussian blur on the backdrop layer. Without it (`CAFilter` or its factory missing:
    /// `perform` on a missing selector would crash) the backdrop would show the desktop unblurred, so
    /// the view hides and the pill draws its SwiftUI material instead.
    private func applyBlur() {
        guard isLive else { return }
        guard let blur = Self.gaussianBlur() else {
            isLive = false
            isHidden = true
            return
        }
        blur.setValue(StatusHUD.look.blur, forKey: "inputRadius")
        blur.setValue(true, forKey: "inputNormalizeEdges")
        layer?.filters = [blur]
    }

    /// `[CAFilter filterWithType:@"gaussianBlur"]`, or nil if the private class or method is missing.
    private static func gaussianBlur() -> NSObject? {
        let selector = NSSelectorFromString("filterWithType:")
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
              (filterClass as AnyObject).responds(to: selector) else { return nil }
        return filterClass.perform(selector, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject
    }
}

struct HUDPill: View {
    enum Background {
        /// The live blurred backdrop layer, behind the hosting view.
        case backdrop
        /// A SwiftUI material (no live backdrop: missing private classes, snapshots).
        case material
        /// Reduce Transparency: solid dark grey.
        case opaque
    }

    let symbol: String
    let content: HUDContent
    var background: Background = .material

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .frame(width: 32)
            switch content {
            case let .text(text):
                Text(text).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            case let .level(level):
                SegmentBar(level: level)
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 20).padding(.trailing, 26)
        .frame(width: StatusHUD.pillSize.width, height: StatusHUD.pillSize.height)
        .background {
            ZStack {
                switch background {
                case .backdrop:
                    EmptyView()
                case .material:
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.black.opacity(0.5))
                case .opaque:
                    Capsule().fill(Color(white: 0.16))
                }
                Capsule().fill(Color.white.opacity(StatusHUD.look.wash))
                ZStack {
                    Capsule().strokeBorder(Color.white.opacity(StatusHUD.look.glow), lineWidth: 1.5).blur(radius: 0.75)
                    Capsule().strokeBorder(Color.white.opacity(StatusHUD.look.rim), lineWidth: 0.5)
                }
                .mask(RimLight())
            }
            .clipShape(Capsule())
        }
        .environment(\.colorScheme, .dark)
    }
}

/// 16 segments like the system indicator.
struct SegmentBar: View {
    let level: Double
    private static let segments = 16

    var body: some View {
        let filled = Int((min(1, max(0, level)) * Double(Self.segments)).rounded())
        HStack(spacing: 1.5) {
            ForEach(0..<Self.segments, id: \.self) { i in
                Rectangle()
                    .fill(i < filled ? Color.white : Color.white.opacity(0.22))
                    .frame(height: 5)
            }
        }
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityValue("\(Int((level * 100).rounded()))%")
    }
}

/// Where the rim catches the light: full along the top and bottom edges, fading in just after the
/// straight edge begins, none anywhere on the rounded ends (like the system pill).
private struct RimLight: View {
    var body: some View {
        // Angles from the centre, clockwise from the right end; symmetric top and bottom.
        // The rounded ends span about ±13° from the centre of a 306 x 59 pill: no rim there at all.
        let stops: [(Double, Double)] = [(0, 0), (13, 0), (21, 1), (159, 1), (167, 0),
                                         (193, 0), (201, 1), (339, 1), (347, 0), (360, 0)]
        AngularGradient(stops: stops.map { .init(color: .white.opacity($0.1), location: $0.0 / 360) },
                        center: .center)
    }
}
