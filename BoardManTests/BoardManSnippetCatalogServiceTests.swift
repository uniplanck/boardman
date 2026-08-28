import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class BoardManSnippetCatalogServiceTests {
    @Test
    func folderCrudMovesSnippetsToUncategorizedAndPreservesOrder() throws {
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        let folder = BoardManSnippetCatalogService.createFolder(title: "Work", store: store)
        let first = BoardManSnippet()
        first.title = "A"
        first.index = 0
        let second = BoardManSnippet()
        second.title = "B"
        second.index = 1
        store.upsertSnippet(first, folderIdentifier: folder.identifier)
        store.upsertSnippet(second, folderIdentifier: folder.identifier)

        BoardManSnippetCatalogService.renameFolder(folder, title: "Projects", store: store)
        #expect(store.folder(identifier: folder.identifier)?.title == "Projects")

        let fallback = try #require(BoardManSnippetCatalogService.deleteFolder(
            identifier: folder.identifier,
            store: store
        ))
        #expect(store.folder(identifier: folder.identifier) == nil)
        #expect(fallback.title == "Uncategorized")
        let persistedFallback = try #require(store.folder(identifier: fallback.identifier))
        #expect(Array(persistedFallback.snippets).map(\.identifier) == [first.identifier, second.identifier])
    }

    @Test
    func commercialAdmissionGatesFolderAndSnippetCreationWithoutDeletingExistingData() throws {
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        let freeService = EntitlementService(snapshot: .freeDefault)

        let firstFolder = try #require(BoardManSnippetCatalogService.createFolderIfAllowed(
            title: "Free Folder",
            store: store,
            entitlementService: freeService
        ))
        #expect(BoardManSnippetCatalogService.createFolderIfAllowed(
            title: "Blocked Folder",
            store: store,
            entitlementService: freeService
        ) == nil)
        #expect(store.foldersSortedByIndex().map(\.identifier).contains(firstFolder.identifier))

        for _ in 0..<5 {
            #expect(BoardManSnippetCatalogService.createSnippetIfAllowed(
                preferredFolderIdentifier: firstFolder.identifier,
                allCategoriesIdentifier: "__all__",
                uncategorizedIdentifier: "__uncategorized__",
                store: store,
                entitlementService: freeService
            ) != nil)
        }
        #expect(BoardManSnippetCatalogService.createSnippetIfAllowed(
            preferredFolderIdentifier: firstFolder.identifier,
            allCategoriesIdentifier: "__all__",
            uncategorizedIdentifier: "__uncategorized__",
            store: store,
            entitlementService: freeService
        ) == nil)
        #expect(store.snippetsSortedByIndex().count == 5)

        let legacyUnlimited = EntitlementService(snapshot: .proActive())
        #expect(BoardManSnippetCatalogService.createFolderIfAllowed(
            title: "Lifetime-compatible Folder",
            store: store,
            entitlementService: legacyUnlimited
        ) != nil)
        #expect(BoardManSnippetCatalogService.createSnippetIfAllowed(
            preferredFolderIdentifier: firstFolder.identifier,
            allCategoriesIdentifier: "__all__",
            uncategorizedIdentifier: "__uncategorized__",
            store: store,
            entitlementService: legacyUnlimited
        ) != nil)
    }

    @Test
    func snippetCrudSelectsDeterministicTargetsAndCompactsAfterDelete() throws {
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        let disabled = BoardManSnippetCatalogService.createFolder(title: "Disabled", store: store)
        disabled.enable = false
        store.upsertFolder(disabled)
        let enabled = BoardManSnippetCatalogService.createFolder(title: "Enabled", store: store)

        let creation = BoardManSnippetCatalogService.createSnippet(
            preferredFolderIdentifier: "__all__",
            allCategoriesIdentifier: "__all__",
            uncategorizedIdentifier: "__uncategorized__",
            store: store
        )
        #expect(creation.folder.identifier == enabled.identifier)
        #expect(creation.snippet.title == boardManText("Untitled snippet"))

        let second = BoardManSnippetCatalogService.createSnippet(
            preferredFolderIdentifier: enabled.identifier,
            allCategoriesIdentifier: "__all__",
            uncategorizedIdentifier: "__uncategorized__",
            store: store
        ).snippet
        #expect(BoardManSnippetCatalogService.deleteSnippet(identifier: creation.snippet.identifier, store: store))
        #expect(Array(try #require(store.folder(identifier: enabled.identifier)).snippets).map(\.identifier) == [second.identifier])
        #expect(!BoardManSnippetCatalogService.deleteSnippet(identifier: "missing", store: store))

        #expect(BoardManSnippetCatalogService.normalizedCategoryTitle("  Work  ") == "Work")
        #expect(BoardManSnippetCatalogService.normalizedCategoryTitle("  \n ") == nil)
        #expect(BoardManSnippetCatalogService.normalizedSnippetTitle("  \n ") == boardManText("Untitled snippet"))
    }
}
