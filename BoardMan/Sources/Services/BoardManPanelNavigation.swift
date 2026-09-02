//
//  BoardManPanelNavigation.swift
//  Board-Man
//
//  Pure horizontal navigation policy for History, Templates All, and template groups.
//

import Foundation

enum BoardManPanelNavigationTarget: Equatable {
    case history
    case snippets(categoryIdentifier: String)
}

struct BoardManPanelNavigationPolicy {
    static func target(
        activeTab: BoardManPanelTab,
        activeSnippetGroupIdentifiers: Set<String>,
        snippetCategoryIdentifiers: [String],
        delta: Int
    ) -> BoardManPanelNavigationTarget? {
        guard delta != 0, activeTab != .settings else { return nil }

        let currentIndex: Int
        switch activeTab {
        case .history:
            currentIndex = 0
        case .snippets:
            if activeSnippetGroupIdentifiers.isEmpty {
                currentIndex = 1
            } else if activeSnippetGroupIdentifiers.count == 1,
                      let identifier = activeSnippetGroupIdentifiers.first,
                      let categoryIndex = snippetCategoryIdentifiers.firstIndex(of: identifier) {
                currentIndex = categoryIndex + 1
            } else {
                currentIndex = 1
            }
        case .settings:
            return nil
        }

        let nextIndex = min(snippetCategoryIdentifiers.count, max(0, currentIndex + delta))
        guard nextIndex != currentIndex else { return nil }
        if nextIndex == 0 {
            return .history
        }
        return .snippets(categoryIdentifier: snippetCategoryIdentifiers[nextIndex - 1])
    }
}
