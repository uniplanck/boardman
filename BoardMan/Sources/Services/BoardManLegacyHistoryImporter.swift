//
//  BoardManLegacyHistoryImporter.swift
//  Board-Man
//
//  Prepares and verifies a SQLite migration candidate without replacing the
//  current authoritative store. The legacy Realm remains available for rollback.
//

import CryptoKit
import Foundation
import RealmSwift

struct BoardManFolderMigrationSnapshot: Equatable {
    let identifier: String
    let index: Int
    let enable: Bool
    let title: String
}

struct BoardManSnippetMigrationSnapshot: Equatable {
    let identifier: String
    let index: Int
    let enable: Bool
    let title: String
    let content: String
    let folderIdentifier: String?
    let folderPosition: Int?
}

struct BoardManMigrationVerification: Equatable {
    let historyCount: Int
    let folderCount: Int
    let snippetCount: Int
    let digest: String
}

struct BoardManPreparedHistoryMigration: Equatable {
    let sourceCount: Int
    let destinationCount: Int
    let sourceFolderCount: Int
    let destinationFolderCount: Int
    let sourceSnippetCount: Int
    let destinationSnippetCount: Int
    let verificationDigest: String
    let backupURL: URL
    let candidateURL: URL
}

enum BoardManHistoryMigrationVerifier {
    static func digest(for snapshots: [BoardManClipSnapshot]) -> String {
        digest(history: snapshots, folders: [], snippets: [])
    }

