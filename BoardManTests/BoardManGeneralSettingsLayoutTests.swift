import AppKit
import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class BoardManGeneralSettingsLayoutTests {
    @Test
    func generalSectionKeepsControlsOrderedAndInsideColumn() {
        let layout = BoardManGeneralSettingsLayoutPolicy.generalSection(
            originX: 26,
            originY: 656,
            width: 520
        )

        #expect(layout.sectionHeaderFrame.minX == 26)
        #expect(layout.launchOnLoginFrame.maxX <= 546)
        #expect(layout.languageControlFrame.minX > layout.languageLabelFrame.minX)
        #expect(layout.maxHistoryDecreaseFrame.maxX <= layout.maxHistoryValueFrame.minX)
        #expect(layout.maxHistoryValueFrame.maxX <= layout.maxHistoryIncreaseFrame.minX)
        #expect(layout.statusItemControlFrame.maxX <= 546)
        #expect(layout.statusItemControlFrame.minY < layout.languageControlFrame.minY)
    }

    @Test
    func shortcutSectionScalesRowsWithoutOverlappingActions() throws {
        let layout = BoardManGeneralSettingsLayoutPolicy.shortcutSection(
            originX: 26,
            originY: 416,
            width: 520,
            rowCount: 5
        )
        let first = try #require(layout.rows.first)
        let last = try #require(layout.rows.last)

        #expect(layout.rows.count == 5)
        #expect(first.recordFrame.minX > first.titleFrame.minX)
        #expect(first.recordFrame.maxX <= first.clearFrame.minX)
        #expect(last.titleFrame.minY < first.titleFrame.minY)
        #expect(layout.statusFrame.maxY <= last.detailFrame.minY)
        #expect(layout.rows.allSatisfy { $0.clearFrame.maxX <= 546 })
    }
}
