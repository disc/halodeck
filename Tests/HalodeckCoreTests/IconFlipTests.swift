import Testing
import HalodeckCore

@Suite struct IconFlipTests {
    @Test func theIconIsHiddenBeforeItStarts() {
        #expect(IconFlip.pose(at: -0.1).opacity == 0)
        #expect(IconFlip.pose(at: 0).opacity == 0)
    }

    @Test func theIconEndsAtRest() {
        #expect(IconFlip.pose(at: IconFlip.duration) == .rest)
        #expect(IconFlip.pose(at: IconFlip.duration + 1) == .rest)
    }

    @Test func itTurnsAndGrowsOnTheWay() {
        let middle = IconFlip.pose(at: IconFlip.duration * 0.4)
        #expect(abs(middle.rotationY) > 30)
        #expect(middle.scale < 1)
    }

    // It swings a little past face-on before it settles.
    @Test func itOvershootsBeforeSettling() {
        let rotations = stride(from: 0.0, through: IconFlip.duration, by: 0.02).map { IconFlip.pose(at: $0).rotationY }
        #expect(rotations.contains { $0 > 5 })
    }

    private var samples: [IconPose] {
        stride(from: 0.0, through: IconFlip.duration + 0.1, by: 0.01).map { IconFlip.pose(at: $0) }
    }

    // No jumps anywhere, including where the turn hands over to the settle.
    @Test func itMovesSmoothly() {
        for (a, b) in zip(samples, samples.dropFirst()) {
            #expect(abs(b.rotationY - a.rotationY) < 40)
            #expect(abs(b.scale - a.scale) < 0.05)
        }
    }

    @Test func itNeverFadesOutOrOutgrowsItsSize() {
        for (a, b) in zip(samples, samples.dropFirst()) { #expect(b.opacity >= a.opacity) }
        for pose in samples.dropFirst() { #expect((0.4...1).contains(pose.scale)) }
    }

    @Test func reduceMotionOnlyFadesTheIconIn() {
        let pose = IconFlip.pose(at: IconFlip.duration * 0.1, reduceMotion: true)
        #expect(pose.rotationY == 0 && pose.scale == 1)
        #expect(pose.opacity > 0 && pose.opacity < 1)
        #expect(IconFlip.pose(at: 0.25, reduceMotion: true) == .rest)
    }
}
