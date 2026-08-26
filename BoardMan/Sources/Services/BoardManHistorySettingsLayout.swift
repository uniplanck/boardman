import AppKit

struct BoardManHistorySettingsLayoutInput: Equatable {
    let originX: CGFloat
    let originY: CGFloat
    let width: CGFloat
    let controlHeight: CGFloat
    let actionButtonHeight: CGFloat

    init(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        controlHeight: CGFloat = BoardManPanelLayoutMetrics.controlHeight,
        actionButtonHeight: CGFloat = BoardManPanelLayoutMetrics.actionButtonHeight
    ) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.controlHeight = controlHeight
        self.actionButtonHeight = actionButtonHeight
    }
}

struct BoardManHistorySettingsLayout: Equatable {
    let sectionHeaderFrame: NSRect
    let dedupeFrame: NSRect
    let reuseTopFrame: NSRect
    let overwriteSameHistoryFrame: NSRect
    let skipPinnedNavigationFrame: NSRect
    let longPressLabelFrame: NSRect
    let longPressPopupFrame: NSRect
    let timestampInteractionLabelFrame: NSRect
    let timestampInteractionPopupFrame: NSRect
    let timestampShortcutEnabledFrame: NSRect
    let timestampShortcutLabelFrame: NSRect
    let timestampShortcutRecordFrame: NSRect
    let timestampShortcutDelayLabelFrame: NSRect
    let timestampShortcutDelayDecreaseFrame: NSRect
    let timestampShortcutDelayFieldFrame: NSRect
    let timestampShortcutDelayIncreaseFrame: NSRect
    let timestampShortcutSecondsFrame: NSRect
    let timedPinDurationLabelFrame: NSRect
    let timedPinPresetFrame: NSRect
    let timedPinPresetAddFrame: NSRect
    let timedPinPresetRemoveFrame: NSRect
    let timedPinDurationDecreaseFrame: NSRect
    let timedPinDurationValueFrame: NSRect
    let timedPinDurationIncreaseFrame: NSRect
    let timedPinDurationUnitFrame: NSRect
    let exportHistoryFrame: NSRect
    let clearHistoryFrame: NSRect
    let usesStackedShortcutLayout: Bool
}

enum BoardManHistorySettingsLayoutPolicy {
    private struct ShortcutFrames {
        let label: NSRect
        let record: NSRect
        let delayLabel: NSRect
        let delayDecrease: NSRect
        let delayField: NSRect
        let delayIncrease: NSRect
        let seconds: NSRect
        let pinLabelY: CGFloat
        let isStacked: Bool
    }

    private struct PinFrames {
        let label: NSRect
        let preset: NSRect
        let presetAdd: NSRect
        let presetRemove: NSRect
        let durationDecrease: NSRect
        let durationValue: NSRect
        let durationIncrease: NSRect
        let durationUnit: NSRect
        let exportHistory: NSRect
        let clearHistory: NSRect
    }

    static func layout(_ input: BoardManHistorySettingsLayoutInput) -> BoardManHistorySettingsLayout {
        let compactLabelWidth = min(104, max(78, floor(input.width * 0.24)))
        let longPress = labeledRow(
            originX: input.originX,
            originY: input.originY - 198,
            width: input.width,
            labelWidth: compactLabelWidth,
            controlHeight: input.controlHeight
        )
        let timestampInteraction = labeledRow(
            originX: input.originX,
            originY: input.originY - 240,
            width: input.width,
            labelWidth: compactLabelWidth,
            controlHeight: input.controlHeight
        )
        let shortcut = shortcutFrames(input: input, compactLabelWidth: compactLabelWidth)
        let pin = pinFrames(input: input, pinLabelY: shortcut.pinLabelY)

        return BoardManHistorySettingsLayout(
            sectionHeaderFrame: NSRect(x: input.originX, y: input.originY, width: input.width, height: 18),
            dedupeFrame: NSRect(x: input.originX, y: input.originY - 42, width: input.width, height: 20),
            reuseTopFrame: NSRect(x: input.originX, y: input.originY - 78, width: input.width, height: 20),
            overwriteSameHistoryFrame: NSRect(x: input.originX, y: input.originY - 114, width: input.width, height: 20),
            skipPinnedNavigationFrame: NSRect(x: input.originX, y: input.originY - 150, width: input.width, height: 20),
            longPressLabelFrame: longPress.label,
            longPressPopupFrame: longPress.control,
            timestampInteractionLabelFrame: timestampInteraction.label,
            timestampInteractionPopupFrame: timestampInteraction.control,
            timestampShortcutEnabledFrame: NSRect(x: input.originX, y: input.originY - 282, width: input.width, height: 20),
            timestampShortcutLabelFrame: shortcut.label,
            timestampShortcutRecordFrame: shortcut.record,
            timestampShortcutDelayLabelFrame: shortcut.delayLabel,
            timestampShortcutDelayDecreaseFrame: shortcut.delayDecrease,
            timestampShortcutDelayFieldFrame: shortcut.delayField,
            timestampShortcutDelayIncreaseFrame: shortcut.delayIncrease,
            timestampShortcutSecondsFrame: shortcut.seconds,
            timedPinDurationLabelFrame: pin.label,
            timedPinPresetFrame: pin.preset,
            timedPinPresetAddFrame: pin.presetAdd,
            timedPinPresetRemoveFrame: pin.presetRemove,
            timedPinDurationDecreaseFrame: pin.durationDecrease,
            timedPinDurationValueFrame: pin.durationValue,
            timedPinDurationIncreaseFrame: pin.durationIncrease,
            timedPinDurationUnitFrame: pin.durationUnit,
            exportHistoryFrame: pin.exportHistory,
            clearHistoryFrame: pin.clearHistory,
            usesStackedShortcutLayout: shortcut.isStacked
        )
    }

