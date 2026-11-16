import HalodeckCore
import SwiftUI

enum ZoneSelection: Hashable { case side(Side), corner(Corner) }

struct TrackpadMapView: View {
    enum Size { case compact, large }

    var settings: HalodeckSettings
    var brightnessAvailable: Bool
    var size: Size
    var selection: Binding<ZoneSelection?>? = nil

    @Environment(\.colorScheme) private var scheme
    /// The view's size, for mapping taps onto the pad (Settings only).
    @State private var viewSize: CGSize = .zero

    private let aspect = 142.7 / 85.1
    private let cornerHeightFraction = 12.0 / 85.1
    private let bottomStripFraction = 10.0 / 85.1

    var body: some View {
        Canvas { ctx, canvasSize in
            let large = size == .large
            let pad = padRect(in: canvasSize)
            let radius = pad.width * 0.055
            let padPath = Path(roundedRect: pad, cornerRadius: radius, style: .continuous)
            let dark = scheme == .dark

            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(dark ? 0.5 : 0.18), radius: large ? 6 : 3, y: large ? 2 : 1))
                layer.fill(padPath, with: .linearGradient(
                    Gradient(colors: dark
                        ? [Color(white: 0.27), Color(white: 0.20)]
                        : [Color(white: 0.94), Color(white: 0.86)]),
                    startPoint: CGPoint(x: pad.midX, y: pad.minY), endPoint: CGPoint(x: pad.midX, y: pad.maxY)))
            }

            ctx.drawLayer { clipped in
                clipped.clip(to: padPath)
                for side in Side.allCases { drawZone(side, in: &clipped, pad: pad, large: large) }
            }

            ctx.stroke(padPath, with: .color(dark ? Color.white.opacity(0.10) : Color.black.opacity(0.14)), lineWidth: 1)
            ctx.stroke(Path(roundedRect: pad.insetBy(dx: 1, dy: 1), cornerRadius: radius - 1, style: .continuous),
                       with: .linearGradient(Gradient(colors: [Color.white.opacity(dark ? 0.12 : 0.8), .clear]),
                                             startPoint: CGPoint(x: pad.midX, y: pad.minY),
                                             endPoint: CGPoint(x: pad.midX, y: pad.minY + pad.height * 0.25)),
                       lineWidth: 1)

            for corner in Corner.allCases { drawCorner(corner, in: &ctx, pad: pad, large: large) }
        } symbols: {
            ForEach(Corner.allCases, id: \.self) { corner in
                let action = shownAction(corner)
                Image(systemName: Theme.symbol(for: action))
                    .font(.system(size: size == .large ? 14 : 9, weight: .bold))
                    .foregroundStyle(action.isReady ? Color.white : Color.secondary)
                    .shadow(color: .black.opacity(action.isReady ? 0.25 : 0), radius: 0.8, y: 0.6)
                    .tag(corner)
            }
            ForEach(Corner.allCases.map { "badge-\($0.rawValue)" }, id: \.self) { badgeID in
                let corner = Corner.allCases.first { "badge-\($0.rawValue)" == badgeID } ?? .topLeft
                Text("\(settings.maxClicks(corner))×")
                    .font(.system(size: size == .large ? 9 : 7, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.trackpad)
                    .padding(.horizontal, size == .large ? 4 : 3).padding(.vertical, 1)
                    .background(Capsule().fill(Color.white))
                    .overlay(Capsule().strokeBorder(Theme.trackpad.opacity(0.5), lineWidth: 0.5))
                    .tag(badgeID)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in selection?.wrappedValue = zone(at: tap.location) },
                 including: selection == nil ? .none : .all)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// The trackpad's surface within a view of `size`: drawing and tapping both use it.
    private func padRect(in size: CGSize) -> CGRect {
        let inset: CGFloat = self.size == .large ? 8 : 5
        return CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    }

    /// The rectangle a side occupies on the pad (matches `zone(x:yTop:)`).
    private func laneRect(_ side: Side, pad: CGRect) -> CGRect {
        let strip = pad.width * settings.sideWidthFraction
        let top = pad.height * cornerHeightFraction, bottom = pad.height * bottomStripFraction
        switch side {
        case .left: return CGRect(x: pad.minX, y: pad.minY + top, width: strip, height: pad.height - top - bottom)
        case .right: return CGRect(x: pad.maxX - strip, y: pad.minY + top, width: strip, height: pad.height - top - bottom)
        case .top: return CGRect(x: pad.minX + strip, y: pad.minY, width: pad.width - 2 * strip, height: top)
        case .bottom: return CGRect(x: pad.minX + strip, y: pad.maxY - bottom, width: pad.width - 2 * strip, height: bottom)
        }
    }

    private enum LaneState { case active, off, unset }

    private func laneState(_ side: Side) -> LaneState {
        let function = settings.sides[side] ?? .nothing
        if function == .nothing { return .unset }
        return isOn(side: side, function: function) ? .active : .off
    }

    private func zoneRect(_ side: Side, pad: CGRect, large: Bool) -> CGRect {
        let rect = laneRect(side, pad: pad)
        let gap: CGFloat = large ? 5 : 3.5
        return switch side {
        case .left, .right: CGRect(x: rect.minX, y: rect.minY + gap, width: rect.width, height: rect.height - 2 * gap)
        case .top, .bottom: CGRect(x: rect.minX + gap, y: rect.minY, width: rect.width - 2 * gap, height: rect.height)
        }
    }

    private func rimToMiddle(_ side: Side, _ zone: CGRect) -> (CGPoint, CGPoint) {
        switch side {
        case .left: (CGPoint(x: zone.minX, y: zone.midY), CGPoint(x: zone.maxX, y: zone.midY))
        case .right: (CGPoint(x: zone.maxX, y: zone.midY), CGPoint(x: zone.minX, y: zone.midY))
        case .top: (CGPoint(x: zone.midX, y: zone.minY), CGPoint(x: zone.midX, y: zone.maxY))
        case .bottom: (CGPoint(x: zone.midX, y: zone.maxY), CGPoint(x: zone.midX, y: zone.minY))
        }
    }

    private func drawZone(_ side: Side, in ctx: inout GraphicsContext, pad: CGRect, large: Bool) {
        let state = laneState(side)
        let zone = zoneRect(side, pad: pad, large: large)
        let selected = selection?.wrappedValue == .side(side)
        if state == .unset {
            ctx.stroke(Path(roundedRect: zone.insetBy(dx: 2, dy: 2), cornerRadius: 6), with: .color(.primary.opacity(0.13)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            return
        }
        let color = state == .active ? Theme.trackpad : Color.gray
        let (outer, inner) = rimToMiddle(side, zone)
        // Fade the two ends of the zone so it melts into the corners instead of ending in a box.
        let along: (CGPoint, CGPoint) = side.isVertical
            ? (CGPoint(x: zone.midX, y: zone.minY), CGPoint(x: zone.midX, y: zone.maxY))
            : (CGPoint(x: zone.minX, y: zone.midY), CGPoint(x: zone.maxX, y: zone.midY))
        let endFade = Gradient(stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black, location: 0.12),
                                       .init(color: .black, location: 0.88), .init(color: .black.opacity(0), location: 1)])

        let a = state == .active ? (selected ? 1.0 : 0.85) : 0.14   // off: barely there, so it never reads as live
        ctx.drawLayer { layer in
            layer.clip(to: Path(roundedRect: zone, cornerRadius: 3))
            var lines = Path()
            let step: CGFloat = large ? 5 : 4
            var x = zone.minX - zone.height
            while x < zone.maxX + zone.height {
                lines.move(to: CGPoint(x: x, y: zone.maxY)); lines.addLine(to: CGPoint(x: x + zone.height, y: zone.minY))
                x += step
            }
            layer.drawLayer { hatch in
                hatch.stroke(lines, with: .linearGradient(
                    Gradient(colors: [color.opacity(a), color.opacity(a * 0.5)]), startPoint: outer, endPoint: inner),
                             lineWidth: state == .active ? 1 : 0.8)
                hatch.blendMode = .destinationIn
                hatch.fill(Path(zone), with: .linearGradient(endFade, startPoint: along.0, endPoint: along.1))
            }
        }
    }

    private func drawCorner(_ corner: Corner, in ctx: inout GraphicsContext, pad: CGRect, large: Bool) {
        let strip = pad.width * settings.sideWidthFraction
        let height = pad.height * (corner.isTop ? cornerHeightFraction : bottomStripFraction)
        let d: CGFloat = large ? 30 : 19
        let margin = d / 2 + (large ? 7 : 4)
        let cx = corner.isLeft ? pad.minX + max(strip / 2, margin) : pad.maxX - max(strip / 2, margin)
        let cy = corner.isTop ? pad.minY + max(height / 2, margin) : pad.maxY - max(height / 2, margin)
        let rect = CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)
        let action = shownAction(corner)
        let on = settings.enabled
        let selected = selection?.wrappedValue == .corner(corner)

        if !action.isReady {   // Nothing, or an action still waiting for its app or keys
            ctx.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(0.05)))
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)), with: .color(.primary.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 1.3, dash: [3, 3]))
        } else {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(on ? 0.22 : 0.08), radius: large ? 2.5 : 1.5, y: 1))
                layer.fill(Path(ellipseIn: rect), with: .color(Theme.trackpad))
            }
            if !on { ctx.fill(Path(ellipseIn: rect), with: .color(Color(nsColor: .controlBackgroundColor).opacity(0.6))) }
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1.1, dy: 1.1)), with: .color(.white.opacity(0.85)),
                       lineWidth: large ? 2 : 1.4)
        }
        if selected {
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(.accentColor), lineWidth: 2)
        }
        if let symbol = ctx.resolveSymbol(id: corner) { ctx.draw(symbol, at: CGPoint(x: cx, y: cy)) }
        if settings.maxClicks(corner) > 1, let badge = ctx.resolveSymbol(id: "badge-\(corner.rawValue)") {
            ctx.draw(badge, at: CGPoint(x: corner.isLeft ? rect.maxX + 2 : rect.minX - 2, y: rect.minY + 2))
        }
    }

    /// The action whose icon a corner shows: its first ready action (1 click first), or else one
    /// still waiting for its app or keys, which draws dimmed in a dashed ring.
    private func shownAction(_ corner: Corner) -> CornerAction {
        let actions = (1...HalodeckSettings.maxCornerClicks).map { settings.cornerAction(corner, clicks: $0) }
        return actions.first { $0.isReady } ?? actions.first { $0 != .nothing } ?? .nothing
    }

    /// Which zone a point (x 0…1 from the left, yTop 0…1 from the top) is in, as drawn on the map.
    private func zone(x: Double, yTop: Double) -> ZoneSelection? {
        let strip = settings.sideWidthFraction
        let side: Side? = x <= strip ? .left : x >= 1 - strip ? .right : nil
        if yTop >= 1 - bottomStripFraction {
            if let side { return .corner(side == .left ? .bottomLeft : .bottomRight) }
            return .side(.bottom)
        }
        if let side {
            if yTop <= cornerHeightFraction { return .corner(side == .left ? .topLeft : .topRight) }
            return .side(side)
        }
        if yTop <= cornerHeightFraction { return .side(.top) }
        return nil
    }

    private func zone(at point: CGPoint) -> ZoneSelection? {
        let pad = padRect(in: viewSize)
        guard pad.width > 0, pad.height > 0 else { return nil }
        let x = Double((point.x - pad.minX) / pad.width), yTop = Double((point.y - pad.minY) / pad.height)
        guard (0...1).contains(x), (0...1).contains(yTop) else { return nil }
        return zone(x: x, yTop: yTop)
    }

    private func isOn(side: Side, function: SideAction) -> Bool {
        guard settings.enabled, settings.activeSides[side] != nil else { return false }   // Custom keys without a shortcut is unset
        return function != .brightness || brightnessAvailable
    }

    private var accessibilitySummary: String {
        let parts = Side.allCases.map { "\($0.rawValue.capitalized) side: \((settings.sides[$0] ?? .nothing).title)" }
        return "Trackpad map. " + parts.joined(separator: ". ") + "."
    }
}
