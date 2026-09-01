import AppKit

enum BoardManPanelLayoutMetrics {
    static let preferredWidth: CGFloat = 800
    static let minimumWidth: CGFloat = 640
    static let outerMargin: CGFloat = 18
    static let compactOuterMargin: CGFloat = 14
    static let controlHeight: CGFloat = 30
    static let actionButtonHeight: CGFloat = 30
    static let settingsLabelWidth: CGFloat = 84
    static let settingsColumnGap: CGFloat = 22
    static let horizontalGap: CGFloat = 10
    static let settingsInset: CGFloat = 26
    static let cardCornerRadius: CGFloat = 14
    static let sidebarSymbolLeadingInset: CGFloat = 8
    static let historyRowHeight: CGFloat = 62
    static let compactHistoryRowHeight: CGFloat = 46
}

struct BoardManPanelLayout: Equatable {
    let isCompact: Bool
    let margin: CGFloat
    let contentWidth: CGFloat
    let tabsFrame: NSRect
    let settingsButtonFrame: NSRect
    let searchFrame: NSRect
    let usesCompactSearchPlaceholder: Bool
    let showsSnippetButtons: Bool
    let snippetButtonFrames: [NSRect]
    let contentTop: CGFloat
    let showsHistoryToolbar: Bool
    let historyUsageFilterFrame: NSRect
    let historySortFrame: NSRect
    let historyConditionFrame: NSRect
    let historySavedFilterFrame: NSRect
    let settingsSidebarFrame: NSRect
    let settingsFrame: NSRect
    let settingsDocumentHeight: CGFloat
    let showsSnippetCategories: Bool
    let snippetCategoryLabelFrame: NSRect
    let snippetCategoryPopupFrame: NSRect
    let snippetCategoryButtonFrames: [NSRect]
    let snippetInteractionHintFrame: NSRect
    let snippetReorderFrame: NSRect
    let listFrame: NSRect
    let snippetEditorFrame: NSRect
}

