import AppKit

struct BoardManGeneralSettingsLayout: Equatable {
    let sectionHeaderFrame: NSRect
    let launchOnLoginFrame: NSRect
    let inputPasteCommandFrame: NSRect
    let languageLabelFrame: NSRect
    let languageControlFrame: NSRect
    let maxHistoryLabelFrame: NSRect
    let maxHistoryDecreaseFrame: NSRect
    let maxHistoryValueFrame: NSRect
    let maxHistoryIncreaseFrame: NSRect
    let statusItemLabelFrame: NSRect
    let statusItemControlFrame: NSRect
}

struct BoardManShortcutRowLayout: Equatable {
    let titleFrame: NSRect
    let detailFrame: NSRect
    let recordFrame: NSRect
    let clearFrame: NSRect
}

struct BoardManShortcutSectionLayout: Equatable {
    let sectionHeaderFrame: NSRect
    let rows: [BoardManShortcutRowLayout]
    let statusFrame: NSRect
}

enum BoardManGeneralSettingsLayoutPolicy {
    static func generalSection(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        rowHeight: CGFloat = BoardManPanelLayoutMetrics.controlHeight,
        labelWidth: CGFloat = BoardManPanelLayoutMetrics.settingsLabelWidth
    ) -> BoardManGeneralSettingsLayout {
        let language = labeledRow(
            originX: originX,
            originY: originY - 112,
            width: width,
            rowHeight: rowHeight,
            labelWidth: labelWidth
        )
        let visibleHistoryX = originX + labelWidth + 12
        let status = labeledRow(
            originX: originX,
            originY: originY - 204,
            width: width,
            rowHeight: rowHeight,
            labelWidth: labelWidth
        )
        return BoardManGeneralSettingsLayout(
            sectionHeaderFrame: NSRect(x: originX, y: originY, width: width, height: 18),
            launchOnLoginFrame: NSRect(x: originX, y: originY - 38, width: width, height: 20),
            inputPasteCommandFrame: NSRect(x: originX, y: originY - 70, width: width, height: 20),
            languageLabelFrame: language.label,
            languageControlFrame: language.control,
            maxHistoryLabelFrame: NSRect(
                x: originX,
                y: originY - 157,
                width: labelWidth,
                height: 16
            ),
            maxHistoryDecreaseFrame: NSRect(
                x: visibleHistoryX,
                y: originY - 164,
                width: 30,
                height: rowHeight
            ),
            maxHistoryValueFrame: NSRect(
                x: visibleHistoryX + 36,
                y: originY - 164,
                width: 82,
                height: rowHeight
            ),
            maxHistoryIncreaseFrame: NSRect(
                x: visibleHistoryX + 124,
                y: originY - 164,
                width: 30,
                height: rowHeight
            ),
            statusItemLabelFrame: status.label,
            statusItemControlFrame: status.control
        )
    }

    static func shortcutSection(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        rowCount: Int
    ) -> BoardManShortcutSectionLayout {
        let shortcutRowHeight: CGFloat = 50
        let clearWidth: CGFloat = 60
        let recordWidth: CGFloat = min(176, max(128, floor(width * 0.34)))
        let textWidth = max(110, width - recordWidth - clearWidth - 24)
        let rows = (0..<max(0, rowCount)).map { index in
            let rowY = originY - 34 - CGFloat(index) * shortcutRowHeight
            return BoardManShortcutRowLayout(
                titleFrame: NSRect(x: originX, y: rowY + 20, width: textWidth, height: 16),
                detailFrame: NSRect(x: originX, y: rowY + 4, width: textWidth, height: 14),
                recordFrame: NSRect(
                    x: originX + textWidth + 8,
                    y: rowY + 6,
                    width: recordWidth,
                    height: 30
                ),
                clearFrame: NSRect(
                    x: originX + textWidth + recordWidth + 16,
                    y: rowY + 6,
                    width: clearWidth,
                    height: 30
                )
            )
        }
        return BoardManShortcutSectionLayout(
            sectionHeaderFrame: NSRect(x: originX, y: originY, width: width, height: 18),
            rows: rows,
            statusFrame: NSRect(
                x: originX,
                y: originY - 34 - CGFloat(max(0, rowCount)) * shortcutRowHeight - 2,
                width: width,
                height: 16
            )
        )
    }

    private static func labeledRow(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        rowHeight: CGFloat,
        labelWidth: CGFloat
    ) -> (label: NSRect, control: NSRect) {
        let controlWidth = max(118, width - labelWidth - 12)
        return (
            NSIntegralRect(NSRect(
                x: originX,
                y: originY + 7,
                width: labelWidth,
                height: 16
            )),
            NSIntegralRect(NSRect(
                x: originX + labelWidth + 12,
                y: originY,
                width: controlWidth,
                height: rowHeight
            ))
        )
    }
}
