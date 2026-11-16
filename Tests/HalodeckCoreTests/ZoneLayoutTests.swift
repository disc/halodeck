import Testing
@testable import HalodeckCore

@Suite struct ZoneLayoutTests {
    let layout = ZoneLayout(sideWidthFraction: 0.10)

    @Test func sides() {
        #expect(layout.side(normalizedX: 0.95) == .right)
        #expect(layout.side(normalizedX: 0.05) == .left)
        #expect(layout.side(normalizedX: 0.5) == nil)
    }

    @Test func corners() {
        #expect(layout.corner(normalizedX: 0.05, yMM: 80, padHeightMM: Pad.height) == .topLeft)
        #expect(layout.corner(normalizedX: 0.05, yMM: 60, padHeightMM: Pad.height) == nil)
        #expect(layout.corner(normalizedX: 0.95, yMM: 80, padHeightMM: Pad.height) == .topRight)
        #expect(layout.corner(normalizedX: 0.5, yMM: 80, padHeightMM: Pad.height) == nil)
    }

    @Test func bottomCorners() {
        #expect(layout.corner(normalizedX: 0.05, yMM: 5, padHeightMM: Pad.height) == .bottomLeft)
        #expect(layout.corner(normalizedX: 0.95, yMM: 5, padHeightMM: Pad.height) == .bottomRight)
        #expect(layout.corner(normalizedX: 0.5, yMM: 5, padHeightMM: Pad.height) == nil)
    }

    @Test func middleOfBottomStripIsBottom() {
        #expect(layout.sides(normalizedX: 0.5, yMM: 5, padHeightMM: Pad.height) == [.bottom])
    }

    @Test func topStripBetweenCornersIsTop() {
        #expect(layout.sides(normalizedX: 0.5, yMM: 80, padHeightMM: Pad.height) == [.top])
    }

    @Test func middleIsNoSide() {
        #expect(layout.sides(normalizedX: 0.5, yMM: 40, padHeightMM: Pad.height).isEmpty)
    }

    @Test func bottomCornerIsInTheBottomSideAllTheWayUp() {
        #expect(layout.corner(normalizedX: 0.95, yMM: 11, padHeightMM: Pad.height) == .bottomRight)
        #expect(layout.sides(normalizedX: 0.95, yMM: 11, padHeightMM: Pad.height) == [.right, .bottom])
    }

    @Test(arguments: [0.05, 0.5, 0.95], [1.0, 9.0, 11.0, 11.9, 12.5, 30.0])
    func topAndBottomStripsMirrorEachOther(x: Double, fromBorderMM: Double) {
        let bottom = layout.sides(normalizedX: x, yMM: fromBorderMM, padHeightMM: Pad.height)
        let top = layout.sides(normalizedX: x, yMM: Pad.height - fromBorderMM, padHeightMM: Pad.height)
        #expect(Set(bottom.map { $0 == .bottom ? Side.top : $0 }) == top)
    }
}
