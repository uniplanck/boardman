import AppKit

struct BoardManPrivacySettingsLayoutInput: Equatable {
    let originX: CGFloat
    let originY: CGFloat
    let width: CGFloat
    let storedTypeCount: Int
    let controlHeight: CGFloat
    let rowGap: CGFloat

    init(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        storedTypeCount: Int,
        controlHeight: CGFloat = BoardManPanelLayoutMetrics.controlHeight,
        rowGap: CGFloat = 38
    ) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.storedTypeCount = storedTypeCount
        self.controlHeight = controlHeight
        self.rowGap = rowGap
    }
}

struct BoardManPrivacySettingsLayout: Equatable {
    let privacyHeaderFrame: NSRect
    let hideMaskedPreviewFrame: NSRect
    let hideMaskedTitleFrame: NSRect
    let excludedAppsSummaryFrame: NSRect
    let excludedAppsButtonFrame: NSRect

    let storedTypesHeaderFrame: NSRect
    let storedTypeFrames: [NSRect]

    let filterHeaderFrame: NSRect
    let hideRuleModeFrame: NSRect
    let hideRuleTextFrame: NSRect
    let addHideRuleFrame: NSRect
    let removeLastHideRuleFrame: NSRect
    let clearHideRulesFrame: NSRect
    let hideRulesSummaryFrame: NSRect
    let hideRulesExamplesFrame: NSRect
    let hideRulesNoteFrame: NSRect
}

enum BoardManPrivacySettingsLayoutPolicy {
    private struct FilterFrames {
        let mode: NSRect
        let text: NSRect
        let add: NSRect
        let removeLast: NSRect
        let clear: NSRect
        let summary: NSRect
        let examples: NSRect
        let note: NSRect
    }

    static func layout(_ input: BoardManPrivacySettingsLayoutInput) -> BoardManPrivacySettingsLayout {
        let storedOriginY = input.originY - 190
        let filterOriginY = input.originY - 364
        let storedTypeFrames = storedTypes(
            originX: input.originX,
            originY: storedOriginY,
            width: input.width,
            count: input.storedTypeCount,
            rowGap: input.rowGap
        )
        let filter = filterFrames(
            originX: input.originX,
            originY: filterOriginY,
            width: input.width,
            controlHeight: input.controlHeight,
            rowGap: input.rowGap
        )

        return BoardManPrivacySettingsLayout(
            privacyHeaderFrame: NSRect(x: input.originX, y: input.originY, width: input.width, height: 18),
            hideMaskedPreviewFrame: NSRect(x: input.originX, y: input.originY - 38, width: input.width, height: 20),
            hideMaskedTitleFrame: NSRect(x: input.originX, y: input.originY - 68, width: input.width, height: 20),
            excludedAppsSummaryFrame: NSRect(x: input.originX, y: input.originY - 104, width: input.width, height: 18),
            excludedAppsButtonFrame: NSRect(
                x: input.originX,
                y: input.originY - 144,
                width: min(178, input.width),
                height: input.controlHeight
            ),
            storedTypesHeaderFrame: NSRect(x: input.originX, y: storedOriginY, width: input.width, height: 18),
            storedTypeFrames: storedTypeFrames,
            filterHeaderFrame: NSRect(x: input.originX, y: filterOriginY, width: input.width, height: 18),
            hideRuleModeFrame: filter.mode,
            hideRuleTextFrame: filter.text,
            addHideRuleFrame: filter.add,
            removeLastHideRuleFrame: filter.removeLast,
            clearHideRulesFrame: filter.clear,
            hideRulesSummaryFrame: filter.summary,
            hideRulesExamplesFrame: filter.examples,
            hideRulesNoteFrame: filter.note
        )
    }

    private static func storedTypes(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        count: Int,
        rowGap: CGFloat
    ) -> [NSRect] {
        let buttonWidth = max(72, floor((width - 8) / 2))
        return (0..<max(0, count)).map { index in
            let column = index % 2
            let row = index / 2
            return NSRect(
                x: originX + CGFloat(column) * (buttonWidth + 8),
                y: originY - rowGap - CGFloat(row * 24),
                width: buttonWidth,
                height: 18
            )
        }
    }

    private static func filterFrames(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        controlHeight: CGFloat,
        rowGap: CGFloat
    ) -> FilterFrames {
        let addWidth: CGFloat = 52
        let modeWidth = min(112, max(92, floor(width * 0.34)))
        let textWidth = max(96, width - modeWidth - addWidth - 16)
        return FilterFrames(
            mode: NSRect(x: originX, y: originY - rowGap - 6, width: modeWidth, height: controlHeight),
            text: NSRect(
                x: originX + modeWidth + 8,
                y: originY - rowGap - 4,
                width: textWidth,
                height: controlHeight
            ),
            add: NSRect(
                x: originX + modeWidth + textWidth + 16,
                y: originY - rowGap - 6,
                width: addWidth,
                height: controlHeight
            ),
            removeLast: NSRect(x: originX, y: originY - (rowGap * 2) - 8, width: 100, height: controlHeight),
            clear: NSRect(x: originX + 108, y: originY - (rowGap * 2) - 8, width: 64, height: controlHeight),
            summary: NSRect(x: originX, y: originY - (rowGap * 3) - 2, width: width, height: 18),
            examples: NSRect(x: originX, y: originY - (rowGap * 3) - 22, width: width, height: 18),
            note: NSRect(x: originX, y: originY - (rowGap * 3) - 42, width: width, height: 18)
        )
    }
}
