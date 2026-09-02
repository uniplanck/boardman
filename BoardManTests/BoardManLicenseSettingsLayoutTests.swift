import AppKit
import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class BoardManLicenseSettingsLayoutTests {
    @Test
    func regularLayoutKeepsActivationAndPlanControlsBounded() {
        let layout = BoardManLicenseSettingsLayoutPolicy.layout(
            BoardManLicenseSettingsLayoutInput(originX: 24, originY: 680, width: 520)
        )

        #expect(layout.keyFieldFrame.minX == 24)
        #expect(layout.activateFrame.minX > layout.keyFieldFrame.minX)
        #expect(layout.activateFrame.maxX == 544)
        #expect(layout.upgradeFrame.width == 126)
        #expect(layout.proLockedFrame.maxX == 544)
        #expect(layout.stateExamplesFrame.minY < layout.mockNoteFrame.minY)
    }

    @Test
    func compactLayoutPreservesMinimumKeyWidthAndVerticalOrder() {
        let layout = BoardManLicenseSettingsLayoutPolicy.layout(
            BoardManLicenseSettingsLayoutInput(originX: 18, originY: 620, width: 210)
        )

        #expect(layout.keyFieldFrame.width == 120)
        #expect(layout.activateFrame.width == 106)
        #expect(layout.sectionHeaderFrame.minY > layout.planFrame.minY)
        #expect(layout.planFrame.minY > layout.stateFrame.minY)
        #expect(layout.stateFrame.minY > layout.limitsFrame.minY)
        #expect(layout.activationStatusFrame.minY > layout.upgradeFrame.minY)
        #expect(layout.upgradeFrame.minY > layout.proLockedFrame.minY)
    }
}
