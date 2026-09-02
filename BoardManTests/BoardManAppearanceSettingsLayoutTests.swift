import AppKit
import Testing
@testable import Board_Man

@Suite
struct BoardManAppearanceSettingsLayoutTests {
    @Test
    func regularLayoutKeepsCardsAndControlsInsideTwoColumns() {
        let layout = BoardManAppearanceSettingsLayoutPolicy.layout(
            BoardManAppearanceSettingsLayoutInput(
                originX: 20,
                originY: 980,
                width: 560,
                controlHeight: 30,
                advancedExpanded: false
            )
        )

        #expect(!layout.stacksCards)
        #expect(layout.layoutCardFrame.maxX < layout.timestampCardFrame.minX)
        #expect(layout.usageCardFrame.maxX < layout.themeCardFrame.minX)
        #expect(layout.uiStyle.controlFrame.maxX <= layout.layoutCardFrame.maxX - 16)
        #expect(layout.inlineImagePosition.controlFrame.maxX <= layout.usageCardFrame.maxX - 16)
        #expect(layout.advanced == nil)
    }

    @Test
    func stackedAdvancedLayoutPreservesVerticalOrderAndBoundedRows() throws {
        let layout = BoardManAppearanceSettingsLayoutPolicy.layout(
            BoardManAppearanceSettingsLayoutInput(
                originX: 18,
                originY: 1_320,
                width: 430,
                controlHeight: 30,
                advancedExpanded: true
            )
        )
        let advanced = try #require(layout.advanced)

        #expect(layout.stacksCards)
        #expect(layout.timestampCardFrame.maxY < layout.layoutCardFrame.minY)
        #expect(layout.themeCardFrame.maxY < layout.usageCardFrame.minY)
        #expect(advanced.cardFrame.maxY < layout.advancedToggleFrame.minY)
        #expect(advanced.relativeNumber.controlFrame.maxX < advanced.relativeUnit.controlFrame.minX)
        #expect(advanced.customAccent.sliderFrame.maxX < advanced.customPanel.sliderFrame.minX)
        #expect(advanced.textPreviewScale.valueFrame.maxX <= advanced.cardFrame.maxX - 16)
        #expect(advanced.previewScaleProNoteFrame.minY >= advanced.cardFrame.minY)
    }
}
