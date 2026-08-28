import Foundation

struct BoardManSnippetCreationResult {
    let snippet: BoardManSnippet
    let folder: BoardManFolder
}

enum BoardManSnippetCatalogService {
    static func normalizedSnippetTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? boardManText("Untitled snippet") : trimmedTitle
    }

    static func normalizedCategoryTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    static func createFolderIfAllowed(
        title: String,
        store: BoardManStore,
        entitlementService: EntitlementService = .shared
    ) -> BoardManFolder? {
        let currentCount = store.foldersSortedByIndex().count
        guard EntitlementGate.canCreateSnippetFolder(
            currentFolderCount: currentCount,
            service: entitlementService
        ) else {
            return nil
        }
        return createFolder(title: title, store: store)
    }

    @discardableResult
    static func createFolder(title: String, store: BoardManStore) -> BoardManFolder {
        let folder = BoardManFolder()
        folder.title = title
        folder.enable = true
        folder.index = (store.foldersSortedByIndex().last?.index ?? -1) + 1
        store.upsertFolder(folder)
        return folder
    }

    static func renameFolder(_ folder: BoardManFolder, title: String, store: BoardManStore) {
        folder.title = title
        store.upsertFolder(folder)
    }

    static func deleteFolder(
        identifier: String,
        store: BoardManStore
    ) -> BoardManFolder? {
        guard let savedFolder = store.folder(identifier: identifier) else { return nil }
        let fallbackFolder = uncategorizedFolder(
            excluding: savedFolder.identifier,
            store: store
        )
        var destinationIndex = fallbackFolder.snippets.count
        for snippet in savedFolder.snippets {
            store.moveSnippet(
                identifier: snippet.identifier,
                toFolderIdentifier: fallbackFolder.identifier,
                index: destinationIndex
            )
            destinationIndex += 1
        }
        store.deleteFolder(identifier: savedFolder.identifier)
        return fallbackFolder
    }

    static func createSnippetIfAllowed(
        preferredFolderIdentifier: String,
        allCategoriesIdentifier: String,
        uncategorizedIdentifier: String,
        store: BoardManStore,
        entitlementService: EntitlementService = .shared
    ) -> BoardManSnippetCreationResult? {
        let currentCount = store.snippetsSortedByIndex().count
        guard EntitlementGate.canCreateSnippet(
            currentSnippetCount: currentCount,
            service: entitlementService
        ) else {
            return nil
        }
        return createSnippet(
            preferredFolderIdentifier: preferredFolderIdentifier,
            allCategoriesIdentifier: allCategoriesIdentifier,
            uncategorizedIdentifier: uncategorizedIdentifier,
            store: store
        )
    }

    static func createSnippet(
        preferredFolderIdentifier: String,
        allCategoriesIdentifier: String,
        uncategorizedIdentifier: String,
        store: BoardManStore
    ) -> BoardManSnippetCreationResult {
        let folder = targetFolder(
            preferredIdentifier: preferredFolderIdentifier,
            allCategoriesIdentifier: allCategoriesIdentifier,
            uncategorizedIdentifier: uncategorizedIdentifier,
            store: store
        )
        let snippet = BoardManSnippet()
        snippet.title = boardManText("Untitled snippet")
        snippet.content = ""
        snippet.enable = true
        snippet.index = folder.snippets.count
        store.upsertSnippet(snippet, folderIdentifier: folder.identifier)
        return BoardManSnippetCreationResult(snippet: snippet, folder: folder)
    }

    @discardableResult
    static func deleteSnippet(identifier: String, store: BoardManStore) -> Bool {
        guard let snippet = store.snippet(identifier: identifier) else { return false }
        let folderIdentifier = store.folderIdentifier(forSnippetIdentifier: snippet.identifier)
        store.deleteSnippet(identifier: snippet.identifier)
        if let folderIdentifier,
           let folder = store.folder(identifier: folderIdentifier) {
            store.reorderSnippets(
                Array(folder.snippets).map(\.identifier),
                folderIdentifier: folderIdentifier
            )
        }
        return true
    }

    static func targetFolder(
        preferredIdentifier: String,
        allCategoriesIdentifier: String,
        uncategorizedIdentifier: String,
        store: BoardManStore
    ) -> BoardManFolder {
        if preferredIdentifier == uncategorizedIdentifier {
            return uncategorizedFolder(store: store)
        }
        if preferredIdentifier != allCategoriesIdentifier,
           let folder = store.folder(identifier: preferredIdentifier) {
            return folder
        }
        return defaultFolder(store: store)
    }

    static func defaultFolder(store: BoardManStore) -> BoardManFolder {
        let folders = store.foldersSortedByIndex()
        if let enabledFolder = folders.first(where: { $0.enable }) {
            return enabledFolder
        }
        if let firstFolder = folders.first {
            return firstFolder
        }
        return createFolder(title: "Board-Man Snippets", store: store)
    }

    static func uncategorizedFolder(
        excluding excludedIdentifier: String? = nil,
        store: BoardManStore
    ) -> BoardManFolder {
        let folders = store.foldersSortedByIndex()
        if let folder = folders.first(where: {
            $0.identifier != excludedIdentifier && $0.title == "Uncategorized"
        }) {
            return folder
        }
        return createFolder(title: "Uncategorized", store: store)
    }

    static func moveSnippet(
        _ snippet: BoardManSnippet,
        toCategoryIdentifier categoryIdentifier: String,
        allCategoriesIdentifier: String,
        uncategorizedIdentifier: String,
        store: BoardManStore
    ) {
        let targetFolder = targetFolder(
            preferredIdentifier: categoryIdentifier,
            allCategoriesIdentifier: allCategoriesIdentifier,
            uncategorizedIdentifier: uncategorizedIdentifier,
            store: store
        )
        let currentFolderIdentifier = store.folderIdentifier(forSnippetIdentifier: snippet.identifier)
        if currentFolderIdentifier == targetFolder.identifier { return }
        let remainingIdentifiers = currentFolderIdentifier
            .flatMap { store.folder(identifier: $0) }
            .map { Array($0.snippets).map(\.identifier).filter { $0 != snippet.identifier } }
        store.moveSnippet(
            identifier: snippet.identifier,
            toFolderIdentifier: targetFolder.identifier,
            index: targetFolder.snippets.count
        )
        if let currentFolderIdentifier, let remainingIdentifiers {
            store.reorderSnippets(remainingIdentifiers, folderIdentifier: currentFolderIdentifier)
        }
    }
}
