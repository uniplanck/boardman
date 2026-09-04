import AppKit

enum BoardManAppearanceSettingsTab: Int, CaseIterable {
    case historyAndSnippets
    case selectionCopy

    var title: String {
        switch self {
        case .historyAndSnippets:
            return boardManText("History & Templates")
        case .selectionCopy:
            return boardManText("Selection Copy")
        }
    }
}

struct BoardManAppearanceLabeledRowLayout: Equatable {
    let labelFrame: NSRect
    let controlFrame: NSRect
}

struct BoardManAppearanceStepperLayout: Equatable {
    let labelFrame: NSRect
    let decreaseFrame: NSRect
    let valueFrame: NSRect
    let increaseFrame: NSRect
}

struct BoardManAppearanceColorRowLayout: Equatable {
    let labelFrame: NSRect
    let colorWellFrame: NSRect
    let sliderFrame: NSRect
}

struct BoardManAppearancePreviewScaleRowLayout: Equatable {
    let labelFrame: NSRect
    let sliderFrame: NSRect
    let valueFrame: NSRect
}

struct BoardManAppearanceAdvancedSettingsLayout: Equatable {
    let cardFrame: NSRect
    let relativeNumber: BoardManAppearanceLabeledRowLayout
    let relativeUnit: BoardManAppearanceLabeledRowLayout
    let relativeSuffix: BoardManAppearanceLabeledRowLayout
    let relativeNow: BoardManAppearanceLabeledRowLayout
    let customAccent: BoardManAppearanceColorRowLayout
    let customPanel: BoardManAppearanceColorRowLayout
    let customUsed: BoardManAppearanceColorRowLayout
    let resetCustomColorsFrame: NSRect
    let textPreviewScale: BoardManAppearancePreviewScaleRowLayout
    let imagePreviewScale: BoardManAppearancePreviewScaleRowLayout
    let previewScaleProNoteFrame: NSRect
}

struct BoardManAppearanceSettingsLayout: Equatable {
    let stacksCards: Bool
    let layoutCardFrame: NSRect
    let usageCardFrame: NSRect
    let scopeTabsFrame: NSRect
    let previewCardFrame: NSRect
    let previewFrame: NSRect
    let timestampCardFrame: NSRect
    let itemCardFrame: NSRect
    let themeCardFrame: NSRect
    let rowNumbersFrame: NSRect
    let uiStyle: BoardManAppearanceLabeledRowLayout
    let itemTextScale: BoardManAppearanceStepperLayout
    let itemRowHeight: BoardManAppearanceStepperLayout
    let heightControl: BoardManAppearanceStepperLayout
    let appearanceMode: BoardManAppearanceLabeledRowLayout
    let usageCountFrame: NSRect
    let usageStyle: BoardManAppearanceLabeledRowLayout
    let timestamp: BoardManAppearanceLabeledRowLayout
    let timestampPosition: BoardManAppearanceLabeledRowLayout
    let usedItemStyle: BoardManAppearanceLabeledRowLayout
    let pinLabelStyle: BoardManAppearanceLabeledRowLayout
    let showInlineImagesFrame: NSRect
    let inlineImagePosition: BoardManAppearanceLabeledRowLayout
    let themePreset: BoardManAppearanceLabeledRowLayout
    let fontChoice: BoardManAppearanceLabeledRowLayout
    let themeLightenFrame: NSRect
    let advancedToggleFrame: NSRect
    let advanced: BoardManAppearanceAdvancedSettingsLayout?
}

struct BoardManAppearanceSettingsLayoutInput: Equatable {
    let originX: CGFloat
    let originY: CGFloat
    let width: CGFloat
    let controlHeight: CGFloat
    let advancedExpanded: Bool
}

private struct BoardManAppearanceScopedSettingsLayout {
    let timestampCardFrame: NSRect
    let timestamp: BoardManAppearanceLabeledRowLayout
    let timestampPosition: BoardManAppearanceLabeledRowLayout
    let itemCardFrame: NSRect
    let rowNumbersFrame: NSRect
    let usedItemStyle: BoardManAppearanceLabeledRowLayout
    let pinLabelStyle: BoardManAppearanceLabeledRowLayout
    let showInlineImagesFrame: NSRect
    let inlineImagePosition: BoardManAppearanceLabeledRowLayout
    let themeCardFrame: NSRect
    let themePreset: BoardManAppearanceLabeledRowLayout
    let fontChoice: BoardManAppearanceLabeledRowLayout
    let themeLightenFrame: NSRect
}

enum BoardManAppearanceSettingsLayoutPolicy {
    private static let cardGap: CGFloat = 14
    private static let cardInset: CGFloat = 18
    private static let rowGap: CGFloat = 42

