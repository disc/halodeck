import AppKit
import Testing
@testable import Halodeck

@MainActor
@Suite struct MenuBarIconTests {
    /// The image's alpha at `point` (in its 20 × 16 pt space, origin bottom-left), drawn at 4×.
    private func alpha(_ image: NSImage, at point: NSPoint) -> CGFloat {
        let scale: CGFloat = 4
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale),
                                   pixelsHigh: Int(image.size.height * scale), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let x = Int(point.x * scale), y = rep.pixelsHigh - 1 - Int(point.y * scale)
        return rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    private let dotCentre = NSPoint(x: 17, y: 13)
    /// On the ring's top edge, inside the gap that separates the dot from the ring.
    private let ringInsideTheGap = NSPoint(x: 13.3, y: 14.9)

    @Test func theDotIsSolid() {
        #expect(alpha(MenuBarIcon.image(on: true, dot: true), at: dotCentre) > 0.9)
    }

    @Test func aGapSeparatesTheDotFromTheRing() {
        #expect(alpha(MenuBarIcon.image(on: true), at: ringInsideTheGap) > 0.9)
        #expect(alpha(MenuBarIcon.image(on: true, dot: true), at: ringInsideTheGap) < 0.1)
    }

    @Test func theDotStaysSolidWhenHalodeckIsOff() {
        #expect(alpha(MenuBarIcon.image(on: false, dot: true), at: dotCentre) > 0.9)
    }

    @Test func voiceOverHearsAboutTheUpdate() {
        #expect(MenuBarIcon.image(on: true, dot: true).accessibilityDescription == "Halodeck on, update available")
        #expect(MenuBarIcon.image(on: true).accessibilityDescription == "Halodeck on")
    }
}