    static func digest(
        history: [BoardManClipSnapshot],
        folders: [BoardManFolderMigrationSnapshot],
        snippets: [BoardManSnippetMigrationSnapshot]
    ) -> String {
        var hasher = SHA256()
        append("history", to: &hasher)
        for snapshot in history.sorted(by: { $0.dataHash < $1.dataHash }) {
            appendFields([
                snapshot.dataHash,
                snapshot.dataPath,
                snapshot.title,
                snapshot.primaryType,
                String(snapshot.createdTime),
                String(snapshot.updateTime),
                snapshot.thumbnailPath,
                snapshot.isColorCode ? "1" : "0"
            ], to: &hasher)
        }

        append("folders", to: &hasher)
        for folder in folders.sorted(by: { $0.identifier < $1.identifier }) {
            appendFields([
                folder.identifier,
                String(folder.index),
                folder.enable ? "1" : "0",
                folder.title
            ], to: &hasher)
        }

        append("snippets", to: &hasher)
        for snippet in snippets.sorted(by: { $0.identifier < $1.identifier }) {
            appendFields([
                snippet.identifier,
                String(snippet.index),
                snippet.enable ? "1" : "0",
                snippet.title,
                snippet.content,
                snippet.folderIdentifier ?? "",
                snippet.folderPosition.map(String.init) ?? ""
            ], to: &hasher)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func appendFields(_ fields: [String], to hasher: inout SHA256) {
        fields.forEach { append($0, to: &hasher) }
        hasher.update(data: Data([0xFF]))
    }

    private static func append(_ value: String, to hasher: inout SHA256) {
        hasher.update(data: Data(value.utf8))
        hasher.update(data: Data([0]))
    }
}

enum BoardManHistoryMigrationPreparationResult: Equatable {
    case skippedNoHistory
    case prepared(BoardManPreparedHistoryMigration)
    case failed(String)
}

struct BoardManActivatedHistoryMigration: Equatable {
    let destinationURL: URL
    let migratedCount: Int
}

enum BoardManHistoryCutoverResult: Equatable {
    case activated(BoardManActivatedHistoryMigration)
    case resumed(BoardManActivatedHistoryMigration)
    case failed(String)
}

struct BoardManHistoryMigrationManifest: Codable, Equatable {
    enum State: String, Codable {
        case prepared
        case promoted
        case activated
    }

    static let currentVersion = 2

    let version: Int
    let sourceCount: Int
    let destinationCount: Int
    let sourceFolderCount: Int
    let destinationFolderCount: Int
    let sourceSnippetCount: Int
    let destinationSnippetCount: Int
    let verificationDigest: String
    let backupPath: String
    let candidatePath: String
    let destinationPath: String
    var state: State

    init(
        prepared: BoardManPreparedHistoryMigration,
        destinationURL: URL,
        state: State = .prepared
    ) {
        version = Self.currentVersion
        sourceCount = prepared.sourceCount
        destinationCount = prepared.destinationCount
        sourceFolderCount = prepared.sourceFolderCount
        destinationFolderCount = prepared.destinationFolderCount
        sourceSnippetCount = prepared.sourceSnippetCount
        destinationSnippetCount = prepared.destinationSnippetCount
        verificationDigest = prepared.verificationDigest
        backupPath = prepared.backupURL.path
        candidatePath = prepared.candidateURL.path
        destinationPath = destinationURL.path
        self.state = state
    }

    var preparedMigration: BoardManPreparedHistoryMigration {
        BoardManPreparedHistoryMigration(
            sourceCount: sourceCount,
            destinationCount: destinationCount,
            sourceFolderCount: sourceFolderCount,
            destinationFolderCount: destinationFolderCount,
            sourceSnippetCount: sourceSnippetCount,
            destinationSnippetCount: destinationSnippetCount,
            verificationDigest: verificationDigest,
            backupURL: URL(fileURLWithPath: backupPath),
            candidateURL: URL(fileURLWithPath: candidatePath)
        )
    }

    var destinationURL: URL {
        URL(fileURLWithPath: destinationPath)
    }
}

enum BoardManHistoryMigrationManifestStore {
    static func write(
        _ manifest: BoardManHistoryMigrationManifest,
        to fileURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func load(from fileURL: URL) throws -> BoardManHistoryMigrationManifest {
        let manifest = try JSONDecoder().decode(
            BoardManHistoryMigrationManifest.self,
            from: Data(contentsOf: fileURL)
        )
        guard manifest.version == BoardManHistoryMigrationManifest.currentVersion,
              manifest.sourceCount >= 0,
              manifest.sourceCount == manifest.destinationCount,
              manifest.sourceFolderCount >= 0,
              manifest.sourceFolderCount == manifest.destinationFolderCount,
              manifest.sourceSnippetCount >= 0,
              manifest.sourceSnippetCount == manifest.destinationSnippetCount,
              manifest.verificationDigest.count == 64,
              !manifest.backupPath.isEmpty,
              !manifest.candidatePath.isEmpty,
              !manifest.destinationPath.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return manifest
    }
}

enum BoardManHistoryPersistenceBootstrapResult: Equatable {
    case realmWithShadowReplication
    case realmFailClosed(String)
    case sqliteActivated(BoardManActivatedHistoryMigration)
    case sqliteResumed(BoardManActivatedHistoryMigration)

    var shouldStartRealmShadowReplication: Bool {
        if case .realmWithShadowReplication = self { return true }
        return false
    }

    var isSQLiteAuthoritative: Bool {
        switch self {
        case .sqliteActivated, .sqliteResumed:
            return true
        case .realmWithShadowReplication, .realmFailClosed:
            return false
        }
    }
}

enum BoardManHistoryPersistenceBootstrap {
    static func prepareLegacyRealmSchema() {
        Realm.migration()
    }

    static func bootstrap(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        manifestURL: URL? = nil,
        destinationURL: URL? = nil,
        stagingDirectoryURL: URL? = nil,
        backupDirectoryURL: URL? = nil,
        router: BoardManStoreRouter = BoardManStores.authoritative,
        fileManager: FileManager = .default,
        realmProvider: () throws -> Realm = { try Realm() },
        prepareCandidate: ((Realm) -> BoardManHistoryMigrationPreparationResult)? = nil
    ) -> BoardManHistoryPersistenceBootstrapResult {
        let resolvedManifestURL = manifestURL
            ?? BoardManRuntimeSupport.historyMigrationManifestURL(environment: environment)
        let resolvedDestinationURL = destinationURL
            ?? BoardManRuntimeSupport.sqliteHistoryFileURL(environment: environment)
        let resolvedStagingDirectoryURL = stagingDirectoryURL
            ?? BoardManRuntimeSupport.sqliteMigrationStagingDirectoryURL(environment: environment)
        let resolvedBackupDirectoryURL = backupDirectoryURL
            ?? BoardManRuntimeSupport.legacyRealmBackupDirectoryURL(environment: environment)

        if fileManager.fileExists(atPath: resolvedManifestURL.path) {
            do {
                let manifest = try BoardManHistoryMigrationManifestStore.load(from: resolvedManifestURL)
                guard standardized(manifest.destinationURL) == standardized(resolvedDestinationURL),
                      isWithin(
                        URL(fileURLWithPath: manifest.candidatePath),
                        directory: resolvedStagingDirectoryURL
                      ),
                      isWithin(
                        URL(fileURLWithPath: manifest.backupPath),
                        directory: resolvedBackupDirectoryURL
                      ) else {
                    throw CocoaError(.fileReadCorruptFile)
                }

                switch BoardManHistoryCutoverCoordinator.resume(
                    from: resolvedManifestURL,
                    router: router,
                    fileManager: fileManager
                ) {
                case .activated(let migration):
                    return .sqliteActivated(migration)
                case .resumed(let migration):
                    return .sqliteResumed(migration)
                case .failed(let reason):
                    router.replaceBackend(with: RealmBoardManStore.shared)
                    return .realmFailClosed(reason)
                }
            } catch {
                router.replaceBackend(with: RealmBoardManStore.shared)
                return .realmFailClosed(error.localizedDescription)
            }
        }

        guard BoardManRuntimeSupport.prefersSQLiteHistory(environment: environment) else {
            router.replaceBackend(with: RealmBoardManStore.shared)
            return .realmWithShadowReplication
        }

        do {
            let realm = try realmProvider()
            let preparation = prepareCandidate?(realm)
                ?? BoardManLegacyHistoryImporter.prepareCandidate(
                    from: realm,
                    environment: environment,
                    fileManager: fileManager
                )

            switch preparation {
            case .prepared(let prepared):
                switch BoardManHistoryCutoverCoordinator.activate(
                    prepared,
                    destinationURL: resolvedDestinationURL,
                    manifestURL: resolvedManifestURL,
                    router: router,
                    fileManager: fileManager
                ) {
                case .activated(let migration):
                    return .sqliteActivated(migration)
                case .resumed(let migration):
                    return .sqliteResumed(migration)
                case .failed(let reason):
                    router.replaceBackend(with: RealmBoardManStore.shared)
                    return .realmFailClosed(reason)
                }
            case .skippedNoHistory:
                let store = try SQLiteBoardManStore(fileURL: resolvedDestinationURL)
                router.replaceBackend(with: store)
                return .sqliteActivated(
                    BoardManActivatedHistoryMigration(destinationURL: resolvedDestinationURL, migratedCount: 0)
                )
            case .failed(let reason):
                router.replaceBackend(with: RealmBoardManStore.shared)
                return .realmFailClosed(reason)
            }
        } catch {
            router.replaceBackend(with: RealmBoardManStore.shared)
            return .realmFailClosed(error.localizedDescription)
        }
    }

    private static func standardized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isWithin(_ fileURL: URL, directory: URL) -> Bool {
        let directoryPath = standardized(directory)
        let filePath = standardized(fileURL)
        return filePath == directoryPath || filePath.hasPrefix(directoryPath + "/")
    }
}

enum BoardManHistoryCutoverCoordinator {
    static func activate(
        _ prepared: BoardManPreparedHistoryMigration,
        destinationURL: URL,
        manifestURL: URL? = nil,
        router: BoardManStoreRouter = BoardManStores.authoritative,
        fileManager: FileManager = .default
    ) -> BoardManHistoryCutoverResult {
        guard prepared.sourceCount == prepared.destinationCount,
              prepared.sourceFolderCount == prepared.destinationFolderCount,
              prepared.sourceSnippetCount == prepared.destinationSnippetCount else {
            return .failed("Prepared migration count mismatch")
        }

        let resolvedManifestURL = manifestURL ?? destinationURL.deletingLastPathComponent()
            .appendingPathComponent("BoardMan-history-migration.json")
        var manifest = BoardManHistoryMigrationManifest(
            prepared: prepared,
            destinationURL: destinationURL
        )

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try BoardManHistoryMigrationManifestStore.write(
                manifest,
                to: resolvedManifestURL,
                fileManager: fileManager
            )

            if fileManager.fileExists(atPath: destinationURL.path) {
                let store = try verifiedStore(at: destinationURL, prepared: prepared)
                router.replaceBackend(with: store)
                manifest.state = .activated
                try BoardManHistoryMigrationManifestStore.write(
                    manifest,
                    to: resolvedManifestURL,
                    fileManager: fileManager
                )
                removeSQLiteFilesIfPresent(at: prepared.candidateURL, fileManager: fileManager)
                return .resumed(
                    BoardManActivatedHistoryMigration(
                        destinationURL: destinationURL,
                        migratedCount: prepared.destinationCount
                    )
                )
            }

            guard fileManager.fileExists(atPath: prepared.candidateURL.path) else {
                return .failed("Prepared SQLite migration candidate is missing")
            }

            _ = try verifiedStore(at: prepared.candidateURL, prepared: prepared)

            try fileManager.moveItem(at: prepared.candidateURL, to: destinationURL)
            manifest.state = .promoted
            try BoardManHistoryMigrationManifestStore.write(
                manifest,
                to: resolvedManifestURL,
                fileManager: fileManager
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destinationURL.path
            )

            let store = try verifiedStore(at: destinationURL, prepared: prepared)
            router.replaceBackend(with: store)
            manifest.state = .activated
            try BoardManHistoryMigrationManifestStore.write(
                manifest,
                to: resolvedManifestURL,
                fileManager: fileManager
            )
            return .activated(
                BoardManActivatedHistoryMigration(
                    destinationURL: destinationURL,
                    migratedCount: prepared.destinationCount
                )
            )
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func resume(
        from manifestURL: URL,
        router: BoardManStoreRouter = BoardManStores.authoritative,
        fileManager: FileManager = .default
    ) -> BoardManHistoryCutoverResult {
        do {
            let manifest = try BoardManHistoryMigrationManifestStore.load(from: manifestURL)
            return activate(
                manifest.preparedMigration,
                destinationURL: manifest.destinationURL,
                manifestURL: manifestURL,
                router: router,
                fileManager: fileManager
            )
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func removeSQLiteFilesIfPresent(at fileURL: URL, fileManager: FileManager) {
        [fileURL.path, fileURL.path + "-shm", fileURL.path + "-wal"].forEach { path in
            guard fileManager.fileExists(atPath: path) else { return }
            try? fileManager.removeItem(atPath: path)
        }
    }

    private static func verifiedStore(
        at fileURL: URL,
        prepared: BoardManPreparedHistoryMigration
    ) throws -> SQLiteBoardManStore {
        let store = try SQLiteBoardManStore(fileURL: fileURL)
        let history = try store.snapshotsForVerification()
        let structured = try store.templateSnapshotsForVerification()
        let digest = BoardManHistoryMigrationVerifier.digest(
            history: history,
            folders: structured.folders,
            snippets: structured.snippets
        )
        guard history.count == prepared.destinationCount,
              structured.folders.count == prepared.destinationFolderCount,
              structured.snippets.count == prepared.destinationSnippetCount,
              digest == prepared.verificationDigest else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return store
    }
}

enum BoardManLegacyHistoryImporter {
    static func prepareCandidate(
        from realm: Realm,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> BoardManHistoryMigrationPreparationResult {
        let candidateURL = BoardManRuntimeSupport
            .sqliteMigrationStagingDirectoryURL(environment: environment)
            .appendingPathComponent("BoardMan-history-\(UUID().uuidString).sqlite")
        return prepareCandidate(
            from: realm,
            candidateURL: candidateURL,
            backupDirectoryURL: BoardManRuntimeSupport.legacyRealmBackupDirectoryURL(environment: environment),
            fileManager: fileManager
        )
    }

    static func prepareCandidate(
        from realm: Realm,
        candidateURL: URL,
        backupDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> BoardManHistoryMigrationPreparationResult {
        do {
            let sourceHistory = realm.objects(BoardManClip.self)
                .map(BoardManClipSnapshot.init)
                .sorted { $0.dataHash < $1.dataHash }
            let sourceStructured = try templateSnapshots(from: realm)
            guard !sourceHistory.isEmpty || !sourceStructured.folders.isEmpty || !sourceStructured.snippets.isEmpty else {
                return .skippedNoHistory
            }

            guard !fileManager.fileExists(atPath: candidateURL.path) else {
                return .failed("SQLite migration candidate already exists")
            }

            try preparePrivateDirectory(candidateURL.deletingLastPathComponent(), fileManager: fileManager)
            try preparePrivateDirectory(backupDirectoryURL, fileManager: fileManager)

            let backupURL = try createReadOnlyBackup(
                of: realm,
                in: backupDirectoryURL,
                fileManager: fileManager
            )

            let destinationVerification: BoardManMigrationVerification
            do {
                destinationVerification = try importAndVerify(
                    history: sourceHistory,
                    folders: sourceStructured.folders,
                    snippets: sourceStructured.snippets,
                    candidateURL: candidateURL
                )
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: candidateURL.path
                )
            } catch {
                removeSQLiteFiles(at: candidateURL, fileManager: fileManager)
                throw error
            }

            return .prepared(
                BoardManPreparedHistoryMigration(
                    sourceCount: sourceHistory.count,
                    destinationCount: destinationVerification.historyCount,
                    sourceFolderCount: sourceStructured.folders.count,
                    destinationFolderCount: destinationVerification.folderCount,
                    sourceSnippetCount: sourceStructured.snippets.count,
                    destinationSnippetCount: destinationVerification.snippetCount,
                    verificationDigest: destinationVerification.digest,
                    backupURL: backupURL,
                    candidateURL: candidateURL
                )
            )
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func importAndVerify(
        history sourceHistory: [BoardManClipSnapshot],
        folders sourceFolders: [BoardManFolderMigrationSnapshot],
        snippets sourceSnippets: [BoardManSnippetMigrationSnapshot],
        candidateURL: URL
    ) throws -> BoardManMigrationVerification {
        let store = try SQLiteBoardManStore(fileURL: candidateURL)
        try store.replaceAllClipsSafely(with: sourceHistory)
        try store.replaceAllTemplatesSafely(folders: sourceFolders, snippets: sourceSnippets)

        let destinationHistory = try store.snapshotsForVerification()
        let destinationStructured = try store.templateSnapshotsForVerification()
        guard destinationHistory == sourceHistory,
              destinationStructured.folders == sourceFolders,
              destinationStructured.snippets == sourceSnippets else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let sourceDigest = BoardManHistoryMigrationVerifier.digest(
            history: sourceHistory,
            folders: sourceFolders,
            snippets: sourceSnippets
        )
        let destinationDigest = BoardManHistoryMigrationVerifier.digest(
            history: destinationHistory,
            folders: destinationStructured.folders,
            snippets: destinationStructured.snippets
        )
        guard destinationDigest == sourceDigest else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return BoardManMigrationVerification(
            historyCount: destinationHistory.count,
            folderCount: destinationStructured.folders.count,
            snippetCount: destinationStructured.snippets.count,
            digest: destinationDigest
        )
    }

    private static func templateSnapshots(
        from realm: Realm
    ) throws -> (folders: [BoardManFolderMigrationSnapshot], snippets: [BoardManSnippetMigrationSnapshot]) {
        let folders = realm.objects(BoardManFolder.self)
            .map {
                BoardManFolderMigrationSnapshot(
                    identifier: $0.identifier,
                    index: $0.index,
                    enable: $0.enable,
                    title: $0.title
                )
            }
            .sorted { $0.identifier < $1.identifier }

        var membership = [String: (folderIdentifier: String, position: Int)]()
        for folder in realm.objects(BoardManFolder.self) {
            for (position, snippet) in folder.snippets.enumerated() {
                guard membership[snippet.identifier] == nil else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                membership[snippet.identifier] = (folder.identifier, position)
            }
        }

        let snippets = realm.objects(BoardManSnippet.self)
            .map { snippet -> BoardManSnippetMigrationSnapshot in
                let relation = membership[snippet.identifier]
                return BoardManSnippetMigrationSnapshot(
                    identifier: snippet.identifier,
                    index: snippet.index,
                    enable: snippet.enable,
                    title: snippet.title,
                    content: snippet.content,
                    folderIdentifier: relation?.folderIdentifier,
                    folderPosition: relation?.position
                )
            }
            .sorted { $0.identifier < $1.identifier }
        return (folders, snippets)
    }

    private static func createReadOnlyBackup(
        of realm: Realm,
        in directoryURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let backupURL = directoryURL.appendingPathComponent(
            "BoardMan-before-SQLite-\(formatter.string(from: Date()))-\(UUID().uuidString).realm"
        )
        try realm.writeCopy(toFile: backupURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o400],
            ofItemAtPath: backupURL.path
        )
        return backupURL
    }

    private static func preparePrivateDirectory(
        _ directoryURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }

    private static func removeSQLiteFiles(at fileURL: URL, fileManager: FileManager) {
        [fileURL.path, fileURL.path + "-shm", fileURL.path + "-wal"].forEach { path in
            guard fileManager.fileExists(atPath: path) else { return }
            try? fileManager.removeItem(atPath: path)
        }
    }
}