    static func layout(_ input: BoardManAppearanceSettingsLayoutInput) -> BoardManAppearanceSettingsLayout {
        // Appearance settings are intentionally one column at every supported panel width.
        // The former two-column card grid caused labels and popup titles to be truncated at
        // normal Board-Man widths, especially after localization.
        let fullWidth = input.width
        let innerX = input.originX + cardInset
        let innerWidth = max(180, fullWidth - (cardInset * 2))
        let labelWidth = min(126, max(92, floor(innerWidth * 0.24)))

        let layoutCardHeight: CGFloat = 282
        let layoutCardY = input.originY - layoutCardHeight
        let layoutCardFrame = integralRect(
            x: input.originX,
            y: layoutCardY,
            width: fullWidth,
            height: layoutCardHeight
        )
        let uiStyle = labeledRow(
            originX: innerX,
            originY: layoutCardY + layoutCardHeight - 96,
            width: innerWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let itemTextScale = stepperRow(
            originX: innerX,
            originY: uiStyle.controlFrame.minY - rowGap,
            width: innerWidth,
            labelWidth: labelWidth,
            valueWidth: 64,
            controlHeight: input.controlHeight
        )
        let itemRowHeight = stepperRow(
            originX: innerX,
            originY: itemTextScale.valueFrame.minY - rowGap,
            width: innerWidth,
            labelWidth: labelWidth,
            valueWidth: 64,
            controlHeight: input.controlHeight
        )
        let heightControl = stepperRow(
            originX: innerX,
            originY: itemRowHeight.valueFrame.minY - rowGap,
            width: innerWidth,
            labelWidth: labelWidth,
            valueWidth: 70,
            controlHeight: input.controlHeight
        )
        let appearanceMode = labeledRow(
            originX: innerX,
            originY: heightControl.valueFrame.minY - rowGap,
            width: innerWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )

        let usageCardHeight: CGFloat = 150
        let usageCardY = layoutCardY - cardGap - usageCardHeight
        let usageCardFrame = integralRect(
            x: input.originX,
            y: usageCardY,
            width: fullWidth,
            height: usageCardHeight
        )
        let usageCountFrame = integralRect(
            x: innerX,
            y: usageCardY + usageCardHeight - 82,
            width: innerWidth,
            height: 20
        )
        let usageStyle = labeledRow(
            originX: innerX,
            originY: usageCardY + 18,
            width: innerWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )

        let tabsHeight: CGFloat = 28
        let tabsY = usageCardY - cardGap - tabsHeight
        let scopeTabsFrame = integralRect(
            x: input.originX,
            y: tabsY,
            width: fullWidth,
            height: tabsHeight
        )

        let previewHeight: CGFloat = 172
        let previewY = tabsY - cardGap - previewHeight
        let previewInset: CGFloat = 22
        let previewCardFrame = integralRect(
            x: input.originX,
            y: previewY,
            width: fullWidth,
            height: previewHeight
        )
        let previewFrame = integralRect(
            x: input.originX + previewInset,
            y: previewY + 18,
            width: max(160, fullWidth - (previewInset * 2)),
            height: previewHeight - 70
        )

        let scoped = scopedLayout(input: input, previewY: previewY)
        let advanced = advancedLayout(
            input: input,
            topY: scoped.themeCardFrame.minY - cardGap,
            labelWidth: labelWidth
        )

        return BoardManAppearanceSettingsLayout(
            stacksCards: true,
            layoutCardFrame: layoutCardFrame,
            usageCardFrame: usageCardFrame,
            scopeTabsFrame: scopeTabsFrame,
            previewCardFrame: previewCardFrame,
            previewFrame: previewFrame,
            timestampCardFrame: scoped.timestampCardFrame,
            itemCardFrame: scoped.itemCardFrame,
            themeCardFrame: scoped.themeCardFrame,
            rowNumbersFrame: scoped.rowNumbersFrame,
            uiStyle: uiStyle,
            itemTextScale: itemTextScale,
            itemRowHeight: itemRowHeight,
            heightControl: heightControl,
            appearanceMode: appearanceMode,
            usageCountFrame: usageCountFrame,
            usageStyle: usageStyle,
            timestamp: scoped.timestamp,
            timestampPosition: scoped.timestampPosition,
            usedItemStyle: scoped.usedItemStyle,
            pinLabelStyle: scoped.pinLabelStyle,
            showInlineImagesFrame: scoped.showInlineImagesFrame,
            inlineImagePosition: scoped.inlineImagePosition,
            themePreset: scoped.themePreset,
            fontChoice: scoped.fontChoice,
            themeLightenFrame: scoped.themeLightenFrame,
            advancedToggleFrame: .zero,
            advanced: advanced
        )
    }
}

private extension BoardManAppearanceSettingsLayoutPolicy {
    static func scopedLayout(
        input: BoardManAppearanceSettingsLayoutInput,
        previewY: CGFloat
    ) -> BoardManAppearanceScopedSettingsLayout {
        let fullWidth = input.width
        let innerX = input.originX + cardInset
        let innerWidth = max(180, fullWidth - (cardInset * 2))
        let labelWidth = min(126, max(92, floor(innerWidth * 0.24)))
        let timestampCardHeight: CGFloat = 170
        let timestampCardY = previewY - cardGap - timestampCardHeight
        let timestampCardFrame = integralRect(
            x: input.originX,
            y: timestampCardY,
            width: fullWidth,
            height: timestampCardHeight
        )
        let timestamp = labeledRow(
            originX: innerX,
            originY: timestampCardY + timestampCardHeight - 94,
            width: innerWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let timestampPosition = labeledRow(
            originX: innerX,
            originY: timestamp.controlFrame.minY - 46,
            width: innerWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )

        let itemCardHeight: CGFloat = 260
        let itemCardY = timestampCardY - cardGap - itemCardHeight
        let itemCardFrame = integralRect(
            x: input.originX,
            y: itemCardY,
            width: fullWidth,
            height: itemCardHeight
        )
        let rowNumbersFrame = integralRect(
            x: innerX,
            y: itemCardY + itemCardHeight - 82,
            width: innerWidth,
            height: 20
        )
        let usedItemStyle = labeledRow(
            originX: innerX,
            originY: itemCardY + itemCardHeight - 132,
            width: innerWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let pinLabelStyle = labeledRow(
            originX: innerX,
            originY: usedItemStyle.controlFrame.minY - rowGap,
            width: innerWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let showInlineImagesFrame = integralRect(
            x: innerX,
            y: pinLabelStyle.controlFrame.minY - 38,
            width: innerWidth,
            height: 20
        )
        let inlineImagePosition = labeledRow(
            originX: innerX,
            originY: itemCardY + 10,
            width: innerWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )

        let themeCardHeight: CGFloat = 220
        let themeCardY = itemCardY - cardGap - themeCardHeight
        let themeCardFrame = integralRect(
            x: input.originX,
            y: themeCardY,
            width: fullWidth,
            height: themeCardHeight
        )
        let themePreset = labeledRow(
            originX: innerX,
            originY: themeCardY + themeCardHeight - 94,
            width: innerWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let fontChoice = labeledRow(
            originX: innerX,
            originY: themePreset.controlFrame.minY - 46,
            width: innerWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let themeLightenFrame = integralRect(
            x: innerX,
            y: themeCardY + 20,
            width: innerWidth,
            height: 20
        )
        return BoardManAppearanceScopedSettingsLayout(
            timestampCardFrame: timestampCardFrame,
            timestamp: timestamp,
            timestampPosition: timestampPosition,
            itemCardFrame: itemCardFrame,
            rowNumbersFrame: rowNumbersFrame,
            usedItemStyle: usedItemStyle,
            pinLabelStyle: pinLabelStyle,
            showInlineImagesFrame: showInlineImagesFrame,
            inlineImagePosition: inlineImagePosition,
            themeCardFrame: themeCardFrame,
            themePreset: themePreset,
            fontChoice: fontChoice,
            themeLightenFrame: themeLightenFrame
        )
    }

    static func advancedLayout(
        input: BoardManAppearanceSettingsLayoutInput,
        topY: CGFloat,
        labelWidth: CGFloat
    ) -> BoardManAppearanceAdvancedSettingsLayout {
        let advancedHeight: CGFloat = 560
        let advancedY = topY - advancedHeight
        let advancedX = input.originX + cardInset
        let advancedWidth = max(180, input.width - (cardInset * 2))
        let cardFrame = integralRect(
            x: input.originX,
            y: advancedY,
            width: input.width,
            height: advancedHeight
        )

        let relativeNumber = labeledRow(
            originX: advancedX,
            originY: advancedY + advancedHeight - 96,
            width: advancedWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let relativeUnit = labeledRow(
            originX: advancedX,
            originY: relativeNumber.controlFrame.minY - rowGap,
            width: advancedWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let relativeSuffix = labeledRow(
            originX: advancedX,
            originY: relativeUnit.controlFrame.minY - rowGap,
            width: advancedWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let relativeNow = labeledRow(
            originX: advancedX,
            originY: relativeSuffix.controlFrame.minY - rowGap,
            width: advancedWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let customAccent = colorRow(
            originX: advancedX,
            originY: relativeNow.controlFrame.minY - 48,
            width: advancedWidth,
            controlHeight: input.controlHeight
        )
        let customPanel = colorRow(
            originX: advancedX,
            originY: customAccent.colorWellFrame.minY - 48,
            width: advancedWidth,
            controlHeight: input.controlHeight
        )
        let customUsed = colorRow(
            originX: advancedX,
            originY: customPanel.colorWellFrame.minY - 48,
            width: advancedWidth,
            controlHeight: input.controlHeight
        )
        let resetCustomColorsFrame = integralRect(
            x: advancedX,
            y: customUsed.colorWellFrame.minY - 42,
            width: min(190, advancedWidth),
            height: BoardManPanelLayoutMetrics.actionButtonHeight
        )
        let textPreviewScale = previewScaleRow(
            originX: advancedX,
            originY: resetCustomColorsFrame.minY - 48,
            width: advancedWidth,
            controlHeight: input.controlHeight
        )
        let imagePreviewScale = previewScaleRow(
            originX: advancedX,
            originY: textPreviewScale.sliderFrame.minY - 46,
            width: advancedWidth,
            controlHeight: input.controlHeight
        )
        let previewScaleProNoteFrame = integralRect(
            x: advancedX,
            y: advancedY + 14,
            width: advancedWidth,
            height: 28
        )

        return BoardManAppearanceAdvancedSettingsLayout(
            cardFrame: cardFrame,
            relativeNumber: relativeNumber,
            relativeUnit: relativeUnit,
            relativeSuffix: relativeSuffix,
            relativeNow: relativeNow,
            customAccent: customAccent,
            customPanel: customPanel,
            customUsed: customUsed,
            resetCustomColorsFrame: resetCustomColorsFrame,
            textPreviewScale: textPreviewScale,
            imagePreviewScale: imagePreviewScale,
            previewScaleProNoteFrame: previewScaleProNoteFrame
        )
    }

    private static func labeledRow(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        labelWidth: CGFloat,
        controlHeight: CGFloat
    ) -> BoardManAppearanceLabeledRowLayout {
        BoardManAppearanceLabeledRowLayout(
            labelFrame: integralRect(
                x: originX,
                y: originY + 7,
                width: labelWidth,
                height: 16
            ),
            controlFrame: integralRect(
                x: originX + labelWidth + 14,
                y: originY,
                width: max(150, width - labelWidth - 14),
                height: controlHeight
            )
        )
    }

    private static func stepperRow(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        labelWidth: CGFloat,
        valueWidth: CGFloat,
        controlHeight: CGFloat
    ) -> BoardManAppearanceStepperLayout {
        let controlX = originX + labelWidth + 14
        return BoardManAppearanceStepperLayout(
            labelFrame: integralRect(
                x: originX,
                y: originY + 7,
                width: labelWidth,
                height: 16
            ),
            decreaseFrame: integralRect(
                x: controlX,
                y: originY,
                width: 30,
                height: controlHeight
            ),
            valueFrame: integralRect(
                x: controlX + 38,
                y: originY,
                width: valueWidth,
                height: controlHeight
            ),
            increaseFrame: integralRect(
                x: controlX + 46 + valueWidth,
                y: originY,
                width: 30,
                height: controlHeight
            )
        )
    }

    private static func colorRow(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        controlHeight: CGFloat
    ) -> BoardManAppearanceColorRowLayout {
        let labelWidth = min(108, max(82, floor(width * 0.20)))
        let wellWidth: CGFloat = 44
        return BoardManAppearanceColorRowLayout(
            labelFrame: integralRect(
                x: originX,
                y: originY + 6,
                width: labelWidth,
                height: 16
            ),
            colorWellFrame: integralRect(
                x: originX + labelWidth + 12,
                y: originY,
                width: wellWidth,
                height: controlHeight
            ),
            sliderFrame: integralRect(
                x: originX + labelWidth + wellWidth + 24,
                y: originY + 3,
                width: max(120, width - labelWidth - wellWidth - 24),
                height: 24
            )
        )
    }

    private static func previewScaleRow(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        controlHeight: CGFloat
    ) -> BoardManAppearancePreviewScaleRowLayout {
        let labelWidth: CGFloat = 126
        let valueWidth: CGFloat = 64
        let gap: CGFloat = 12
        return BoardManAppearancePreviewScaleRowLayout(
            labelFrame: integralRect(
                x: originX,
                y: originY + 7,
                width: labelWidth,
                height: 16
            ),
            sliderFrame: integralRect(
                x: originX + labelWidth + gap,
                y: originY + 3,
                width: max(120, width - labelWidth - valueWidth - (gap * 2)),
                height: 24
            ),
            valueFrame: integralRect(
                x: originX + width - valueWidth,
                y: originY,
                width: valueWidth,
                height: controlHeight
            )
        )
    }

    private static func integralRect(
        x originX: CGFloat,
        y originY: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> NSRect {
        NSIntegralRect(NSRect(x: originX, y: originY, width: width, height: height))
    }
}
