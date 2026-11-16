import Foundation
import Testing
@testable import HalodeckCore

@Suite struct SystemActionsTests {
    @Test(arguments: [CornerAction.muteMicrophone, .lockScreen, .missionControl, .appExpose, .showDesktop, .showApps])
    func cornerActionsSurviveSaveAndLoad(_ action: CornerAction) throws {
        var s = HalodeckSettings()
        s.corners[.bottomLeft] = action
        s.setCornerAction(action, for: .topLeft, clicks: 2)
        let back = try JSONDecoder().decode(HalodeckSettings.self, from: JSONEncoder().encode(s))
        #expect(back.corners[.bottomLeft] == action)
        #expect(back.cornerAction(.topLeft, clicks: 2) == action)
    }
}
