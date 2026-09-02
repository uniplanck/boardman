import AppKit

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
    let previewCardFrame: NSRect
    let previewFrame: NSRect
    let layoutCardFrame: NSRect
    let timestampCardFrame: NSRect
    let rowNumbersFrame: NSRect
    let uiStyle: BoardManAppearanceLabeledRowLayout
    let itemTextScale: BoardManAppearanceStepperLayout
    let heightControl: BoardManAppearanceStepperLayout
    let timestamp: BoardManAppearanceLabeledRowLayout
    let timestampPosition: BoardManAppearanceLabeledRowLayout
    let usageCardFrame: NSRect
    let themeCardFrame: NSRect
    let usageCountFrame: NSRect
    let usageStyle: BoardManAppearanceLabeledRowLayout
    let usedItemStyle: BoardManAppearanceLabeledRowLayout
    let pinLabelStyle: BoardManAppearanceLabeledRowLayout
    let showInlineImagesFrame: NSRect
    let inlineImagePosition: BoardManAppearanceLabeledRowLayout
    let themePreset: BoardManAppearanceLabeledRowLayout
    let appearanceMode: BoardManAppearanceLabeledRowLayout
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

enum BoardManAppearanceSettingsLayoutPolicy {
    private static let cardGap: CGFloat = 14
    private static let columnGap: CGFloat = 14
    private static let cardInset: CGFloat = 16