enum BoardManPanelLayoutPolicy {
    static func panelLayout(
        bounds: NSRect,
        isQuickMode: Bool,
        activeTab: BoardManPanelTab,
        activeSettingsCategory: BoardManInlineSettingsCategory,
        appearanceAdvancedExpanded: Bool,
        searchIntrinsicHeight: CGFloat
    ) -> BoardManPanelLayout {
        let isCompact = bounds.width < 720
        let margin = isQuickMode
            ? 12
            : (isCompact ? BoardManPanelLayoutMetrics.compactOuterMargin : BoardManPanelLayoutMetrics.outerMargin)
        let width = bounds.width - (margin * 2)
        let headerY = isQuickMode ? bounds.height - 42 : bounds.height - 70
        let isSettings = activeTab == .settings && !isQuickMode
        let gearWidth: CGFloat = 36
        let gearGap: CGFloat = isCompact ? 8 : 12
        let tabsWidth: CGFloat = isCompact ? 190 : min(250, max(216, floor(width * 0.31)))
        let tabsFrame = NSIntegralRect(NSRect(x: margin, y: headerY, width: tabsWidth, height: 36))
        let settingsButtonFrame = NSIntegralRect(NSRect(
            x: margin + width - gearWidth,
            y: headerY,
            width: gearWidth,
            height: 36
        ))

        let showsSnippetButtons = activeTab == .snippets && !isSettings && !isQuickMode
        let snippetButtonGap: CGFloat = isCompact ? 6 : 8
        let snippetButtonWidths: [CGFloat] = isCompact ? [58, 64, 64] : [70, 72, 72]
        let snippetButtonsWidth = showsSnippetButtons
            ? snippetButtonWidths.reduce(0, +) + (snippetButtonGap * 2)
            : 0
        let headerGap: CGFloat = isCompact ? 10 : 14
        let rightX = margin + tabsWidth + headerGap
        let rightEdge = margin + width - gearWidth - gearGap
        let rightWidth = max(0, rightEdge - rightX)
        let searchWidth = max(
            78,
            rightWidth - snippetButtonsWidth - (showsSnippetButtons ? headerGap : 0)
        )
        let searchHeight = min(32, max(28, ceil(searchIntrinsicHeight)))
        let searchFrame = NSIntegralRect(NSRect(
            x: rightX,
            y: floor(tabsFrame.midY - (searchHeight / 2)),
            width: searchWidth,
            height: searchHeight
        ))
        var snippetButtonFrames: [NSRect] = []
        if showsSnippetButtons {
            let buttonY = headerY + 3
            var buttonX = rightX + searchWidth + headerGap
            for buttonWidth in snippetButtonWidths {
                snippetButtonFrames.append(NSRect(
                    x: buttonX,
                    y: buttonY,
                    width: buttonWidth,
                    height: BoardManPanelLayoutMetrics.actionButtonHeight
                ))
                buttonX += buttonWidth + snippetButtonGap
            }
        }

        let contentTop = isQuickMode ? bounds.height - 18 : headerY - 24
        let showsHistoryToolbar = activeTab == .history && !isSettings
        let historyToolbarHeight: CGFloat = 30
        let historyToolbarY = isQuickMode ? bounds.height - 52 : contentTop - 34
        let filterWidth: CGFloat = 118
        let historyUsageFilterFrame = NSIntegralRect(NSRect(
            x: margin,
            y: historyToolbarY,
            width: filterWidth,
            height: historyToolbarHeight
        ))
        let historySortFrame = NSIntegralRect(NSRect(
            x: margin + filterWidth + 10,
            y: historyToolbarY,
            width: 34,
            height: historyToolbarHeight
        ))
        let historyConditionFrame = NSIntegralRect(NSRect(
            x: margin + filterWidth + 54,
            y: historyToolbarY,
            width: 34,
            height: historyToolbarHeight
        ))
        let savedFilterX = margin + filterWidth + 100
        let historySavedFilterFrame = NSIntegralRect(NSRect(
            x: savedFilterX,
            y: historyToolbarY,
            width: max(140, min(isCompact ? 166 : 220, margin + width - savedFilterX)),
            height: historyToolbarHeight
        ))

        let sidebarWidth: CGFloat = min(184, max(160, floor(width * 0.25)))
        let settingsGap: CGFloat = 16
        let settingsContentX = margin + sidebarWidth + settingsGap
        let settingsContentWidth = max(260, width - sidebarWidth - settingsGap)
        let settingsViewportHeight = max(220, contentTop - 28)
        let settingsSidebarFrame = NSRect(
            x: margin,
            y: 28,
            width: sidebarWidth,
            height: settingsViewportHeight
        )
        let settingsFrame = NSIntegralRect(NSRect(
            x: settingsContentX,
            y: 28,
            width: settingsContentWidth,
            height: settingsViewportHeight
        ))
        let settingsDocumentHeight = settingsDocumentHeight(
            viewportHeight: settingsViewportHeight,
            contentWidth: settingsContentWidth,
            category: activeSettingsCategory,
            appearanceAdvancedExpanded: appearanceAdvancedExpanded
        )

        let showsSnippetCategories = activeTab == .snippets && !isSettings
        let categoryRowY = contentTop - 38
        let snippetInteractionRowY = categoryRowY - 40
        let listTop: CGFloat
        if showsSnippetCategories {
            listTop = snippetInteractionRowY - 12
        } else if showsHistoryToolbar {
            listTop = historyToolbarY - 16
        } else {
            listTop = contentTop
        }
        let listBottom: CGFloat = isQuickMode ? 12 : 24
        let listHeight = isQuickMode ? max(1, listTop - listBottom) : max(190, listTop - 28)

        let categoryButtonGap: CGFloat = isCompact ? 6 : 8
        let categoryButtonWidths: [CGFloat] = isCompact ? [82, 88, 82] : [94, 108, 98]
        let actionWidth = categoryButtonWidths.reduce(0, +) + (categoryButtonGap * 2)
        let popupWidth = max(120, width - 64 - 12 - actionWidth - 12)
        let snippetCategoryLabelFrame = NSRect(x: margin, y: categoryRowY + 6, width: 64, height: 17)
        let snippetCategoryPopupFrame = NSRect(
            x: margin + 76,
            y: categoryRowY,
            width: popupWidth,
            height: BoardManPanelLayoutMetrics.controlHeight
        )
        var categoryButtonFrames: [NSRect] = []
        var categoryButtonX = margin + 76 + popupWidth + 12
        for buttonWidth in categoryButtonWidths {
            categoryButtonFrames.append(NSRect(
                x: categoryButtonX,
                y: categoryRowY,
                width: buttonWidth,
                height: BoardManPanelLayoutMetrics.controlHeight
            ))
            categoryButtonX += buttonWidth + categoryButtonGap
        }
        let reorderWidth: CGFloat = 118
        let snippetInteractionHintFrame = NSRect(
            x: margin,
            y: snippetInteractionRowY + 6,
            width: max(120, width - reorderWidth - 14),
            height: 17
        )
        let snippetReorderFrame = NSRect(
            x: margin + width - reorderWidth,
            y: snippetInteractionRowY,
            width: reorderWidth,
            height: BoardManPanelLayoutMetrics.controlHeight
        )

        let editorGap: CGFloat = showsSnippetCategories ? 8 : 0
        let editorWidth = showsSnippetCategories ? min(360, max(300, floor(width * 0.42))) : 0
        let listWidth = max(180, width - editorWidth - editorGap)
        let listFrame = NSRect(
            x: margin,
            y: listBottom,
            width: listWidth,
            height: listHeight
        )
        let snippetEditorFrame = NSRect(
            x: margin + listWidth + editorGap,
            y: 24,
            width: editorWidth,
            height: listHeight
        )

        return BoardManPanelLayout(
            isCompact: isCompact,
            margin: margin,
            contentWidth: width,
            tabsFrame: tabsFrame,
            settingsButtonFrame: settingsButtonFrame,
            searchFrame: searchFrame,
            usesCompactSearchPlaceholder: searchWidth < 230,
            showsSnippetButtons: showsSnippetButtons,
            snippetButtonFrames: snippetButtonFrames,
            contentTop: contentTop,
            showsHistoryToolbar: showsHistoryToolbar,
            historyUsageFilterFrame: historyUsageFilterFrame,
            historySortFrame: historySortFrame,
            historyConditionFrame: historyConditionFrame,
            historySavedFilterFrame: historySavedFilterFrame,
            settingsSidebarFrame: settingsSidebarFrame,
            settingsFrame: settingsFrame,
            settingsDocumentHeight: settingsDocumentHeight,
            showsSnippetCategories: showsSnippetCategories,
            snippetCategoryLabelFrame: snippetCategoryLabelFrame,
            snippetCategoryPopupFrame: snippetCategoryPopupFrame,
            snippetCategoryButtonFrames: categoryButtonFrames,
            snippetInteractionHintFrame: snippetInteractionHintFrame,
            snippetReorderFrame: snippetReorderFrame,
            listFrame: listFrame,
            snippetEditorFrame: snippetEditorFrame
        )
    }

