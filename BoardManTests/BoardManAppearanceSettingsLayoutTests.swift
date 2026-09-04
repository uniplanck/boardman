import AppKit
import Testing
@testable import Board_Man

@Suite
struct BoardManAppearanceSettingsLayoutTests {
    @Test
    func appearanceSettingsExposeHistoryAndSelectionCopyScopes() {
        #expect(BoardManAppearanceSettingsTab.allCases == [.historyAndSnippets, .selectionCopy])
        #expect(BoardManAppearanceSettingsTab.historyAndSnippets.rawValue == 0)
        #expect(BoardManAppearanceSettingsTab.selectionCopy.rawValue == 1)
        #expect(!BoardManAppearanceSettingsTab.historyAndSnippets.title.isEmpty)
        #expect(!BoardManAppearanceSettingsTab.selectionCopy.title.isEmpty)
        #expect(Constants.UserDefaults.boardManSelectionThemePreset != Constants.UserDefaults.boardManThemePreset)
        #expect(Constants.UserDefaults.boardManSelectionUsedItemStyle != Constants.UserDefaults.boardManUsedItemStyle)
        #expect(Constants.UserDefaults.boardManSelectionRelativeNumberStyle != Constants.UserDefaults.boardManRelativeNumberStyle)
        #expect(Constants.UserDefaults.boardManSelectionCustomAccentColor != Constants.UserDefaults.boardManCustomAccentColor)
        #expect(Constants.UserDefaults.boardManSelectionCustomPanelColor != Constants.UserDefaults.boardManCustomPanelColor)
        #expect(Constants.UserDefaults.boardManSelectionTextPreviewScale != Constants.UserDefaults.boardManTextPreviewScale)
    }

    @Test
    func selectionRelativeTimestampStyleUsesDedicatedValuesAndFallsBackToHistory() {
        let suite = "BoardManAppearanceSettingsLayoutTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Could not create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(BoardManRelativeNumberStyle.twoDigits.rawValue,
                     forKey: Constants.UserDefaults.boardManRelativeNumberStyle)
        defaults.set(BoardManRelativeUnitStyle.full.rawValue,
                     forKey: Constants.UserDefaults.boardManRelativeUnitStyle)
        defaults.set(BoardManRelativeSuffixStyle.ago.rawValue,
                     forKey: Constants.UserDefaults.boardManRelativeSuffixStyle)
        defaults.set(BoardManRelativeNowStyle.now.rawValue,
                     forKey: Constants.UserDefaults.boardManRelativeNowStyle)

        let entitlementService = EntitlementService(snapshot: .proActive())
        let inherited = BoardManRelativeTimestampStyle.selectionCurrent(
            defaults: defaults,
            entitlementService: entitlementService
        )
        #expect(inherited.number == .twoDigits)
        #expect(inherited.text(seconds: 480, language: .english) == "08 min ago")

        defaults.set(BoardManRelativeNumberStyle.single.rawValue,
                     forKey: Constants.UserDefaults.boardManSelectionRelativeNumberStyle)
        defaults.set(BoardManRelativeUnitStyle.symbol.rawValue,
                     forKey: Constants.UserDefaults.boardManSelectionRelativeUnitStyle)
        defaults.set(BoardManRelativeSuffixStyle.none.rawValue,
                     forKey: Constants.UserDefaults.boardManSelectionRelativeSuffixStyle)
        let dedicated = BoardManRelativeTimestampStyle.selectionCurrent(
            defaults: defaults,
            entitlementService: entitlementService
        )
        #expect(dedicated.number == .single)
        #expect(dedicated.text(seconds: 480, language: .english) == "8m")
    }

    @Test
    func appearanceLayoutAlwaysUsesOneColumnWithCommonCardsBeforeScopeTabs() throws {
        let layout = BoardManAppearanceSettingsLayoutPolicy.layout(
            BoardManAppearanceSettingsLayoutInput(
                originX: 20,
                originY: 2_100,
                width: 560,
                controlHeight: 30,
                advancedExpanded: false
            )
        )
        let advanced = try #require(layout.advanced)
        let cards = [
            layout.layoutCardFrame, layout.usageCardFrame, layout.previewCardFrame,
            layout.timestampCardFrame, layout.itemCardFrame, layout.themeCardFrame,
            advanced.cardFrame
        ]

        #expect(layout.stacksCards)
        #expect(layout.advancedToggleFrame == .zero)
        #expect(cards.allSatisfy { abs($0.minX - layout.layoutCardFrame.minX) <= 0.5 })
        #expect(cards.allSatisfy { abs($0.width - layout.layoutCardFrame.width) <= 0.5 })
        #expect(layout.usageCardFrame.maxY < layout.layoutCardFrame.minY)
        #expect(layout.scopeTabsFrame.maxY < layout.usageCardFrame.minY)
        #expect(layout.previewCardFrame.maxY < layout.scopeTabsFrame.minY)
        #expect(layout.timestampCardFrame.maxY < layout.previewCardFrame.minY)
        #expect(layout.itemCardFrame.maxY < layout.timestampCardFrame.minY)
        #expect(layout.themeCardFrame.maxY < layout.itemCardFrame.minY)
        #expect(advanced.cardFrame.maxY < layout.themeCardFrame.minY)
        #expect(layout.uiStyle.controlFrame.maxX <= layout.layoutCardFrame.maxX - 16)
        #expect(layout.usageStyle.controlFrame.maxX <= layout.usageCardFrame.maxX - 16)
        #expect(layout.inlineImagePosition.controlFrame.maxX <= layout.itemCardFrame.maxX - 16)
    }

    @Test
    func visualModesExposeDepthAndFutureAsDistinctStyles() {
        #expect(BoardManUIStyle.allowed("Depth") == .depth)
        #expect(BoardManUIStyle.allowed("Future") == .future)
        #expect(BoardManUIStyle.depth.usesDepth)
        #expect(BoardManUIStyle.future.usesDepth)
        #expect(BoardManUIStyle.future.usesFutureGlow)
        #expect(!BoardManUIStyle.defaultStyle.usesDepth)
    }

    @Test
    func advancedAppearanceIsAlwaysVisibleAndVerticallyOrdered() throws {
        let layout = BoardManAppearanceSettingsLayoutPolicy.layout(
            BoardManAppearanceSettingsLayoutInput(
                originX: 18,
                originY: 2_100,
                width: 430,
                controlHeight: 30,
                advancedExpanded: false
            )
        )
        let advanced = try #require(layout.advanced)

        #expect(layout.stacksCards)
        #expect(layout.advancedToggleFrame == .zero)
        #expect(advanced.relativeUnit.controlFrame.maxY < advanced.relativeNumber.controlFrame.minY)
        #expect(advanced.relativeSuffix.controlFrame.maxY < advanced.relativeUnit.controlFrame.minY)
        #expect(advanced.relativeNow.controlFrame.maxY < advanced.relativeSuffix.controlFrame.minY)
        #expect(advanced.customPanel.colorWellFrame.maxY < advanced.customAccent.colorWellFrame.minY)
        #expect(advanced.customUsed.colorWellFrame.maxY < advanced.customPanel.colorWellFrame.minY)
        #expect(advanced.textPreviewScale.sliderFrame.maxY < advanced.resetCustomColorsFrame.minY)
        #expect(advanced.imagePreviewScale.sliderFrame.maxY < advanced.textPreviewScale.sliderFrame.minY)
        #expect(advanced.textPreviewScale.valueFrame.maxX <= advanced.cardFrame.maxX - 16)
        #expect(advanced.previewScaleProNoteFrame.minY >= advanced.cardFrame.minY)
    }
}
