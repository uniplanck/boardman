import Foundation

struct BoardManSnippetDraft: Equatable {
    let title: String
    let content: String
    let snippetEnabled: Bool
    let folderEnabled: Bool
    let canEditFolder: Bool
}

enum BoardManSnippetEditingPolicy {
    static func shouldBeginEditorContainerClick(
        isSnippetTab: Bool,
        isEditing: Bool,
        hasSelection: Bool
    ) -> Bool {
        return isSnippetTab && !isEditing && hasSelection
    }

    static func persist(
        draft: BoardManSnippetDraft,
        snippet: BoardManSnippet,
        folder: BoardManFolder?,
        store: BoardManStore
    ) {
        snippet.title = draft.title
        snippet.content = draft.content
        snippet.enable = draft.snippetEnabled
        store.upsertSnippet(
            snippet,
            folderIdentifier: store.folderIdentifier(forSnippetIdentifier: snippet.identifier)
        )
        if draft.canEditFolder, let folder {
            folder.enable = draft.folderEnabled
            store.upsertFolder(folder)
        }
    }

    static func persistTitle(_ title: String, snippet: BoardManSnippet, store: BoardManStore) {
        guard snippet.title != title else { return }
        snippet.title = title
        store.upsertSnippet(
            snippet,
            folderIdentifier: store.folderIdentifier(forSnippetIdentifier: snippet.identifier)
        )
    }

    static func reorderedIdentifiers(
        _ identifiers: [String],
        moving identifier: String,
        to destinationRow: Int
    ) -> [String] {
        guard let sourceIndex = identifiers.firstIndex(of: identifier) else { return identifiers }
        var reordered = identifiers
        let moved = reordered.remove(at: sourceIndex)
        var targetIndex = max(0, min(destinationRow, reordered.count))
        if destinationRow > sourceIndex {
            targetIndex = max(0, min(destinationRow - 1, reordered.count))
        }
        reordered.insert(moved, at: targetIndex)
        return reordered
    }
}
