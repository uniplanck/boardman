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
    let permissionsHeaderFrame: NSRect
    let permissionsStatusFrame: NSRect
    let permissionsManageFrame: NSRect
    let privacyHeaderFrame: NSRect
    let selectionMemoryFrame: NSRect
    let selectionHarvestFrame: NSRect
    let selectionSequentialCaptureFrame: NSRect
    let selectionMemoryStatusFrame: NSRect
    let selectionMemoryOpenFrame: NSRect
    let selectionMemoryClearFrame: NSRect
    let selectionPreviewEnabledFrame: NSRect
    let selectionPreviewPositionLabelFrame: NSRect
    let selectionPreviewPositionFrame: NSRect
    let selectionPreviewStyleLabelFrame: NSRect
    let selectionPreviewStyleFrame: NSRect
    let selectionMetadataPositionLabelFrame: NSRect
    let selectionMetadataPositionFrame: NSRect
    let selectionAutoDeleteUsedFrame: NSRect
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
        let privacyOriginY = input.originY - 86
        let storedOriginY = privacyOriginY - 522
        let storedTypeFrames = storedTypes(
            originX: input.originX,
            originY: storedOriginY,
            width: input.width,
            count: input.storedTypeCount,
            rowGap: input.rowGap
        )
        let storedBottomY = storedTypeFrames.map(\.minY).min() ?? storedOriginY
        let filterOriginY = storedBottomY - 42
        let filter = filterFrames(
            originX: input.originX,
            originY: filterOriginY,
            width: input.width,
            controlHeight: input.controlHeight,
            rowGap: input.rowGap
        )
        let clearWidth: CGFloat = 72
        let openWidth: CGFloat = 104
        let actionGap: CGFloat = 8
        let actionsWidth = clearWidth + openWidth + actionGap
        let statusWidth = max(120, input.width - actionsWidth - 10)

        let permissionButtonWidth: CGFloat = min(116, max(96, floor(input.width * 0.24)))
        return BoardManPrivacySettingsLayout(
            permissionsHeaderFrame: NSRect(x: input.originX, y: input.originY, width: input.width, height: 18),
            permissionsStatusFrame: NSRect(
                x: input.originX,
                y: input.originY - 42,
                width: max(120, input.width - permissionButtonWidth - 12),
                height: 30
            ),
            permissionsManageFrame: NSRect(
                x: input.originX + max(0, input.width - permissionButtonWidth),
                y: input.originY - 48,
                width: permissionButtonWidth,
                height: input.controlHeight
            ),
            privacyHeaderFrame: NSRect(x: input.originX, y: privacyOriginY, width: input.width, height: 18),
            selectionMemoryFrame: NSRect(x: input.originX, y: privacyOriginY - 38, width: input.width, height: 20),
            selectionHarvestFrame: NSRect(x: input.originX + 18, y: privacyOriginY - 70, width: input.width - 18, height: 20),
            selectionSequentialCaptureFrame: NSRect(x: input.originX + 18, y: privacyOriginY - 100, width: input.width - 18, height: 20),
            selectionMemoryStatusFrame: NSRect(x: input.originX, y: privacyOriginY - 135, width: statusWidth, height: 18),
            selectionMemoryOpenFrame: NSRect(
                x: input.originX + max(0, input.width - actionsWidth),
                y: privacyOriginY - 141,
                width: openWidth,
                height: input.controlHeight
            ),
            selectionMemoryClearFrame: NSRect(
                x: input.originX + max(0, input.width - clearWidth),
                y: privacyOriginY - 141,
                width: clearWidth,
                height: input.controlHeight
            ),
            selectionPreviewEnabledFrame: NSRect(x: input.originX + 18, y: privacyOriginY - 178, width: input.width - 18, height: 20),
            selectionPreviewPositionLabelFrame: NSRect(x: input.originX + 18, y: privacyOriginY - 218, width: 120, height: 18),
            selectionPreviewPositionFrame: NSRect(x: input.originX + 146, y: privacyOriginY - 224, width: max(120, input.width - 146), height: input.controlHeight),
            selectionPreviewStyleLabelFrame: NSRect(x: input.originX + 18, y: privacyOriginY - 256, width: 120, height: 18),
            selectionPreviewStyleFrame: NSRect(x: input.originX + 146, y: privacyOriginY - 262, width: max(120, input.width - 146), height: input.controlHeight),
            selectionMetadataPositionLabelFrame: NSRect(x: input.originX + 18, y: privacyOriginY - 296, width: 120, height: 18),
            selectionMetadataPositionFrame: NSRect(x: input.originX + 146, y: privacyOriginY - 302, width: max(120, input.width - 146), height: input.controlHeight),
            selectionAutoDeleteUsedFrame: NSRect(x: input.originX + 18, y: privacyOriginY - 340, width: input.width - 18, height: 20),
            hideMaskedPreviewFrame: NSRect(x: input.originX, y: privacyOriginY - 376, width: input.width, height: 20),
            hideMaskedTitleFrame: NSRect(x: input.originX, y: privacyOriginY - 406, width: input.width, height: 20),
            excludedAppsSummaryFrame: NSRect(x: input.originX, y: privacyOriginY - 442, width: input.width, height: 18),
            excludedAppsButtonFrame: NSRect(
                x: input.originX,
                y: privacyOriginY - 480,
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
