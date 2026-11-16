import AppKit

/// Menu-bar glyph: a ring of light around a quiet middle (matches the app icon).
@MainActor
enum MenuBarIcon {
    /// `dot`: a new version is waiting (a small dot cut into the ring's top-right corner).
    static func image(on: Bool, dot: Bool = false) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let halo = NSRect(x: 12.4, y: 8.4, width: 9.2, height: 9.2)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            if dot {   // leave a gap round the dot: draw everything else outside it
                let outside = NSBezierPath(rect: rect)
                outside.appendOval(in: halo)
                outside.windingRule = .evenOdd
                outside.addClip()
            }
            let alpha: CGFloat = on ? 1 : 0.4
            let ring = NSBezierPath(roundedRect: NSRect(x: 1.6, y: 1.1, width: 16.8, height: 13.8), xRadius: 4, yRadius: 4)
            ring.lineWidth = 2.2
            NSColor.black.withAlphaComponent(alpha).setStroke()
            ring.stroke()

            NSColor.black.withAlphaComponent(alpha * 0.35).setFill()
            NSBezierPath(roundedRect: NSRect(x: 5.6, y: 4.9, width: 8.8, height: 6.2), xRadius: 1.6, yRadius: 1.6).fill()

            if !on {
                NSColor.black.setStroke()
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 2, y: 0.8))
                slash.line(to: NSPoint(x: 18, y: 15.2))
                slash.lineWidth = 1.6
                slash.lineCapStyle = .round
                slash.stroke()
            }

            NSGraphicsContext.restoreGraphicsState()

            if dot {   // solid even while the ring is faded (off)
                NSColor.black.setFill()
                NSBezierPath(ovalIn: halo.insetBy(dx: 1.8, dy: 1.8)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = (on ? "Halodeck on" : "Halodeck off") + (dot ? ", update available" : "")
        return image
    }
}
