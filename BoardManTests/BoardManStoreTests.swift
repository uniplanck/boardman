import AppKit
import RealmSwift
import XCTest
@testable import Board_Man

// Migration coverage is intentionally colocated so all persistence backends share one serialized Realm fixture.
// swiftlint:disable:next type_body_length
final class BoardManStoreTests: XCTestCase {
    private var originalConfiguration: Realm.Configuration!

    override func setUp() {
        super.setUp()
        originalConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
    }

    override func tearDown() {
        Realm.Configuration.defaultConfiguration = originalConfiguration
        originalConfiguration = nil
        super.tearDown()
    }

    func testRealmStoreUpsertsReadsSortsAndDeletesDetachedClips() throws {
        try assertStoreContract(RealmBoardManStore.shared)
    }

    func testSQLiteStoreUpsertsReadsSortsAndDeletesDetachedClips() throws {
        try assertStoreContract(SQLiteBoardManStore.inMemoryForTesting())
    }

    func testSQLiteStoreReplaceAllClipsRemovesStaleRows() throws {
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        store.upsertClip(makeClip(identifier: "stale", updateTime: 1, title: "stale"))
        store.upsertClip(makeClip(identifier: "keep", updateTime: 2, title: "before"))

        let replacement = makeClip(identifier: "keep", updateTime: 3, title: "after")
        let added = makeClip(identifier: "added", updateTime: 4, title: "added")
        store.replaceAllClips(with: [BoardManClipSnapshot(replacement), BoardManClipSnapshot(added)])

        XCTAssertNil(store.clip(identifier: "stale"))
        XCTAssertEqual(store.clip(identifier: "keep")?.title, "after")
        XCTAssertEqual(store.clipsSortedByUpdateTimeDescending().map(\.dataHash), ["added", "keep"])
    }

    func testRealmTemplateStoreContract() throws {
        try assertTemplateStoreContract(RealmBoardManStore.shared)
    }

    func testSQLiteTemplateStoreContract() throws {
        try assertTemplateStoreContract(SQLiteBoardManStore.inMemoryForTesting())
    }

    func testSQLiteAuthoritativeRuntimeModelFlowDoesNotTouchRealm() throws {
        let sqlite = try SQLiteBoardManStore.inMemoryForTesting()
        BoardManStores.authoritative.replaceBackend(with: sqlite)
        defer { BoardManStores.authoritative.replaceBackend(with: RealmBoardManStore.shared) }

        let folder = BoardManFolder.create()
        folder.title = "SQLite Runtime"
        folder.merge()
        let snippet = folder.createSnippet()
        snippet.title = "Runtime Snippet"
        snippet.content = "echo sqlite"
        folder.mergeSnippet(snippet)

        let storedFolder = try XCTUnwrap(sqlite.folder(identifier: folder.identifier))
        let storedSnippet = try XCTUnwrap(sqlite.snippet(identifier: snippet.identifier))
        XCTAssertEqual(storedFolder.snippets.map(\.identifier), [snippet.identifier])
        XCTAssertEqual(storedSnippet.content, "echo sqlite")
        XCTAssertNil(storedFolder.realm)
        XCTAssertNil(storedSnippet.realm)

        storedSnippet.title = "Renamed on SQLite"
        storedSnippet.merge()
        XCTAssertEqual(sqlite.snippet(identifier: snippet.identifier)?.title, "Renamed on SQLite")
        folder.removeSnippet(storedSnippet)
        XCTAssertNil(sqlite.folderIdentifier(forSnippetIdentifier: snippet.identifier))
        storedSnippet.remove()
        folder.remove()
        XCTAssertNil(sqlite.snippet(identifier: snippet.identifier))
        XCTAssertNil(sqlite.folder(identifier: folder.identifier))
    }

    func testSQLiteBackupRestorePreservesHistoryTemplatesAndRelationships() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source/BoardMan.sqlite")
        let backupURL = root.appendingPathComponent("backup/BoardMan.sqlite")
        let restoreURL = root.appendingPathComponent("restored/BoardMan.sqlite")
        let store = try SQLiteBoardManStore(fileURL: sourceURL)
        store.upsertClip(makeClip(identifier: "history-a", updateTime: 12, title: "History A"))
        let folder = makeFolder(identifier: "folder-a", index: 0, title: "Folder A")
        let snippet = makeSnippet(identifier: "snippet-a", index: 0, title: "Snippet A")
        store.upsertFolder(folder)
        store.upsertSnippet(snippet, folderIdentifier: folder.identifier)