    static func layout(_ input: BoardManAppearanceSettingsLayoutInput) -> BoardManAppearanceSettingsLayout {
        let stacksCards = BoardManPanelLayoutPolicy.usesStackedAppearanceSettingsLayout(width: input.width)
        let halfWidth = stacksCards ? input.width : max(188, floor((input.width - columnGap) / 2))
        let rightX = stacksCards ? input.originX : input.originX + halfWidth + columnGap
        let labelWidth: CGFloat = stacksCards ? 82 : 64

        let previewHeight: CGFloat = 172
        let previewY = input.originY - previewHeight
        let previewInset: CGFloat = 22
        let previewCardFrame = integralRect(x: input.originX, y: previewY, width: input.width, height: previewHeight)
        let previewFrame = integralRect(
            x: input.originX + previewInset,
            y: previewY + 18,
            width: max(160, input.width - (previewInset * 2)),
            height: previewHeight - 70
        )

        let layoutCardHeight: CGFloat = 218
        let timestampCardHeight: CGFloat = 218
        let layoutCardY = previewY - cardGap - layoutCardHeight
        let timestampCardY = stacksCards
            ? layoutCardY - cardGap - timestampCardHeight
            : layoutCardY
        let layoutCardFrame = integralRect(x: input.originX, y: layoutCardY, width: halfWidth, height: layoutCardHeight)
        let timestampCardFrame = integralRect(x: rightX, y: timestampCardY, width: halfWidth, height: timestampCardHeight)

        let layoutX = input.originX + cardInset
        let layoutWidth = halfWidth - (cardInset * 2)
        let rowNumbersFrame = integralRect(
            x: layoutX,
            y: layoutCardY + layoutCardHeight - 80,
            width: layoutWidth,
            height: 20
        )
        let uiStyle = labeledRow(
            originX: layoutX,
            originY: layoutCardY + layoutCardHeight - 120,
            width: layoutWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let itemTextScale = stepperRow(
            originX: layoutX,
            originY: layoutCardY + layoutCardHeight - 162,
            width: layoutWidth,
            labelWidth: labelWidth,
            valueWidth: max(52, min(58, layoutWidth - labelWidth - 94)),
            controlHeight: input.controlHeight
        )
        let heightControl = stepperRow(
            originX: layoutX,
            originY: layoutCardY + 4,
            width: layoutWidth,
            labelWidth: labelWidth,
            valueWidth: max(52, min(68, layoutWidth - labelWidth - 94)),
            controlHeight: input.controlHeight
        )

        let timestampX = rightX + cardInset
        let timestampWidth = halfWidth - (cardInset * 2)
        let timestamp = labeledRow(
            originX: timestampX,
            originY: timestampCardY + timestampCardHeight - 94,
            width: timestampWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )
        let timestampPosition = labeledRow(
            originX: timestampX,
            originY: timestampCardY + timestampCardHeight - 134,
            width: timestampWidth,
            labelWidth: labelWidth,
            controlHeight: input.controlHeight
        )

        let usageCardHeight: CGFloat = 292
        let themeCardHeight: CGFloat = 292
        let usageCardY = (stacksCards ? timestampCardY : layoutCardY) - cardGap - usageCardHeight
        let themeCardY = stacksCards ? usageCardY - cardGap - themeCardHeight : usageCardY
        let usageCardFrame = integralRect(x: input.originX, y: usageCardY, width: halfWidth, height: usageCardHeight)
        let themeCardFrame = integralRect(x: rightX, y: themeCardY, width: halfWidth, height: themeCardHeight)

        let usageX = input.originX + cardInset
        let usageWidth = halfWidth - (cardInset * 2)
        let usageCountFrame = integralRect(
            x: usageX,
            y: usageCardY + usageCardHeight - 82,
            width: usageWidth,
            height: 20
        )
        let usageStyle = labeledRow(originX: usageX, originY: usageCardY + usageCardHeight - 124, width: usageWidth, labelWidth: labelWidth, controlHeight: input.controlHeight)
        let usedItemStyle = labeledRow(originX: usageX, originY: usageCardY + usageCardHeight - 164, width: usageWidth, labelWidth: labelWidth, controlHeight: input.controlHeight)
        let pinLabelStyle = labeledRow(originX: usageX, originY: usageCardY + usageCardHeight - 204, width: usageWidth, labelWidth: labelWidth, controlHeight: input.controlHeight)
        let showInlineImagesFrame = integralRect(
            x: usageX,
            y: usageCardY + usageCardHeight - 236,
            width: usageWidth,
            height: 20
        )
        let inlineImagePosition = labeledRow(originX: usageX, originY: usageCardY + 10, width: usageWidth, labelWidth: labelWidth, controlHeight: input.controlHeight)

        let themeX = rightX + cardInset
        let themeWidth = halfWidth - (cardInset * 2)
        let themePreset = labeledRow(originX: themeX, originY: themeCardY + themeCardHeight - 86, width: themeWidth, labelWidth: labelWidth, controlHeight: input.controlHeight)
        let appearanceMode = labeledRow(originX: themeX, originY: themeCardY + themeCardHeight - 126, width: themeWidth, labelWidth: labelWidth, controlHeight: input.controlHeight)
        let fontChoice = labeledRow(originX: themeX, originY: themeCardY + themeCardHeight - 166, width: themeWidth, labelWidth: labelWidth, controlHeight: input.controlHeight)
        let themeLightenFrame = integralRect(x: themeX, y: themeCardY + 7, width: themeWidth, height: 20)

        let toggleY = (stacksCards ? themeCardY : usageCardY) - 36
        let advancedToggleFrame = integralRect(x: input.originX, y: toggleY, width: min(210, input.width), height: 26)
        let advanced = input.advancedExpanded
            ? advancedLayout(input: input, toggleY: toggleY, labelWidth: labelWidth)
            : nil

        return BoardManAppearanceSettingsLayout(
            stacksCards: stacksCards,
            previewCardFrame: previewCardFrame,
            previewFrame: previewFrame,
            layoutCardFrame: layoutCardFrame,
            timestampCardFrame: timestampCardFrame,
            rowNumbersFrame: rowNumbersFrame,
            uiStyle: uiStyle,
            itemTextScale: itemTextScale,
            heightControl: heightControl,
            timestamp: timestamp,
            timestampPosition: timestampPosition,
            usageCardFrame: usageCardFrame,
            themeCardFrame: themeCardFrame,
            usageCountFrame: usageCountFrame,
            usageStyle: usageStyle,
            usedItemStyle: usedItemStyle,
            pinLabelStyle: pinLabelStyle,
            showInlineImagesFrame: showInlineImagesFrame,
            inlineImagePosition: inlineImagePosition,
            themePreset: themePreset,
            appearanceMode: appearanceMode,
            fontChoice: fontChoice,
            themeLightenFrame: themeLightenFrame,
            advancedToggleFrame: advancedToggleFrame,
            advanced: advanced
        )
    }

    private static func advancedLayout(
        input: BoardManAppearanceSettingsLayoutInput,
        toggleY: CGFloat,
        labelWidth: CGFloat
    ) -> BoardManAppearanceAdvancedSettingsLayout {
        let advancedHeight: CGFloat = 350
        let advancedY = toggleY - cardGap - advancedHeight
        let advancedX = input.originX + cardInset
        let advancedWidth = input.width - (cardInset * 2)
        let halfWidth = max(180, floor((advancedWidth - columnGap) / 2))
        let rightX = advancedX + halfWidth + columnGap
        let cardFrame = integralRect(x: input.originX, y: advancedY, width: input.width, height: advancedHeight)

        return BoardManAppearanceAdvancedSettingsLayout(
            cardFrame: cardFrame,
            relativeNumber: labeledRow(originX: advancedX, originY: advancedY + advancedHeight - 92, width: halfWidth, labelWidth: labelWidth, controlHeight: input.controlHeight),
            relativeUnit: labeledRow(originX: rightX, originY: advancedY + advancedHeight - 92, width: halfWidth, labelWidth: labelWidth, controlHeight: input.controlHeight),
            relativeSuffix: labeledRow(originX: advancedX, originY: advancedY + advancedHeight - 132, width: halfWidth, labelWidth: labelWidth, controlHeight: input.controlHeight),
            relativeNow: labeledRow(originX: rightX, originY: advancedY + advancedHeight - 132, width: halfWidth, labelWidth: labelWidth, controlHeight: input.controlHeight),
            customAccent: colorRow(originX: advancedX, originY: advancedY + advancedHeight - 180, width: halfWidth, controlHeight: input.controlHeight),
            customPanel: colorRow(originX: rightX, originY: advancedY + advancedHeight - 180, width: halfWidth, controlHeight: input.controlHeight),
            customUsed: colorRow(originX: advancedX, originY: advancedY + advancedHeight - 220, width: halfWidth, controlHeight: input.controlHeight),
            resetCustomColorsFrame: integralRect(x: rightX, y: advancedY + advancedHeight - 222, width: min(150, halfWidth), height: BoardManPanelLayoutMetrics.actionButtonHeight),
            textPreviewScale: previewScaleRow(originX: advancedX, originY: advancedY + 74, width: advancedWidth, controlHeight: input.controlHeight),
            imagePreviewScale: previewScaleRow(originX: advancedX, originY: advancedY + 34, width: advancedWidth, controlHeight: input.controlHeight),
            previewScaleProNoteFrame: integralRect(x: advancedX, y: advancedY + 4, width: advancedWidth, height: 28)
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
            labelFrame: integralRect(x: originX, y: originY + 7, width: labelWidth, height: 16),
            controlFrame: integralRect(
                x: originX + labelWidth + 12,
                y: originY,
                width: max(118, width - labelWidth - 12),
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
        let controlX = originX + labelWidth + 12
        return BoardManAppearanceStepperLayout(
            labelFrame: integralRect(x: originX, y: originY + 7, width: labelWidth, height: 16),
            decreaseFrame: integralRect(x: controlX, y: originY, width: 28, height: controlHeight),
            valueFrame: integralRect(x: controlX + 34, y: originY, width: valueWidth, height: controlHeight),
            increaseFrame: integralRect(x: controlX + 40 + valueWidth, y: originY, width: 28, height: controlHeight)
        )
    }

    private static func colorRow(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        controlHeight: CGFloat
    ) -> BoardManAppearanceColorRowLayout {
        let labelWidth = min(78, max(58, floor(width * 0.27)))
        let wellWidth: CGFloat = 40
        return BoardManAppearanceColorRowLayout(
            labelFrame: integralRect(x: originX, y: originY + 6, width: labelWidth, height: 16),
            colorWellFrame: integralRect(x: originX + labelWidth + 8, y: originY, width: wellWidth, height: controlHeight),
            sliderFrame: integralRect(
                x: originX + labelWidth + wellWidth + 18,
                y: originY + 3,
                width: max(42, width - labelWidth - wellWidth - 18),
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
        BoardManAppearancePreviewScaleRowLayout(
            labelFrame: integralRect(x: originX, y: originY + 7, width: 104, height: 16),
            sliderFrame: integralRect(x: originX + 116, y: originY + 3, width: max(120, width - 192), height: 24),
            valueFrame: integralRect(x: originX + width - 64, y: originY, width: 64, height: controlHeight)
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
