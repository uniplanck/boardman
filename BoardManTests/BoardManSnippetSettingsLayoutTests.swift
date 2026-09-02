import AppKit
import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class BoardManSnippetSettingsLayoutTests {
    @Test
    func shortcutRowsStayInsideBoundedScrollSurface() throws {
        let layout = BoardManSnippetSettingsLayoutPolicy.layout(
            originX: 26,
            originY: 656,
            width: 520,
            requestedScrollHeight: 360,
            shortcutCount: 8
        )
        let first = try #require(layout.shortcutRows.first)
        let last = try #require(layout.shortcutRows.last)

        #expect(layout.shortcutScrollFrame.height <= 280)
        #expect(layout.shortcutScrollFrame.height >= 80)
        #expect(layout.shortcutDocumentFrame.height >= CGFloat(8 * 42))
        #expect(layout.shortcutRows.count == 8)
        #expect(first.titleFrame.maxY <= layout.shortcutDocumentFrame.maxY)
        #expect(last.detailFrame.minY >= 0)
        #expect(layout.shortcutRows.allSatisfy { $0.clearFrame.maxX <= 520 })
        #expect(layout.manageButtonFrame.maxY < layout.shortcutScrollFrame.minY)
    }

    @Test
    func emptyAndCompactLayoutsPreserveMinimumUsableGeometry() {
        let layout = BoardManSnippetSettingsLayoutPolicy.layout(
            originX: 18,
            originY: 430,
            width: 320,
            requestedScrollHeight: 60,
            shortcutCount: 0
        )

        #expect(layout.shortcutRows.isEmpty)
        #expect(layout.shortcutScrollFrame.height == 80)
        #expect(layout.shortcutDocumentFrame.height == 80)
        #expect(layout.groupOrderFrame.width >= 120)
        #expect(layout.moveDownFrame.maxX <= 338)
        #expect(layout.manageButtonFrame.width <= 156)
    }
}
