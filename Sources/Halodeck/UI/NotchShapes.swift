import HalodeckCore
import SwiftUI

/// The notch outline: flush with the top edge, a small outward curve at each top corner (so it flows
/// out of the screen's edge like the notch does), rounded bottom corners.
struct NotchShape: Shape {
    static func cornerRadius(height: CGFloat) -> CGFloat { min(12, height * 0.38) }

    func path(in rect: CGRect) -> Path {
        let s = NotchGeometry.shoulder
        let r = Self.cornerRadius(height: rect.height)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + s, y: rect.minY + s), control: CGPoint(x: rect.minX + s, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + s + r, y: rect.maxY), control: CGPoint(x: rect.minX + s, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - s - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - s, y: rect.maxY - r), control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - s, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The open path the notch's lights run along: the visible edge of a notch body spanning
/// `left`...`right` and reaching down to `bottom`, with corners of `radius` (all already moved out
/// by the light's offset).
private enum NotchEdgePath {
    enum Part {
        case sidesAndBottom
        /// From the middle of the left rounded corner to the middle of the right one.
        case bottom
        /// One bottom corner (the right one or the left) with `lead` of straight edge on each side of it.
        case corner(right: Bool, lead: CGFloat)
    }

    static func make(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat, radius r: CGFloat,
                     part: Part) -> Path {
        var p = Path()
        switch part {
        case .sidesAndBottom:
            p.move(to: CGPoint(x: left, y: top))
            p.addLine(to: CGPoint(x: left, y: bottom - r))
            p.addQuadCurve(to: CGPoint(x: left + r, y: bottom), control: CGPoint(x: left, y: bottom))
            p.addLine(to: CGPoint(x: right - r, y: bottom))
            p.addQuadCurve(to: CGPoint(x: right, y: bottom - r), control: CGPoint(x: right, y: bottom))
            p.addLine(to: CGPoint(x: right, y: top))
        case .bottom:
            p.move(to: CGPoint(x: left + r / 4, y: bottom - r / 4))
            p.addQuadCurve(to: CGPoint(x: left + r, y: bottom), control: CGPoint(x: left + r / 2, y: bottom))
            p.addLine(to: CGPoint(x: right - r, y: bottom))
            p.addQuadCurve(to: CGPoint(x: right - r / 4, y: bottom - r / 4), control: CGPoint(x: right - r / 2, y: bottom))
        case let .corner(isRight, lead):
            let x = isRight ? right : left, inward: CGFloat = isRight ? -1 : 1
            p.move(to: CGPoint(x: x + inward * (r + lead), y: bottom))
            p.addLine(to: CGPoint(x: x + inward * r, y: bottom))
            p.addQuadCurve(to: CGPoint(x: x, y: bottom - r), control: CGPoint(x: x, y: bottom))
            p.addLine(to: CGPoint(x: x, y: max(top, bottom - r - lead)))
        }
        return p
    }
}

/// `NotchShape`'s visible edge as an open path just outside it (or only its bottom, the level gauge's
/// track). Uses the same frame as `NotchShape` (it draws slightly outside it).
struct NotchEdge: Shape {
    /// How far outside the shape's edge the line runs; 0 = on the edge.
    var offset: CGFloat = 1.5
    var bottomOnly = false

    func path(in rect: CGRect) -> Path {
        let s = NotchGeometry.shoulder
        return NotchEdgePath.make(left: rect.minX + s - offset, right: rect.maxX - s + offset, top: rect.minY,
                                  bottom: rect.maxY + offset,
                                  radius: NotchShape.cornerRadius(height: rect.height) + offset,
                                  part: bottomOnly ? .bottom : .sidesAndBottom)
    }
}

/// One bottom corner of `NotchShape`'s edge (see `NotchEdgePath.Part.corner`), just outside it, in
/// the same frame as `NotchShape`.
struct NotchCornerEdge: Shape {
    let right: Bool
    var lead: CGFloat
    var offset: CGFloat = 1.5

