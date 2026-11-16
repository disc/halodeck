// Draws Halodeck's app icon ("teal → blue ring on black") at every macOS icon size and writes an
// .iconset folder. Usage: swift scripts/make-icon.swift <out.iconset>   then   iconutil -c icns <out.iconset>
import AppKit

func drawIcon(size: CGFloat, in ctx: CGContext) {
    let s = size / 1024
    // macOS icon grid: 824 pt body centred on a 1024 canvas, corner radius ~185.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: space, colors: [
        NSColor(red: 0x1B / 255, green: 0x1D / 255, blue: 0x21 / 255, alpha: 1).cgColor,
        NSColor(red: 0x05 / 255, green: 0x05 / 255, blue: 0x06 / 255, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    let w = body.width
    let ring = CGRect(x: body.minX + 0.1695 * w, y: body.minY + (1 - 0.2225 - 0.555) * w,
                      width: 0.661 * w, height: 0.555 * w)
    let ringPath = CGPath(roundedRect: ring, cornerWidth: 0.1165 * w, cornerHeight: 0.1165 * w, transform: nil)
    let ringColors = [
        NSColor(red: 0x7F / 255, green: 0xF0 / 255, blue: 0xDC / 255, alpha: 1).cgColor,
        NSColor(red: 0x5E / 255, green: 0xC8 / 255, blue: 0xB5 / 255, alpha: 1).cgColor,
        NSColor(red: 0x3D / 255, green: 0x8B / 255, blue: 0xFF / 255, alpha: 1).cgColor,
    ] as CFArray
    let ringGradient = CGGradient(colorsSpace: space, colors: ringColors, locations: [0, 0.55, 1])!
    let tl = CGPoint(x: ring.minX, y: ring.maxY), br = CGPoint(x: ring.maxX, y: ring.minY)

    let middle = ring.insetBy(dx: 0.1375 * w, dy: 0.1375 * w)
    let glow = CGGradient(colorsSpace: space, colors: [
        NSColor(red: 0x5E / 255, green: 0xC8 / 255, blue: 0xB5 / 255, alpha: 0.22).cgColor,
        NSColor(red: 0x5E / 255, green: 0xC8 / 255, blue: 0xB5 / 255, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(ringPath)
    ctx.clip()
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: middle.midX, y: middle.midY), startRadius: 0,
                           endCenter: CGPoint(x: middle.midX, y: middle.midY), endRadius: middle.width * 0.6, options: [])
    ctx.restoreGState()

    func strokeRing(width: CGFloat) {
        ctx.saveGState()
        ctx.addPath(ringPath)
        ctx.setLineWidth(width)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(ringGradient, start: tl, end: br, options: [])
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.setAlpha(0.85)
    ctx.setShadow(offset: .zero, blur: 60 * s,
                  color: NSColor(red: 0x5E / 255, green: 0xC8 / 255, blue: 0xB5 / 255, alpha: 1).cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    strokeRing(width: 0.074 * w)
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    strokeRing(width: 0.0424 * w)
    ctx.restoreGState()
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawIcon(size: CGFloat(px), in: NSGraphicsContext.current!.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
print("wrote \(out.path)")
