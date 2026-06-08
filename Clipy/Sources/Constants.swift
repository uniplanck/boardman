//
//  Constants.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/04/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

struct Constants {

    struct Application {
        #if DEBUG
            static let name = "Board-Man DEBUG"
        #else
            static let name = "Board-Man"
        #endif

        static let appcastURL = URL(string: "https://github.com/uniplanck/boardman/releases/latest/download/appcast.xml")!
    }

    struct Menu {
        static let clip = "ClipMenu"
        static let history = "HistoryMenu"
        static let snippet = "SnippetsMenu"
    }

    struct Common {
        static let index = "index"
        static let title = "title"
        static let snippets = "snippets"
        static let content = "content"
        static let selector = "selector"
        static let draggedDataType = "public.data"
    }

    struct UserDefaults {
        static let hotKeys = "kCPYPrefHotKeysKey"
        static let menuIconSize = "kCPYPrefMenuIconSizeKey"
        static let maxHistorySize = "kCPYPrefMaxHistorySizeKey"
        static let storeTypes = "kCPYPrefStoreTypesKey"
        static let inputPasteCommand = "kCPYPrefInputPasteCommandKey"
        static let showIconInTheMenu = "kCPYPrefShowIconInTheMenuKey"
        static let numberOfItemsPlaceInline = "kCPYPrefNumberOfItemsPlaceInlineKey"
        static let numberOfItemsPlaceInsideFolder = "kCPYPrefNumberOfItemsPlaceInsideFolderKey"
        static let maxMenuItemTitleLength = "kCPYPrefMaxMenuItemTitleLengthKey"
        static let menuItemsTitleStartWithZero = "kCPYPrefMenuItemsTitleStartWithZeroKey"
        static let reorderClipsAfterPasting = "kCPYPrefReorderClipsAfterPasting"
        static let addClearHistoryMenuItem = "kCPYPrefAddClearHistoryMenuItemKey"
        static let showAlertBeforeClearHistory = "kCPYPrefShowAlertBeforeClearHistoryKey"
        static let menuItemsAreMarkedWithNumbers = "menuItemsAreMarkedWithNumbers"
        static let showToolTipOnMenuItem = "showToolTipOnMenuItem"
        static let showImageInTheMenu = "showImageInTheMenu"
        static let addNumericKeyEquivalents = "addNumericKeyEquivalents"
        static let maxLengthOfToolTip = "maxLengthOfToolTipKey"
        static let loginItem = "loginItem"
        static let suppressAlertForLoginItem = "suppressAlertForLoginItem"
        static let showStatusItem = "kCPYPrefShowStatusItemKey"
        static let thumbnailWidth = "thumbnailWidth"
        static let thumbnailHeight = "thumbnailHeight"
        static let overwriteSameHistory = "kCPYPrefOverwriteSameHistroy"
        static let copySameHistory = "kCPYPrefCopySameHistroy"
        static let suppressAlertForDeleteSnippet = "kCPYSuppressAlertForDeleteSnippet"
        static let excludeApplications = "kCPYExcludeApplications"
        static let collectCrashReport = "kCPYCollectCrashReport"
        static let showColorPreviewInTheMenu = "kCPYPrefShowColorPreviewInTheMenu"
        static let pasteCounts = "kCPYPasteCounts"
        static let boardManUsePanelUI = "BoardManUsePanelUI"
        static let boardManShowRowNumbers = "BoardManShowRowNumbers"
        static let boardManTimestampFormat = "BoardManTimestampFormat"
        static let boardManPanelHeight = "BoardManPanelHeight"
        static let boardManShowUsageCount = "BoardManShowUsageCount"
        static let boardManUsageCountStyle = "BoardManUsageCountStyle"
        static let boardManUsedItemStyle = "BoardManUsedItemStyle"
        static let boardManLiquidGlass = "BoardManLiquidGlass"
        static let boardManHideRulesJSON = "BoardManHideRulesJSON"
        static let boardManThemePreset = "BoardManThemePreset"
        static let boardManThemeLighten = "BoardManThemeLighten"
    }

    struct Beta {
        static let pastePlainText = "kCPYBetaPastePlainText"
        static let pastePlainTextModifier = "kCPYBetaPastePlainTextModifier"
        static let deleteHistory = "kCPYBetaDeleteHistory"
        static let deleteHistoryModifier = "kCPYBetaDeleteHistoryModifier"
        static let pasteAndDeleteHistory = "kCPYBetaPasteAndDeleteHistory"
        static let pasteAndDeleteHistoryModifier = "kCPYBetapasteAndDeleteHistoryModifier"
        static let observerScreenshot = "kCPYBetaObserveScreenshot"
    }

    struct Update {
        static let enableAutomaticCheck = "kCPYEnableAutomaticCheckKey"
        static let checkInterval = "kCPYUpdateCheckIntervalKey"
    }

    struct Notification {
        static let closeSnippetEditor = "kCPYSnippetEditorWillCloseNotification"
        static let pasteCountDidChange = "kCPYPasteCountDidChangeNotification"
    }

    struct Xml {
        static let fileType = "xml"
        static let type = "type"
        static let rootElement = "folders"
        static let folderElement = "folder"
        static let snippetElement = "snippet"
        static let titleElement = "title"
        static let snippetsElement = "snippets"
        static let contentElement = "content"
    }

    struct HotKey {
        static let mainKeyCombo = "kCPYHotKeyMainKeyCombo"
        static let historyKeyCombo = "kCPYHotKeyHistoryKeyCombo"
        static let snippetKeyCombo = "kCPYHotKeySnippetKeyCombo"
        static let migrateNewKeyCombo = "kCPYMigrateNewKeyCombo"
        static let folderKeyCombos = "kCPYFolderKeyCombos"
        static let clearHistoryKeyCombo = "kCPYClearHistoryKeyCombo"
    }

}
