import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class BoardManSnippetEditingPolicyTests {
    @Test
    func editorContainerClickRequiresSnippetSelectionAndIdleEditingState() {
        #expect(BoardManSnippetEditingPolicy.shouldBeginEditorContainerClick(
            isSnippetTab: true,
            isEditing: false,
            hasSelection: true
        ))
        #expect(!BoardManSnippetEditingPolicy.shouldBeginEditorContainerClick(
            isSnippetTab: false,
            isEditing: false,
            hasSelection: true
        ))
        #expect(!BoardManSnippetEditingPolicy.shouldBeginEditorContainerClick(
            isSnippetTab: true,
            isEditing: true,
            hasSelection: true
        ))
        #expect(!BoardManSnippetEditingPolicy.shouldBeginEditorContainerClick(
            isSnippetTab: true,
            isEditing: false,
            hasSelection: false
        ))
    }

    @Test
    func draftPersistenceUpdatesSnippetAndOnlyAllowedFolderState() throws {
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        let snippet = BoardManSnippet()
        let folder = BoardManFolder()
        folder.enable = false
        store.upsertFolder(folder)
        store.upsertSnippet(snippet, folderIdentifier: folder.identifier)
        let editableSnippet = try #require(store.snippet(identifier: snippet.identifier))
        let editableFolder = try #require(store.folder(identifier: folder.identifier))

        BoardManSnippetEditingPolicy.persist(
            draft: BoardManSnippetDraft(
                title: "tmux",
                content: "tmux new -A -s",
                snippetEnabled: true,
                folderEnabled: true,
                canEditFolder: true
            ),
            snippet: editableSnippet,
            folder: editableFolder,
            store: store
        )
        #expect(editableSnippet.title == "tmux")
        #expect(editableSnippet.content == "tmux new -A -s")
        #expect(editableSnippet.enable)
        #expect(editableFolder.enable)

        BoardManSnippetEditingPolicy.persist(
            draft: BoardManSnippetDraft(
                title: "free edit",
                content: "echo free",
                snippetEnabled: false,
                folderEnabled: false,
                canEditFolder: false
            ),
            snippet: editableSnippet,
            folder: editableFolder,
            store: store
        )
        #expect(editableFolder.enable, "A disallowed folder edit must not mutate folder state.")
        BoardManSnippetEditingPolicy.persistTitle("Renamed", snippet: editableSnippet, store: store)
        let persistedSnippet = try #require(store.snippet(identifier: snippet.identifier))
        #expect(persistedSnippet.title == "Renamed")
        #expect(persistedSnippet.content == "echo free")
        #expect(!persistedSnippet.enable)
        #expect(store.folder(identifier: folder.identifier)?.enable == true)
    }

    @Test
    func reorderingMovesIdentifiersWithoutLosingItems() {
        #expect(BoardManSnippetEditingPolicy.reorderedIdentifiers(
            ["a", "b", "c"],
            moving: "a",
            to: 3
        ) == ["b", "c", "a"])
        #expect(BoardManSnippetEditingPolicy.reorderedIdentifiers(
            ["a", "b", "c"],
            moving: "c",
            to: 0
        ) == ["c", "a", "b"])
        #expect(BoardManSnippetEditingPolicy.reorderedIdentifiers(
            ["a", "b", "c"],
            moving: "missing",
            to: 1
        ) == ["a", "b", "c"])
    }
}