    private static func shortcutFrames(
        input: BoardManHistorySettingsLayoutInput,
        compactLabelWidth: CGFloat
    ) -> ShortcutFrames {
        let isStacked = BoardManPanelLayoutPolicy.usesStackedHistorySettingsLayout(width: input.width)
        let shortcutLabel: NSRect
        let shortcutRecord: NSRect
        let delayRowY: CGFloat
        let pinLabelY: CGFloat

        if isStacked {
            shortcutLabel = NSRect(x: input.originX, y: input.originY - 302, width: input.width, height: 16).integral
            shortcutRecord = NSRect(
                x: input.originX,
                y: input.originY - 336,
                width: input.width,
                height: input.controlHeight
            ).integral
            delayRowY = input.originY - 370
            pinLabelY = input.originY - 392
        } else {
            shortcutLabel = NSRect(
                x: input.originX,
                y: input.originY - 324,
                width: compactLabelWidth,
                height: 16
            ).integral
            shortcutRecord = NSRect(
                x: input.originX + compactLabelWidth + 12,
                y: input.originY - 331,
                width: max(128, input.width - compactLabelWidth - 12),
                height: input.controlHeight
            ).integral
            delayRowY = input.originY - 373
            pinLabelY = input.originY - 396
        }

        let delayLabelWidth: CGFloat = isStacked ? 48 : compactLabelWidth
        let delayX = input.originX + delayLabelWidth + 12
        let adjustmentWidth: CGFloat = 30
        let delayFieldWidth = min(82, max(58, floor(input.width * 0.18)))

        return ShortcutFrames(
            label: shortcutLabel,
            record: shortcutRecord,
            delayLabel: NSRect(x: input.originX, y: delayRowY + 7, width: delayLabelWidth, height: 16).integral,
            delayDecrease: NSRect(x: delayX, y: delayRowY, width: adjustmentWidth, height: input.controlHeight).integral,
            delayField: NSRect(
                x: delayX + adjustmentWidth + 6,
                y: delayRowY,
                width: delayFieldWidth,
                height: input.controlHeight
            ).integral,
            delayIncrease: NSRect(
                x: delayX + adjustmentWidth + delayFieldWidth + 12,
                y: delayRowY,
                width: adjustmentWidth,
                height: input.controlHeight
            ).integral,
            seconds: NSRect(
                x: delayX + (adjustmentWidth * 2) + delayFieldWidth + 24,
                y: delayRowY + 7,
                width: 44,
                height: 16
            ).integral,
            pinLabelY: pinLabelY,
            isStacked: isStacked
        )
    }

    private static func pinFrames(
        input: BoardManHistorySettingsLayoutInput,
        pinLabelY: CGFloat
    ) -> PinFrames {
        let presetRowY = pinLabelY - 34
        let presetButtonWidth: CGFloat = 34
        let presetGap: CGFloat = 6
        let presetWidth = max(112, input.width - (presetButtonWidth * 2) - (presetGap * 2))
        let durationRowY = presetRowY - 36
        let durationValueWidth = min(96, max(72, floor(input.width * 0.22)))
        let unitX = input.originX + durationValueWidth + 84
        let actionY = durationRowY - 50
        let exportWidth = min(176, max(132, floor(input.width * 0.42)))

        return PinFrames(
            label: NSRect(x: input.originX, y: pinLabelY, width: input.width, height: 16).integral,
            preset: NSRect(x: input.originX, y: presetRowY, width: presetWidth, height: input.controlHeight).integral,
            presetAdd: NSRect(
                x: input.originX + presetWidth + presetGap,
                y: presetRowY,
                width: presetButtonWidth,
                height: input.controlHeight
            ).integral,
            presetRemove: NSRect(
                x: input.originX + presetWidth + presetGap + presetButtonWidth + presetGap,
                y: presetRowY,
                width: presetButtonWidth,
                height: input.controlHeight
            ).integral,
            durationDecrease: NSRect(x: input.originX, y: durationRowY, width: 30, height: input.controlHeight).integral,
            durationValue: NSRect(
                x: input.originX + 36,
                y: durationRowY,
                width: durationValueWidth,
                height: input.controlHeight
            ).integral,
            durationIncrease: NSRect(
                x: input.originX + durationValueWidth + 42,
                y: durationRowY,
                width: 30,
                height: input.controlHeight
            ).integral,
            durationUnit: NSRect(
                x: unitX,
                y: durationRowY,
                width: max(92, input.width - (unitX - input.originX)),
                height: input.controlHeight
            ).integral,
            exportHistory: NSRect(
                x: input.originX,
                y: actionY,
                width: exportWidth,
                height: input.actionButtonHeight
            ),
            clearHistory: NSRect(
                x: input.originX + exportWidth + 10,
                y: actionY,
                width: min(104, max(84, input.width - exportWidth - 10)),
                height: input.actionButtonHeight
            )
        )
    }

    private static func labeledRow(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        labelWidth: CGFloat,
        controlHeight: CGFloat
    ) -> (label: NSRect, control: NSRect) {
        let label = NSRect(x: originX, y: originY + 7, width: labelWidth, height: 16).integral
        let control = NSRect(
            x: originX + labelWidth + 12,
            y: originY,
            width: max(118, width - labelWidth - 12),
            height: controlHeight
        ).integral
        return (label, control)
    }
}