    static func settingsDocumentHeight(
        viewportHeight: CGFloat,
        contentWidth: CGFloat,
        category: BoardManInlineSettingsCategory,
        appearanceAdvancedExpanded: Bool
    ) -> CGFloat {
        let appearanceContentWidth = max(
            240,
            contentWidth - (BoardManPanelLayoutMetrics.settingsInset * 2)
        )
        let stacksAppearanceCards = usesStackedAppearanceSettingsLayout(width: appearanceContentWidth)
        let requiredHeight: CGFloat
        switch category {
        case .general:
            requiredHeight = 790
        case .view:
            if stacksAppearanceCards {
                requiredHeight = appearanceAdvancedExpanded ? 1_720 : 1_360
            } else {
                requiredHeight = appearanceAdvancedExpanded ? 1_280 : 1_020
            }
        case .history:
            requiredHeight = 730
        case .snippets:
            requiredHeight = 640
        case .privacy:
            requiredHeight = 840
        case .updates:
            requiredHeight = 390
        case .license:
            requiredHeight = 650
        }
        return max(viewportHeight, requiredHeight)
    }

    static func settingsSidebarButtonFrames(
        width: CGFloat,
        height: CGFloat,
        count: Int
    ) -> [NSRect] {
        let inset: CGFloat = 12
        let buttonHeight: CGFloat = 42
        let gap: CGFloat = 6
        var currentY = height - inset - buttonHeight
        return (0..<max(0, count)).map { _ in
            defer { currentY -= buttonHeight + gap }
            return NSRect(
                x: inset,
                y: currentY,
                width: max(80, width - (inset * 2)),
                height: buttonHeight
            )
        }
    }

    static func updatesPreferenceFrame(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        preferredWidth: CGFloat
    ) -> NSRect {
        let updatesWidth = min(width, preferredWidth)
        return NSRect(
            x: originX + floor((width - updatesWidth) / 2),
            y: originY - 174,
            width: updatesWidth,
            height: 174
        )
    }

    static func usesStackedHistorySettingsLayout(width: CGFloat) -> Bool {
        width < 520
    }

    static func usesStackedAppearanceSettingsLayout(width: CGFloat) -> Bool {
        width < 470
    }
}
