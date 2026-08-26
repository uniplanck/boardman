import AppKit

struct BoardManSnippetShortcutRowLayout: Equatable {
    let titleFrame: NSRect
    let detailFrame: NSRect
    let recordFrame: NSRect
    let clearFrame: NSRect
}

struct BoardManSnippetSettingsLayout: Equatable {
    let sectionHeaderFrame: NSRect
    let summaryFrame: NSRect
    let foldersFrame: NSRect
    let proNoteFrame: NSRect
    let groupOrderFrame: NSRect
    let moveUpFrame: NSRect
    let moveDownFrame: NSRect
    let shortcutsLabelFrame: NSRect
    let shortcutScrollFrame: NSRect
    let shortcutDocumentFrame: NSRect
    let shortcutRows: [BoardManSnippetShortcutRowLayout]
    let manageButtonFrame: NSRect
}

enum BoardManSnippetSettingsLayoutPolicy {
    static func layout(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        requestedScrollHeight: CGFloat,
        shortcutCount: Int,
        controlHeight: CGFloat = BoardManPanelLayoutMetrics.controlHeight,
        actionButtonHeight: CGFloat = BoardManPanelLayoutMetrics.actionButtonHeight
    ) -> BoardManSnippetSettingsLayout {
        let count = max(0, shortcutCount)
        let shortcutRowHeight: CGFloat = 42
        let minimumBottomInset: CGFloat = 28
        let contentHeight = max(80, CGFloat(max(1, count)) * shortcutRowHeight + 8)
        let availableHeight = max(80, originY - 286 - minimumBottomInset)
        let safeScrollHeight = max(
            80,
            min(requestedScrollHeight, min(280, min(contentHeight, availableHeight)))
        )

        let moveButtonWidth: CGFloat = 92
        let moveGap: CGFloat = 8
        let orderPopupWidth = max(120, width - (moveButtonWidth * 2) - (moveGap * 2))
        let scrollFrame = NSRect(
            x: originX,
            y: originY - 196 - safeScrollHeight,
            width: width,
            height: safeScrollHeight
        )
        let documentHeight = max(CGFloat(count) * shortcutRowHeight, safeScrollHeight)
        let documentFrame = NSRect(x: 0, y: 0, width: width, height: documentHeight)

        let clearWidth: CGFloat = 52
        let recordWidth = min(150, max(112, width * 0.32))
        let textWidth = max(80, width - recordWidth - clearWidth - 20)
        let rows = (0..<count).map { index in
            let rowOriginY = documentHeight - CGFloat(index + 1) * shortcutRowHeight
            return BoardManSnippetShortcutRowLayout(
                titleFrame: NSRect(x: 0, y: rowOriginY + 22, width: textWidth, height: 15),
                detailFrame: NSRect(x: 0, y: rowOriginY + 6, width: textWidth, height: 14),
                recordFrame: NSRect(
                    x: textWidth + 8,
                    y: rowOriginY + 7,
                    width: recordWidth,
                    height: 28
                ),
                clearFrame: NSRect(
                    x: textWidth + recordWidth + 16,
                    y: rowOriginY + 7,
                    width: clearWidth,
                    height: 28
                )
            )
        }

        let manageButtonY = scrollFrame.minY - actionButtonHeight - 14
        return BoardManSnippetSettingsLayout(
            sectionHeaderFrame: NSRect(x: originX, y: originY, width: width, height: 18),
            summaryFrame: NSRect(x: originX, y: originY - 42, width: width, height: 20),
            foldersFrame: NSRect(x: originX, y: originY - 74, width: width, height: 20),
            proNoteFrame: NSRect(x: originX, y: originY - 106, width: width, height: 30),
            groupOrderFrame: NSRect(
                x: originX,
                y: originY - 146,
                width: orderPopupWidth,
                height: controlHeight
            ),
            moveUpFrame: NSRect(
                x: originX + orderPopupWidth + moveGap,
                y: originY - 146,
                width: moveButtonWidth,
                height: controlHeight
            ),
            moveDownFrame: NSRect(
                x: originX + orderPopupWidth + moveGap + moveButtonWidth + moveGap,
                y: originY - 146,
                width: moveButtonWidth,
                height: controlHeight
            ),
            shortcutsLabelFrame: NSRect(x: originX, y: originY - 184, width: width, height: 20),
            shortcutScrollFrame: scrollFrame,
            shortcutDocumentFrame: documentFrame,
            shortcutRows: rows,
            manageButtonFrame: NSRect(
                x: originX,
                y: manageButtonY,
                width: min(156, width),
                height: actionButtonHeight
            )
        )
    }
}