    func path(in rect: CGRect) -> Path {
        let s = NotchGeometry.shoulder
        return NotchEdgePath.make(left: rect.minX + s - offset, right: rect.maxX - s + offset, top: rect.minY,
                                  bottom: rect.maxY + offset,
                                  radius: NotchShape.cornerRadius(height: rect.height) + offset,
                                  part: .corner(right: right, lead: lead))
    }
}

/// The launch greeting's light path: the edge of a notch body `notch` in size, `margin` in from the
/// left of the frame, flush with its top.
struct NotchOutline: Shape {
    /// The greeting's light takes its corners a little tighter than `NotchShape`'s.
    static func cornerRadius(height: CGFloat) -> CGFloat { min(10, height * 0.3) }

    let notch: CGSize
    let margin: CGFloat
    /// How far outside the notch the light runs (the notch itself shows nothing).
    var offset: CGFloat = 1.5

    func path(in rect: CGRect) -> Path {
        NotchEdgePath.make(left: margin - offset, right: margin + notch.width + offset, top: 0,
                           bottom: notch.height + offset, radius: Self.cornerRadius(height: notch.height) + offset,
                           part: .sidesAndBottom)
    }
}

/// The teal-to-blue light along part of the notch's edge (`from`...`to` of the way round), with a
/// soft glow; drawn in the same frame as `NotchShape`.
struct NotchGlowStroke: View {
    let from: Double
    let to: Double
    var offset: CGFloat = 1.5
    var lineWidth: CGFloat = 2.5
    var bottomOnly = false

    var body: some View {
        NotchEdge(offset: offset, bottomOnly: bottomOnly)
            .trim(from: from, to: to)
            .stroke(LinearGradient(colors: [Theme.notchLightTeal, Theme.notchLightBlue], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .shadow(color: Theme.notchLightTeal.opacity(0.9), radius: 3)
            .shadow(color: Theme.notchLightBlue.opacity(0.7), radius: 8)
    }
}

/// The end-of-range bump's light, in the same frame as `NotchShape` and drawn behind it (like
/// `NotchGlowStroke`), so only the outside glows.
struct NotchBumpLight: View {
    let right: Bool
    var offset: CGFloat = 1.5
    var lineWidth: CGFloat = 2.5
    /// The bloom's radius: centred on the corner, it fades out within the window's glow margin below
    /// the notch.
    static let bloomRadius = NotchHUD.glowMargin

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size, teal = Theme.notchLightTeal
            let r = NotchShape.cornerRadius(height: size.height) + offset
            let lead = r
            let x = right ? size.width - NotchGeometry.shoulder + offset : NotchGeometry.shoulder - offset
            let corner = CGPoint(x: x, y: size.height + offset)
            let fade = RadialGradient(stops: [.init(color: teal, location: 0), .init(color: teal, location: 0.5),
                                              .init(color: teal.opacity(0), location: 1)],
                                      center: UnitPoint(x: corner.x / max(1, size.width), y: corner.y / max(1, size.height)),
                                      startRadius: 0, endRadius: r + lead)
            ZStack {
                Circle()
                    .fill(RadialGradient(stops: [.init(color: teal.opacity(0.65), location: 0),
                                                 .init(color: teal.opacity(0.25), location: 0.45),
                                                 .init(color: teal.opacity(0), location: 1)],
                                         center: .center, startRadius: 0, endRadius: Self.bloomRadius))
                    .frame(width: 2 * Self.bloomRadius, height: 2 * Self.bloomRadius)
                    .position(x: corner.x, y: size.height)
                NotchCornerEdge(right: right, lead: lead, offset: offset)
                    .stroke(fade, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .shadow(color: teal.opacity(0.9), radius: 3)
                    .shadow(color: teal.opacity(0.6), radius: 8)
            }
        }
    }
}
