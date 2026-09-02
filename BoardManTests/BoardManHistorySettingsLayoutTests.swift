import AppKit
import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class BoardManHistorySettingsLayoutTests {
    @Test
    func regularLayoutKeepsShortcutAndPinControlsInsideColumn() {
        let layout = BoardManHistorySettingsLayoutPolicy.layout(
            BoardManHistorySettingsLayoutInput(originX: 24, originY: 680, width: 560)
        )

        #expect(!layout.usesStackedShortcutLayout)
        #expect(layout.timestampShortcutRecordFrame.minX > layout.timestampShortcutLabelFrame.minX)
        #expect(layout.timestampShortcutRecordFrame.maxX <= 584)
        #expect(layout.timestampShortcutDelayDecreaseFrame.minY == layout.timestampShortcutDelayFieldFrame.minY)
        #expect(layout.timestampShortcutDelayIncreaseFrame.maxX < layout.timestampShortcutSecondsFrame.maxX)
        #expect(layout.timedPinPresetRemoveFrame.maxX <= 584)
        #expect(layout.timedPinDurationUnitFrame.maxX <= 584)
        #expect(layout.clearHistoryFrame.minX > layout.exportHistoryFrame.minX)
    }

    @Test
    func compactLayoutStacksShortcutBeforeTimedPinControls() {
        let layout = BoardManHistorySettingsLayoutPolicy.layout(
            BoardManHistorySettingsLayoutInput(originX: 18, originY: 640, width: 420)
        )

        #expect(layout.usesStackedShortcutLayout)
        #expect(layout.timestampShortcutLabelFrame.width == 420)
        #expect(layout.timestampShortcutRecordFrame.minX == 18)
        #expect(layout.timestampShortcutRecordFrame.width == 420)
        #expect(layout.timestampShortcutDelayLabelFrame.minY < layout.timestampShortcutRecordFrame.minY)
        #expect(layout.timedPinDurationLabelFrame.minY < layout.timestampShortcutDelayLabelFrame.minY)
        #expect(layout.exportHistoryFrame.minY < layout.timedPinDurationValueFrame.minY)
    }

    @Test
    func baseActionsRemainOrderedAndBounded() {
        let layout = BoardManHistorySettingsLayoutPolicy.layout(
            BoardManHistorySettingsLayoutInput(originX: 30, originY: 700, width: 500)
        )

        #expect(layout.sectionHeaderFrame.minY > layout.dedupeFrame.minY)
        #expect(layout.dedupeFrame.minY > layout.reuseTopFrame.minY)
        #expect(layout.reuseTopFrame.minY > layout.overwriteSameHistoryFrame.minY)
        #expect(layout.overwriteSameHistoryFrame.minY > layout.skipPinnedNavigationFrame.minY)
        #expect(layout.longPressPopupFrame.maxX <= 530)
        #expect(layout.timestampInteractionPopupFrame.maxX <= 530)
        #expect(layout.clearHistoryFrame.maxX <= 530)
    }
}
