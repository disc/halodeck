import CoreGraphics

/// Where a MacBook's notch is, from the two menu-bar areas macOS reports beside it
/// (`NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`), and where an indicator that grows out
/// of it goes. Screen coordinates, origin bottom-left, like AppKit's.
public struct NotchGeometry: Equatable, Sendable {
    /// The little outward curve at each top corner, so the shape flows out of the screen edge.
    public static let shoulder: CGFloat = 6

    public let notch: CGRect
    public let screenFrame: CGRect

    /// Nil when the screen has no notch: an area is missing, or the two areas touch.
    public init?(screenFrame: CGRect, leftArea: CGRect?, rightArea: CGRect?) {
        guard let leftArea, let rightArea, rightArea.minX - leftArea.maxX > 1 else { return nil }
        notch = CGRect(x: leftArea.maxX, y: leftArea.minY, width: rightArea.minX - leftArea.maxX,
                       height: leftArea.height)
        self.screenFrame = screenFrame
    }

    /// The grown notch's window with `margin` of room on the left, right and below for a glow,
    /// flush with the top (the launch greeting).
    public func windowFrame(earWidth: CGFloat, margin: CGFloat) -> CGRect {
        let plain = windowFrame(earWidth: earWidth)
        return CGRect(x: plain.minX - margin, y: plain.minY - margin,
                      width: plain.width + 2 * margin, height: plain.height + margin)
    }

    public static let muteSignWidth: CGFloat = 30

    /// The muted signs' window: the whole notch (with both shoulders) plus an ear holding `leftSigns`
    /// signs side by side on its left and one holding `rightSigns` on its right (either may be 0), as
    /// tall as the notch, flush with the top. All signs share it, so they read as one shape.
    public func earFrame(leftSigns: Int, rightSigns: Int) -> CGRect {
        let left = CGFloat(leftSigns) * Self.muteSignWidth, right = CGFloat(rightSigns) * Self.muteSignWidth
        return CGRect(x: notch.minX - left - Self.shoulder, y: notch.minY,
                      width: Self.shoulder + left + notch.width + right + Self.shoulder, height: notch.height)
    }

    /// The indicator's window: the notch with an ear of `earWidth` on each side (plus the shoulders),
    /// as tall as the notch, flush with the top of the screen.
    public func windowFrame(earWidth: CGFloat) -> CGRect {
        let width = notch.width + 2 * earWidth + 2 * Self.shoulder
        return CGRect(x: notch.midX - width / 2, y: screenFrame.maxY - notch.height,
                      width: width, height: notch.height)
    }
}
