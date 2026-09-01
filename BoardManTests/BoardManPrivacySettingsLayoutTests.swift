import AppKit
import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class BoardManPrivacySettingsLayoutTests {
    @Test
    func storedTypesUseTwoBoundedColumns() {
        let layout = BoardManPrivacySettingsLayoutPolicy.layout(
            BoardManPrivacySettingsLayoutInput(
                originX: 24,
                originY: 680,
                width: 520,
                storedTypeCount: 6
            )
        )

        #expect(layout.storedTypeFrames.count == 6)
        #expect(layout.storedTypeFrames[0].minY == layout.storedTypeFrames[1].minY)
        #expect(layout.storedTypeFrames[2].minY < layout.storedTypeFrames[0].minY)
        #expect(layout.storedTypeFrames.allSatisfy { $0.minX >= 24 && $0.maxX <= 544 })
    }

    @Test
    func filterControlsStayOrderedAndInsideColumn() {
        let layout = BoardManPrivacySettingsLayoutPolicy.layout(
            BoardManPrivacySettingsLayoutInput(
                originX: 18,
                originY: 620,
                width: 420,
                storedTypeCount: 4
            )
        )

        #expect(layout.hideRuleModeFrame.minX == 18)
        #expect(layout.hideRuleTextFrame.minX > layout.hideRuleModeFrame.minX)
        #expect(layout.addHideRuleFrame.minX > layout.hideRuleTextFrame.minX)
        #expect(layout.addHideRuleFrame.maxX <= 438)
        #expect(layout.removeLastHideRuleFrame.minY == layout.clearHideRulesFrame.minY)
        #expect(layout.hideRulesNoteFrame.minY < layout.hideRulesExamplesFrame.minY)
    }

    @Test
    func privacySectionsReserveSpaceForSelectionClipboardControls() {
        let layout = BoardManPrivacySettingsLayoutPolicy.layout(
            BoardManPrivacySettingsLayoutInput(
                originX: 30,
                originY: 700,
                width: 500,
                storedTypeCount: 0
            )
        )

        #expect(layout.privacyHeaderFrame.minY == 700)
        #expect(layout.selectionMemoryFrame.minY < layout.privacyHeaderFrame.minY)
        #expect(layout.selectionMemoryClearFrame.maxX <= 530)
        #expect(layout.hideMaskedPreviewFrame.minY < layout.selectionMemoryStatusFrame.minY)
        #expect(layout.storedTypesHeaderFrame.minY == 450)
        #expect(layout.filterHeaderFrame.minY == 276)
        #expect(layout.excludedAppsButtonFrame.width <= 178)
        #expect(layout.storedTypeFrames.isEmpty)
    }
}