        try store.createBackup(at: backupURL)
        store.deleteClip(identifier: "history-a")
        store.deleteSnippet(identifier: "snippet-a")
        let restored = try SQLiteBoardManStore.restoreBackup(from: backupURL, to: restoreURL)

        XCTAssertEqual(restored.clip(identifier: "history-a")?.title, "History A")
        XCTAssertEqual(restored.folder(identifier: "folder-a")?.snippets.map(\.identifier), ["snippet-a"])
        XCTAssertEqual(restored.folderIdentifier(forSnippetIdentifier: "snippet-a"), "folder-a")
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: backupURL.path)[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: restoreURL.path)[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func testStoreRouterSwitchesBackendForRetainedConsumerReference() throws {
        let router = BoardManStoreRouter(initialBackend: RealmBoardManStore.shared)
        let retainedConsumerReference: BoardManStore = router
        retainedConsumerReference.upsertClip(
            makeClip(identifier: "realm-only", updateTime: 1, title: "Realm")
        )
        XCTAssertEqual(retainedConsumerReference.clip(identifier: "realm-only")?.title, "Realm")

        let sqlite = try SQLiteBoardManStore.inMemoryForTesting()
        let historyChange = expectation(forNotification: .boardManHistoryStoreDidChange, object: router)
        let templatesChange = expectation(forNotification: .boardManTemplatesStoreDidChange, object: router)
        router.replaceBackend(with: sqlite)
        wait(for: [historyChange, templatesChange], timeout: 0.2)

        XCTAssertFalse(retainedConsumerReference.hasClips)
        retainedConsumerReference.upsertClip(
            makeClip(identifier: "sqlite-only", updateTime: 2, title: "SQLite")
        )
        XCTAssertNil(sqlite.clip(identifier: "realm-only"))
        XCTAssertEqual(sqlite.clip(identifier: "sqlite-only")?.title, "SQLite")
        XCTAssertEqual(retainedConsumerReference.clip(identifier: "sqlite-only")?.title, "SQLite")
    }

    func testLargeProfileMigrationBenchmarkContract() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realm = try makeFileBackedRealm(at: root.appendingPathComponent("large.realm"))
        let clips = (0..<10_000).map { index in
            makeClip(identifier: "history-\(index)", updateTime: index, title: "History \(index)")
        }
        let folders = (0..<100).map { folderIndex -> BoardManFolder in
            let folder = makeFolder(identifier: "folder-\(folderIndex)", index: folderIndex, title: "Folder \(folderIndex)")
            (0..<10).forEach { snippetIndex in
                folder.snippets.append(
                    makeSnippet(
                        identifier: "snippet-\(folderIndex)-\(snippetIndex)",
                        index: snippetIndex,
                        title: "Snippet \(folderIndex)-\(snippetIndex)"
                    )
                )
            }
            return folder
        }
        try realm.write {
            realm.add(clips)
            realm.add(folders)
        }

        let candidateURL = root.appendingPathComponent("staging/BoardMan.sqlite")
        let startedAt = CFAbsoluteTimeGetCurrent()
        let result = BoardManLegacyHistoryImporter.prepareCandidate(
            from: realm,
            candidateURL: candidateURL,
            backupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        let durationMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        guard case .prepared(let prepared) = result else {
            return XCTFail("Expected large-profile migration to prepare successfully, got \(result)")
        }
        let sqliteBytes = (try FileManager.default.attributesOfItem(atPath: candidateURL.path)[.size] as? NSNumber)?.uint64Value ?? 0

        XCTAssertEqual(prepared.destinationCount, 10_000)
        XCTAssertEqual(prepared.destinationFolderCount, 100)
        XCTAssertEqual(prepared.destinationSnippetCount, 1_000)
        XCTAssertGreaterThan(sqliteBytes, 0)
        print(
            "BOARDMAN_MIGRATION_BENCHMARK history=10000 folders=100 snippets=1000 " +
            "duration_ms=\(String(format: "%.2f", durationMilliseconds)) sqlite_bytes=\(sqliteBytes)"
        )
    }

    func testLegacyHistoryImporterPreparesVerifiedCandidateAndReadOnlyBackup() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realmURL = root.appendingPathComponent("source.realm")
        let realm = try makeFileBackedRealm(at: realmURL)
        let first = makeClip(identifier: "alpha", updateTime: 10, title: "Alpha")
        let second = makeClip(identifier: "beta", updateTime: 20, title: "Beta")
        let folder = makeFolder(identifier: "folder-a", index: 0, title: "Folder A")
        let groupedSnippet = makeSnippet(identifier: "snippet-a", index: 0, title: "Grouped")
        let uncategorizedSnippet = makeSnippet(identifier: "snippet-b", index: 1, title: "Uncategorized")
        folder.snippets.append(groupedSnippet)
        try realm.write {
            realm.add(first)
            realm.add(second)
            realm.add(folder)
            realm.add(uncategorizedSnippet)
        }

        let candidateURL = root.appendingPathComponent("staging/history.sqlite")
        let backupDirectoryURL = root.appendingPathComponent("backups", isDirectory: true)
        let result = BoardManLegacyHistoryImporter.prepareCandidate(
            from: realm,
            candidateURL: candidateURL,
            backupDirectoryURL: backupDirectoryURL
        )

        guard case .prepared(let prepared) = result else {
            return XCTFail("Expected prepared migration, got \(result)")
        }
        XCTAssertEqual(prepared.sourceCount, 2)
        XCTAssertEqual(prepared.destinationCount, 2)
        XCTAssertEqual(prepared.sourceFolderCount, 1)
        XCTAssertEqual(prepared.destinationFolderCount, 1)
        XCTAssertEqual(prepared.sourceSnippetCount, 2)
        XCTAssertEqual(prepared.destinationSnippetCount, 2)
        XCTAssertEqual(prepared.candidateURL, candidateURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.backupURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidateURL.path))
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: prepared.backupURL.path)[.posixPermissions] as? NSNumber)?.intValue,
            0o400
        )
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: candidateURL.path)[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
        XCTAssertEqual(realm.objects(BoardManClip.self).count, 2)

        let migrated = try SQLiteBoardManStore(fileURL: candidateURL)
        XCTAssertEqual(migrated.clipsSortedByCreatedTimeDescending().map(\.dataHash), ["beta", "alpha"])
        XCTAssertEqual(migrated.clip(identifier: "alpha")?.title, "Alpha")
        XCTAssertEqual(migrated.foldersSortedByIndex().map(\.identifier), ["folder-a"])
        XCTAssertEqual(migrated.folder(identifier: "folder-a")?.snippets.map(\.identifier), ["snippet-a"])
        XCTAssertEqual(migrated.folderIdentifier(forSnippetIdentifier: "snippet-a"), "folder-a")
        XCTAssertNil(migrated.folderIdentifier(forSnippetIdentifier: "snippet-b"))
        XCTAssertEqual(migrated.uncategorizedSnippetsSortedByIndex().map(\.identifier), ["snippet-b"])
    }

    func testLegacyHistoryImporterSkipsEmptySourceWithoutCreatingCandidate() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realm = try makeFileBackedRealm(at: root.appendingPathComponent("empty.realm"))
        let candidateURL = root.appendingPathComponent("staging/history.sqlite")
        let result = BoardManLegacyHistoryImporter.prepareCandidate(
            from: realm,
            candidateURL: candidateURL,
            backupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )

        XCTAssertEqual(result, .skippedNoHistory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidateURL.path))
    }

    func testLegacyHistoryImporterMigratesTemplatesWithoutHistory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realm = try makeFileBackedRealm(at: root.appendingPathComponent("templates-only.realm"))
        let folder = makeFolder(identifier: "folder-only", index: 0, title: "Only Folder")
        let snippet = makeSnippet(identifier: "snippet-only", index: 0, title: "Only Snippet")
        folder.snippets.append(snippet)
        try realm.write { realm.add(folder) }

        let candidateURL = root.appendingPathComponent("staging/templates.sqlite")
        let result = BoardManLegacyHistoryImporter.prepareCandidate(
            from: realm,
            candidateURL: candidateURL,
            backupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )

        guard case .prepared(let prepared) = result else {
            return XCTFail("Expected templates-only source to migrate, got \(result)")
        }
        XCTAssertEqual(prepared.sourceCount, 0)
        XCTAssertEqual(prepared.destinationCount, 0)
        XCTAssertEqual(prepared.sourceFolderCount, 1)
        XCTAssertEqual(prepared.destinationFolderCount, 1)
        XCTAssertEqual(prepared.sourceSnippetCount, 1)
        XCTAssertEqual(prepared.destinationSnippetCount, 1)

        let migrated = try SQLiteBoardManStore(fileURL: candidateURL)
        XCTAssertEqual(migrated.foldersSortedByIndex().map(\.identifier), ["folder-only"])
        XCTAssertEqual(migrated.folder(identifier: "folder-only")?.snippets.map(\.identifier), ["snippet-only"])
    }

    func testLegacyHistoryImporterDoesNotOverwriteExistingCandidate() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realm = try makeFileBackedRealm(at: root.appendingPathComponent("source.realm"))
        try realm.write {
            realm.add(makeClip(identifier: "existing", updateTime: 1, title: "source"))
        }

        let candidateDirectory = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: candidateDirectory, withIntermediateDirectories: true)
        let candidateURL = candidateDirectory.appendingPathComponent("history.sqlite")
        let sentinel = Data("do-not-overwrite".utf8)
        try sentinel.write(to: candidateURL)

        let result = BoardManLegacyHistoryImporter.prepareCandidate(
            from: realm,
            candidateURL: candidateURL,
            backupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )

        guard case .failed = result else {
            return XCTFail("Expected migration preparation failure")
        }
        XCTAssertEqual(try Data(contentsOf: candidateURL), sentinel)
    }

    func testHistoryCutoverAtomicallyPromotesVerifiedCandidateAndSwitchesRouter() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realm = try makeFileBackedRealm(at: root.appendingPathComponent("source.realm"))
        let folder = makeFolder(identifier: "cutover-folder", index: 0, title: "Cutover Folder")
        let snippet = makeSnippet(identifier: "cutover-snippet", index: 0, title: "Cutover Snippet")
        folder.snippets.append(snippet)
        try realm.write {
            realm.add(makeClip(identifier: "alpha", updateTime: 10, title: "Alpha"))
            realm.add(makeClip(identifier: "beta", updateTime: 20, title: "Beta"))
            realm.add(folder)
        }
        let candidateURL = root.appendingPathComponent("staging/history.sqlite")
        let preparedResult = BoardManLegacyHistoryImporter.prepareCandidate(
            from: realm,
            candidateURL: candidateURL,
            backupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        guard case .prepared(let prepared) = preparedResult else {
            return XCTFail("Expected prepared migration")
        }

        let router = BoardManStoreRouter(initialBackend: RealmBoardManStore.shared)
        let retainedReference: BoardManStore = router
        let destinationURL = root.appendingPathComponent("final/BoardMan-v2.sqlite")
        let manifestURL = root.appendingPathComponent("final/migration.json")
        let result = BoardManHistoryCutoverCoordinator.activate(
            prepared,
            destinationURL: destinationURL,
            manifestURL: manifestURL,
            router: router
        )

        guard case .activated(let activated) = result else {
            return XCTFail("Expected activated cutover, got \(result)")
        }
        XCTAssertEqual(activated.destinationURL, destinationURL)
        XCTAssertEqual(activated.migratedCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(retainedReference.clipsSortedByCreatedTimeDescending().map(\.dataHash), ["beta", "alpha"])
        XCTAssertEqual(retainedReference.foldersSortedByIndex().map(\.identifier), ["cutover-folder"])
        XCTAssertEqual(retainedReference.folder(identifier: "cutover-folder")?.snippets.map(\.identifier), ["cutover-snippet"])
        XCTAssertEqual(retainedReference.folderIdentifier(forSnippetIdentifier: "cutover-snippet"), "cutover-folder")
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: destinationURL.path)[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
        XCTAssertEqual(realm.objects(BoardManClip.self).count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.backupURL.path))
        XCTAssertEqual(
            try BoardManHistoryMigrationManifestStore.load(from: manifestURL).state,
            .activated
        )
    }

    func testHistoryCutoverResumesAfterMoveBeforeRouterSwitch() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realm = try makeFileBackedRealm(at: root.appendingPathComponent("source.realm"))
        try realm.write {
            realm.add(makeClip(identifier: "resume", updateTime: 10, title: "Resume"))
        }
        let preparedResult = BoardManLegacyHistoryImporter.prepareCandidate(
            from: realm,
            candidateURL: root.appendingPathComponent("staging/history.sqlite"),
            backupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        guard case .prepared(let prepared) = preparedResult else {
            return XCTFail("Expected prepared migration")
        }

        let destinationURL = root.appendingPathComponent("final/BoardMan-v2.sqlite")
        let manifestURL = root.appendingPathComponent("final/migration.json")
        try BoardManHistoryMigrationManifestStore.write(
            BoardManHistoryMigrationManifest(
                prepared: prepared,
                destinationURL: destinationURL
            ),
            to: manifestURL
        )
        try FileManager.default.moveItem(at: prepared.candidateURL, to: destinationURL)

        let router = BoardManStoreRouter(initialBackend: RealmBoardManStore.shared)
        let result = BoardManHistoryCutoverCoordinator.resume(
            from: manifestURL,
            router: router
        )

        guard case .resumed(let resumed) = result else {
            return XCTFail("Expected resumed cutover, got \(result)")
        }
        XCTAssertEqual(resumed.migratedCount, 1)
        XCTAssertEqual(router.clip(identifier: "resume")?.title, "Resume")
        XCTAssertEqual(realm.objects(BoardManClip.self).count, 1)
        XCTAssertEqual(
            try BoardManHistoryMigrationManifestStore.load(from: manifestURL).state,
            .activated
        )
    }

    func testHistoryCutoverRejectsCorruptManifestWithoutSwitchingRouter() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = root.appendingPathComponent("migration.json")
        try Data("not-json".utf8).write(to: manifestURL)
        let router = BoardManStoreRouter(initialBackend: RealmBoardManStore.shared)

        let result = BoardManHistoryCutoverCoordinator.resume(
            from: manifestURL,
            router: router
        )

        guard case .failed = result else {
            return XCTFail("Expected corrupt manifest failure")
        }
        XCTAssertFalse(router.hasClips)
    }

    func testHistoryCutoverRefusesSameCountDestinationWithWrongDigest() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realm = try makeFileBackedRealm(at: root.appendingPathComponent("source.realm"))
        try realm.write {
            realm.add(makeClip(identifier: "expected-a", updateTime: 10, title: "A"))
            realm.add(makeClip(identifier: "expected-b", updateTime: 20, title: "B"))
        }
        let preparedResult = BoardManLegacyHistoryImporter.prepareCandidate(
            from: realm,
            candidateURL: root.appendingPathComponent("staging/history.sqlite"),
            backupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        guard case .prepared(let prepared) = preparedResult else {
            return XCTFail("Expected prepared migration")
        }

        let destinationURL = root.appendingPathComponent("final/BoardMan-v2.sqlite")
        var wrongDestination: SQLiteBoardManStore? = try SQLiteBoardManStore(fileURL: destinationURL)
        wrongDestination?.upsertClip(makeClip(identifier: "wrong-a", updateTime: 10, title: "A"))
        wrongDestination?.upsertClip(makeClip(identifier: "wrong-b", updateTime: 20, title: "B"))
        wrongDestination = nil

        let router = BoardManStoreRouter(initialBackend: RealmBoardManStore.shared)
        let result = BoardManHistoryCutoverCoordinator.activate(
            prepared,
            destinationURL: destinationURL,
            router: router
        )

        guard case .failed = result else {
            return XCTFail("Expected digest verification failure")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.candidateURL.path))
        XCTAssertNil(router.clip(identifier: "wrong-a"))
        let unchangedDestination = try SQLiteBoardManStore(fileURL: destinationURL)
        XCTAssertEqual(
            unchangedDestination.clipsSortedByCreatedTimeDescending().map(\.dataHash),
            ["wrong-b", "wrong-a"]
        )
        XCTAssertEqual(realm.objects(BoardManClip.self).count, 2)
    }

    func testHistoryBootstrapKeepsRealmAndShadowReplicationByDefault() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realm = try Realm()
        try realm.write {
            realm.add(makeClip(identifier: "realm-default", updateTime: 1, title: "Realm"))
        }
        let router = BoardManStoreRouter(initialBackend: RealmBoardManStore.shared)
        let result = BoardManHistoryPersistenceBootstrap.bootstrap(
            environment: [:],
            manifestURL: root.appendingPathComponent("migration.json"),
            destinationURL: root.appendingPathComponent("BoardMan.sqlite"),
            stagingDirectoryURL: root.appendingPathComponent("staging", isDirectory: true),
            backupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true),
            router: router
        )

        XCTAssertEqual(result, .realmWithShadowReplication)
        XCTAssertTrue(result.shouldStartRealmShadowReplication)
        XCTAssertFalse(result.isSQLiteAuthoritative)
        XCTAssertEqual(router.clip(identifier: "realm-default")?.title, "Realm")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("BoardMan.sqlite").path))
    }

    func testHistoryBootstrapOptInActivatesSQLiteAndResumesWithoutOptIn() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realm = try makeFileBackedRealm(at: root.appendingPathComponent("source.realm"))
        try realm.write {
            realm.add(makeClip(identifier: "bootstrap", updateTime: 10, title: "Bootstrap"))
        }
        let stagingDirectory = root.appendingPathComponent("staging", isDirectory: true)
        let backupDirectory = root.appendingPathComponent("backups", isDirectory: true)
        let candidateURL = stagingDirectory.appendingPathComponent("history.sqlite")
        let destinationURL = root.appendingPathComponent("final/BoardMan.sqlite")
        let manifestURL = root.appendingPathComponent("final/migration.json")
        let firstRouter = BoardManStoreRouter(initialBackend: RealmBoardManStore.shared)

        let first = BoardManHistoryPersistenceBootstrap.bootstrap(
            environment: ["BOARDMAN_SQLITE_HISTORY": "1"],
            manifestURL: manifestURL,
            destinationURL: destinationURL,
            stagingDirectoryURL: stagingDirectory,
            backupDirectoryURL: backupDirectory,
            router: firstRouter,
            realmProvider: { realm },
            prepareCandidate: { sourceRealm in
                BoardManLegacyHistoryImporter.prepareCandidate(
                    from: sourceRealm,
                    candidateURL: candidateURL,
                    backupDirectoryURL: backupDirectory
                )
            }
        )

        guard case .sqliteActivated(let activated) = first else {
            return XCTFail("Expected SQLite activation, got \(first)")
        }
        XCTAssertEqual(activated.migratedCount, 1)
        XCTAssertTrue(first.isSQLiteAuthoritative)
        XCTAssertFalse(first.shouldStartRealmShadowReplication)
        XCTAssertEqual(firstRouter.clip(identifier: "bootstrap")?.title, "Bootstrap")
        XCTAssertEqual(try BoardManHistoryMigrationManifestStore.load(from: manifestURL).state, .activated)

        let relaunchRouter = BoardManStoreRouter(initialBackend: RealmBoardManStore.shared)
        let relaunched = BoardManHistoryPersistenceBootstrap.bootstrap(
            environment: [:],
            manifestURL: manifestURL,
            destinationURL: destinationURL,
            stagingDirectoryURL: stagingDirectory,
            backupDirectoryURL: backupDirectory,
            router: relaunchRouter
        )

        guard case .sqliteResumed(let resumed) = relaunched else {
            return XCTFail("Expected SQLite resume, got \(relaunched)")
        }
        XCTAssertEqual(resumed.migratedCount, 1)
        XCTAssertTrue(relaunched.isSQLiteAuthoritative)
        XCTAssertFalse(relaunched.shouldStartRealmShadowReplication)
        XCTAssertEqual(relaunchRouter.clip(identifier: "bootstrap")?.title, "Bootstrap")
    }

    func testHistoryBootstrapFailsClosedOnCorruptManifestWithoutShadowReplication() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realm = try Realm()
        try realm.write {
            realm.add(makeClip(identifier: "safe-realm", updateTime: 1, title: "Safe Realm"))
        }
        let manifestURL = root.appendingPathComponent("migration.json")
        try Data("corrupt".utf8).write(to: manifestURL)
        let router = BoardManStoreRouter(initialBackend: RealmBoardManStore.shared)

        let result = BoardManHistoryPersistenceBootstrap.bootstrap(
            environment: [:],
            manifestURL: manifestURL,
            destinationURL: root.appendingPathComponent("BoardMan.sqlite"),
            stagingDirectoryURL: root.appendingPathComponent("staging", isDirectory: true),
            backupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true),
            router: router
        )

        guard case .realmFailClosed = result else {
            return XCTFail("Expected fail-closed Realm fallback, got \(result)")
        }
        XCTAssertFalse(result.shouldStartRealmShadowReplication)
        XCTAssertFalse(result.isSQLiteAuthoritative)
        XCTAssertEqual(router.clip(identifier: "safe-realm")?.title, "Safe Realm")
    }

    func testHistoryBootstrapRejectsManifestPathsOutsideMigrationDirectories() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realm = try makeFileBackedRealm(at: root.appendingPathComponent("source.realm"))
        try realm.write {
            realm.add(makeClip(identifier: "path-check", updateTime: 1, title: "Path Check"))
        }
        let allowedStaging = root.appendingPathComponent("allowed-staging", isDirectory: true)
        let allowedBackups = root.appendingPathComponent("allowed-backups", isDirectory: true)
        let outsideStaging = root.appendingPathComponent("outside-staging", isDirectory: true)
        let outsideBackups = root.appendingPathComponent("outside-backups", isDirectory: true)
        let preparedResult = BoardManLegacyHistoryImporter.prepareCandidate(
            from: realm,
            candidateURL: outsideStaging.appendingPathComponent("history.sqlite"),
            backupDirectoryURL: outsideBackups
        )
        guard case .prepared(let prepared) = preparedResult else {
            return XCTFail("Expected prepared migration")
        }
        let destinationURL = root.appendingPathComponent("final/BoardMan.sqlite")
        let manifestURL = root.appendingPathComponent("final/migration.json")
        try BoardManHistoryMigrationManifestStore.write(
            BoardManHistoryMigrationManifest(prepared: prepared, destinationURL: destinationURL),
            to: manifestURL
        )
        let router = BoardManStoreRouter(initialBackend: RealmBoardManStore.shared)

        let result = BoardManHistoryPersistenceBootstrap.bootstrap(
            environment: [:],
            manifestURL: manifestURL,
            destinationURL: destinationURL,
            stagingDirectoryURL: allowedStaging,
            backupDirectoryURL: allowedBackups,
            router: router
        )

        guard case .realmFailClosed = result else {
            return XCTFail("Expected path validation failure, got \(result)")
        }
        XCTAssertFalse(result.shouldStartRealmShadowReplication)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    private func assertTemplateStoreContract(_ store: BoardManStore) throws {
        XCTAssertTrue(store.foldersSortedByIndex().isEmpty)
        XCTAssertTrue(store.snippetsSortedByIndex().isEmpty)

        let firstFolder = makeFolder(identifier: "folder-a", index: 1, title: "A")
        let secondFolder = makeFolder(identifier: "folder-b", index: 0, title: "B")
        store.upsertFolder(firstFolder)
        store.upsertFolder(secondFolder)
        XCTAssertEqual(store.foldersSortedByIndex().map(\.identifier), ["folder-b", "folder-a"])
        XCTAssertTrue(store.foldersSortedByIndex().allSatisfy { $0.realm == nil })

        let firstSnippet = makeSnippet(identifier: "snippet-a", index: 1, title: "A")
        let secondSnippet = makeSnippet(identifier: "snippet-b", index: 0, title: "B")
        let uncategorized = makeSnippet(identifier: "snippet-loose", index: 2, title: "Loose")
        store.upsertSnippet(firstSnippet, folderIdentifier: firstFolder.identifier)
        store.upsertSnippet(secondSnippet, folderIdentifier: firstFolder.identifier)
        store.upsertSnippet(uncategorized, folderIdentifier: nil)

        XCTAssertEqual(store.folder(identifier: firstFolder.identifier)?.snippets.map(\.identifier), ["snippet-b", "snippet-a"])
        XCTAssertEqual(store.folderIdentifier(forSnippetIdentifier: "snippet-a"), firstFolder.identifier)
        XCTAssertEqual(store.uncategorizedSnippetsSortedByIndex().map(\.identifier), ["snippet-loose"])
        XCTAssertNil(store.snippet(identifier: "snippet-a")?.realm)

        store.moveSnippet(identifier: "snippet-b", toFolderIdentifier: secondFolder.identifier, index: 0)
        XCTAssertEqual(store.folder(identifier: firstFolder.identifier)?.snippets.map(\.identifier), ["snippet-a"])
        XCTAssertEqual(store.folder(identifier: secondFolder.identifier)?.snippets.map(\.identifier), ["snippet-b"])
        XCTAssertEqual(store.folderIdentifier(forSnippetIdentifier: "snippet-b"), secondFolder.identifier)

        store.reorderFolders([firstFolder.identifier, secondFolder.identifier])
        XCTAssertEqual(store.foldersSortedByIndex().map(\.identifier), ["folder-a", "folder-b"])

        store.deleteFolder(identifier: secondFolder.identifier)
        XCTAssertNil(store.folder(identifier: secondFolder.identifier))
        XCTAssertNil(store.snippet(identifier: "snippet-b"))
        XCTAssertNotNil(store.snippet(identifier: "snippet-a"))

        store.deleteSnippet(identifier: "snippet-a")
        XCTAssertNil(store.snippet(identifier: "snippet-a"))
        XCTAssertEqual(store.uncategorizedSnippetsSortedByIndex().map(\.identifier), ["snippet-loose"])
    }

    private func assertStoreContract(_ store: BoardManStore) throws {
        XCTAssertFalse(store.hasClips)

        let older = makeClip(identifier: "older", updateTime: 10, title: "old")
        let newer = makeClip(identifier: "newer", updateTime: 20, title: "new")
        store.upsertClip(older)
        store.upsertClip(newer)
        XCTAssertTrue(store.hasClips)

        let fetched = store.clip(identifier: "older")
        XCTAssertEqual(fetched?.title, "old")
        XCTAssertNil(fetched?.realm)
        XCTAssertEqual(
            store.latestClip(
                title: "old",
                primaryTypes: [NSPasteboard.PasteboardType.string.rawValue]
            )?.dataHash,
            "older"
        )

        let ordered = store.clipsSortedByUpdateTimeDescending()
        XCTAssertEqual(ordered.map(\.dataHash), ["newer", "older"])
        XCTAssertTrue(ordered.allSatisfy { $0.realm == nil })
        XCTAssertEqual(store.clipsSortedByCreatedTimeDescending().map(\.dataHash), ["newer", "older"])

        XCTAssertTrue(store.updateClipUsage(identifier: "older", updateTime: 40))
        XCTAssertFalse(store.updateClipUsage(identifier: "missing", updateTime: 50))
        XCTAssertEqual(store.clipsSortedByUpdateTimeDescending().map(\.dataHash), ["older", "newer"])
        XCTAssertEqual(store.clipsSortedByCreatedTimeDescending().map(\.dataHash), ["newer", "older"])

        let replacement = makeClip(identifier: "older", updateTime: 50, title: "updated")
        store.upsertClip(replacement)
        XCTAssertEqual(store.clip(identifier: "older")?.title, "updated")

        store.deleteClips(identifiers: Set(["older", "newer"]))
        XCTAssertTrue(store.clipsSortedByUpdateTimeDescending().isEmpty)
        XCTAssertFalse(store.hasClips)
    }

    private func makeFolder(identifier: String, index: Int, title: String) -> BoardManFolder {
        let folder = BoardManFolder()
        folder.identifier = identifier
        folder.index = index
        folder.title = title
        return folder
    }

    private func makeSnippet(identifier: String, index: Int, title: String) -> BoardManSnippet {
        let snippet = BoardManSnippet()
        snippet.identifier = identifier
        snippet.index = index
        snippet.title = title
        snippet.content = "content-\(identifier)"
        return snippet
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFileBackedRealm(at url: URL) throws -> Realm {
        var configuration = Realm.Configuration(fileURL: url)
        configuration.objectTypes = [BoardManClip.self, BoardManFolder.self, BoardManSnippet.self]
        return try Realm(configuration: configuration)
    }

    private func makeClip(identifier: String, updateTime: Int, title: String) -> BoardManClip {
        let clip = BoardManClip()
        clip.dataHash = identifier
        clip.dataPath = "/tmp/\(identifier).data"
        clip.title = title
        clip.primaryType = NSPasteboard.PasteboardType.string.rawValue
        clip.createdTime = updateTime * 1000
        clip.updateTime = updateTime
        return clip
    }
}
