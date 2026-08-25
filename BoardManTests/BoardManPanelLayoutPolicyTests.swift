import AppKit
import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class BoardManPanelLayoutPolicyTests {
    @Test
    func regularHistoryLayoutKeepsHeaderToolbarAndListBounded() {
        let bounds = NSRect(x: 0, y: 0, width: 800, height: 760)
        let layout = BoardManPanelLayoutPolicy.panelLayout(
            bounds: bounds,
            isQuickMode: false,
            activeTab: .history,
            activeSettingsCategory: .general,
            appearanceAdvancedExpanded: false,
            searchIntrinsicHeight: 30
        )

        #expect(!layout.isCompact)
        #expect(layout.margin == BoardManPanelLayoutMetrics.outerMargin)
        #expect(layout.showsHistoryToolbar)
        #expect(!layout.showsSnippetButtons)
        #expect(!layout.showsSnippetCategories)
        #expect(layout.tabsFrame.minX >= 0)
        #expect(layout.settingsButtonFrame.maxX <= bounds.maxX)
        #expect(layout.searchFrame.maxX <= layout.settingsButtonFrame.minX)
        #expect(layout.historySavedFilterFrame.maxX <= bounds.maxX)
        #expect(layout.listFrame.minY >= 0)
        #expect(layout.listFrame.maxX <= bounds.maxX)
    }

    @Test
    func compactSnippetLayoutAllocatesButtonsCategoriesAndEditorWithoutOverlap() {
        let bounds = NSRect(x: 0, y: 0, width: 680, height: 760)
        let layout = BoardManPanelLayoutPolicy.panelLayout(
            bounds: bounds,
            isQuickMode: false,
            activeTab: .snippets,
            activeSettingsCategory: .general,
            appearanceAdvancedExpanded: false,
            searchIntrinsicHeight: 34
        )

        #expect(layout.isCompact)
        #expect(layout.showsSnippetButtons)
        #expect(layout.showsSnippetCategories)
        #expect(layout.snippetButtonFrames.count == 3)
        #expect(layout.snippetCategoryButtonFrames.count == 3)
        #expect(layout.searchFrame.height == 32)
        #expect(layout.listFrame.maxX <= layout.snippetEditorFrame.minX)
        #expect(layout.snippetEditorFrame.width >= 300)
        #expect(layout.snippetReorderFrame.maxX <= bounds.maxX)
    }

    @Test
    func quickModeUsesCompactMarginsAndSingleListSurface() {
        let bounds = NSRect(x: 0, y: 0, width: 680, height: 260)
        let layout = BoardManPanelLayoutPolicy.panelLayout(
            bounds: bounds,
            isQuickMode: true,
            activeTab: .history,
            activeSettingsCategory: .general,
            appearanceAdvancedExpanded: false,
            searchIntrinsicHeight: 30
        )

        #expect(layout.margin == 12)
        #expect(!layout.showsSnippetButtons)
        #expect(!layout.showsSnippetCategories)
        #expect(layout.listFrame.minY == 12)
        #expect(layout.listFrame.height >= 1)
    }

    @Test
    func settingsHeightAndSidebarPolicyRemainDeterministic() {
        #expect(BoardManPanelLayoutPolicy.settingsDocumentHeight(
            viewportHeight: 500,
            contentWidth: 560,
            category: .view,
            appearanceAdvancedExpanded: false
        ) == 1_020)
        #expect(BoardManPanelLayoutPolicy.settingsDocumentHeight(
            viewportHeight: 500,
            contentWidth: 440,
            category: .view,
            appearanceAdvancedExpanded: true
        ) == 1_720)
        #expect(BoardManPanelLayoutPolicy.settingsDocumentHeight(
            viewportHeight: 900,
            contentWidth: 560,
            category: .updates,
            appearanceAdvancedExpanded: false
        ) == 900)

        let frames = BoardManPanelLayoutPolicy.settingsSidebarButtonFrames(
            width: 184,
            height: 500,
            count: BoardManInlineSettingsCategory.allCases.count
        )
        #expect(frames.count == BoardManInlineSettingsCategory.allCases.count)
        #expect(frames.first?.maxY == 488)
        #expect(frames.last?.minY ?? -1 >= 0)
        #expect(BoardManPanelLayoutPolicy.usesStackedHistorySettingsLayout(width: 519))
        #expect(!BoardManPanelLayoutPolicy.usesStackedHistorySettingsLayout(width: 520))
        #expect(BoardManPanelLayoutPolicy.usesStackedAppearanceSettingsLayout(width: 469))
        #expect(!BoardManPanelLayoutPolicy.usesStackedAppearanceSettingsLayout(width: 470))
    }
}
