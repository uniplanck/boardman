//
//  BoardManPanelItem.swift
//  Board-Man
//
//  Presentation models shared by the Board-Man panel, search coordination, and tests.
//

import AppKit

enum BoardManPanelTab: Int, CaseIterable {
    case history = 0
    case snippets
    case settings

    var title: String { title(compact: false) }

    func title(compact: Bool) -> String {
        switch self {
        case .history:
            return boardManText("History")
        case .snippets:
            guard compact else { return boardManText("Snippets") }
            let language = BoardManLanguage.allowed(
                AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
            ).resolved
            switch language {
            case .japanese: return "定型"
            case .simplifiedChinese: return "模板"
            case .korean: return "문구"
            case .system, .english: return "Text"
            }
        case .settings:
            return boardManText("Settings")
        }
    }

    var emptyMessage: String {
        switch self {
        case .history: return boardManText("No clipboard history yet")
        case .snippets: return boardManText("No snippets yet")
        case .settings: return ""
        }
    }
}

enum BoardManPanelItemSource {
    case clip
    case snippet
    case favorite
}

struct BoardManHistoryItem {
    let title: String
    let primaryTitle: String
    let compactTitle: String
    let metadataText: String
    let timestampText: String
    let countText: String
    let previewTitle: String
    let dataHash: String
    let imageDataPath: String
    let inlineThumbnail: NSImage?
    let pasteCount: Int
    let isPinned: Bool
    let isMasked: Bool
    let isEnabled: Bool
    let source: BoardManPanelItemSource
    let categoryIdentifier: String?
    let categoryTitle: String?
}
