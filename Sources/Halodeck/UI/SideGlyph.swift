import HalodeckCore
import SwiftUI

/// A tiny trackpad outline with the relevant sides (and/or corners) drawn bold, so a row says where
/// on the trackpad it acts instead of relying on colour.
struct SideGlyph: View {
    var sides: Set<Side> = []
    var corners: Set<Corner> = []
    var showsEmptyCorners = false
    var highlight: Color = .primary

    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            ctx.stroke(Path(roundedRect: r, cornerRadius: 3.5), with: .color(.secondary.opacity(0.7)), lineWidth: 1.2)
            let t: CGFloat = 2.6, m: CGFloat = 4
            for side in sides {
                let bar: CGRect = switch side {
                case .left: CGRect(x: r.minX - 0.4, y: r.minY + m, width: t, height: r.height - 2 * m)
                case .right: CGRect(x: r.maxX - t + 0.4, y: r.minY + m, width: t, height: r.height - 2 * m)
                case .top: CGRect(x: r.minX + m, y: r.minY - 0.4, width: r.width - 2 * m, height: t)
                case .bottom: CGRect(x: r.minX + m, y: r.maxY - t + 0.4, width: r.width - 2 * m, height: t)
                }
                ctx.fill(Path(roundedRect: bar, cornerRadius: t / 2), with: .color(highlight))
            }
            for corner in Corner.allCases where corners.contains(corner) || showsEmptyCorners {
                let c = CGPoint(x: corner.isLeft ? r.minX + 3 : r.maxX - 3, y: corner.isTop ? r.minY + 3 : r.maxY - 3)
                let dot = CGRect(x: c.x - 2.6, y: c.y - 2.6, width: 5.2, height: 5.2)
                if corners.contains(corner) {
                    ctx.fill(Path(ellipseIn: dot), with: .color(highlight))
                } else {
                    ctx.stroke(Path(ellipseIn: dot.insetBy(dx: 0.5, dy: 0.5)), with: .color(.secondary), lineWidth: 1)
                }
            }
        }
        .frame(width: 24, height: 16)
        .accessibilityHidden(true)
    }
}
