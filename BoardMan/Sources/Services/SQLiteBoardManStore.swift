//
//  SQLiteBoardManStore.swift
//  Board-Man
//
//  SQLiteData-backed persistence candidate for the Realm migration.
//

import Foundation
import GRDB
import SQLiteData

final class SQLiteBoardManStore: BoardManStore {
    private let database: any DatabaseWriter

    init(database: any DatabaseWriter) throws {
        self.database = database
        try Self.migrate(database)
    }

    convenience init(fileURL: URL) throws {
        guard BoardManRuntimeSupport.prepareDirectory(at: fileURL.deletingLastPathComponent().path) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try self.init(database: DatabaseQueue(path: fileURL.path))
    }

    static func inMemoryForTesting() throws -> SQLiteBoardManStore {
        try SQLiteBoardManStore(database: DatabaseQueue())
    }

    func createBackup(at fileURL: URL, fileManager: FileManager = .default) throws {
        guard !fileManager.fileExists(atPath: fileURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let backupDatabase = try DatabaseQueue(path: fileURL.path)
        try database.backup(to: backupDatabase)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func restoreBackup(
        from backupURL: URL,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws -> SQLiteBoardManStore {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var sourceConfiguration = Configuration()
        sourceConfiguration.readonly = true
        let sourceDatabase = try DatabaseQueue(path: backupURL.path, configuration: sourceConfiguration)
        let destinationDatabase = try DatabaseQueue(path: destinationURL.path)
        try sourceDatabase.backup(to: destinationDatabase)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
        return try SQLiteBoardManStore(fileURL: destinationURL)
    }

    private func postHistoryDidChange() {
        NotificationCenter.default.post(name: .boardManHistoryStoreDidChange, object: self)
    }

    var hasClips: Bool {
        try! database.read { db in
            try Int.fetchOne(db, sql: "SELECT 1 FROM history_items LIMIT 1") != nil
        }
    }

    func clip(identifier: String) -> BoardManClip? {
        try! database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT dataHash, dataPath, title, primaryType, createdTime, updateTime, thumbnailPath, isColorCode FROM history_items WHERE dataHash = ? LIMIT 1",
                arguments: [identifier]
            ) else {
                return nil
            }
            return Self.clip(from: row)
        }
    }

    func clipsSortedByUpdateTimeDescending() -> [BoardManClip] {
        try! database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT dataHash, dataPath, title, primaryType, createdTime, updateTime, thumbnailPath, isColorCode FROM history_items ORDER BY updateTime DESC"
            )
            .map(Self.clip)
        }
    }

    func clipsSortedByCreatedTimeDescending() -> [BoardManClip] {
        try! database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT dataHash, dataPath, title, primaryType, createdTime, updateTime, thumbnailPath, isColorCode FROM history_items ORDER BY createdTime DESC"
            )
            .map(Self.clip)
        }
    }

    func latestClip(title: String, primaryTypes: [String]) -> BoardManClip? {
        guard !primaryTypes.isEmpty else { return nil }
        let placeholders = Array(repeating: "?", count: primaryTypes.count).joined(separator: ", ")
        return try! database.read { db in
            let arguments = StatementArguments([title] + primaryTypes)
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT dataHash, dataPath, title, primaryType, createdTime, updateTime, thumbnailPath, isColorCode FROM history_items WHERE title = ? AND primaryType IN (\(placeholders)) ORDER BY updateTime DESC LIMIT 1",
                arguments: arguments
            ) else {
                return nil
            }
            return Self.clip(from: row)
        }
    }

    @discardableResult
    func updateClipUsage(identifier: String, updateTime: Int) -> Bool {
        try! database.write { db in
            try db.execute(
                sql: "UPDATE history_items SET updateTime = ? WHERE dataHash = ?",
                arguments: [updateTime, identifier]
            )
            let changed = db.changesCount > 0
            if changed {
                postHistoryDidChange()
            }
            return changed
        }
    }

    func upsertClip(_ clip: BoardManClip) {
        let snapshot = BoardManClipSnapshot(clip)
        try! database.write { db in
            try Self.upsert(snapshot, in: db)
        }
        postHistoryDidChange()
    }

    func replaceAllClips(with snapshots: [BoardManClipSnapshot]) {
        try! replaceAllClipsSafely(with: snapshots)
    }

    func replaceAllClipsSafely(with snapshots: [BoardManClipSnapshot]) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM history_items")
            for snapshot in snapshots {
                try Self.upsert(snapshot, in: db)
            }
        }
        postHistoryDidChange()
    }

    func snapshotsForVerification() throws -> [BoardManClipSnapshot] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT dataHash, dataPath, title, primaryType, createdTime, updateTime, thumbnailPath, isColorCode FROM history_items ORDER BY dataHash ASC"
            )
            .map { BoardManClipSnapshot(Self.clip(from: $0)) }
        }
    }

    func deleteClip(identifier: String) {
        deleteClips(identifiers: [identifier])
    }

    func deleteClips(identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }
        try! database.write { db in
            for identifier in identifiers {
                try db.execute(sql: "DELETE FROM history_items WHERE dataHash = ?", arguments: [identifier])
            }
        }
        postHistoryDidChange()
    }
}

extension SQLiteBoardManStore {
    func folder(identifier: String) -> BoardManFolder? {
        try! database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT identifier, sortIndex, enable, title FROM template_folders WHERE identifier = ? LIMIT 1",
                arguments: [identifier]
            ) else { return nil }
            return try Self.folder(from: row, database: db)
        }
    }

    func foldersSortedByIndex() -> [BoardManFolder] {
        try! database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT identifier, sortIndex, enable, title FROM template_folders ORDER BY sortIndex ASC, identifier ASC"
            ).map { try Self.folder(from: $0, database: db) }
        }
    }

    func snippet(identifier: String) -> BoardManSnippet? {
        try! database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT identifier, sortIndex, enable, title, content FROM templates WHERE identifier = ? LIMIT 1",
                arguments: [identifier]
            ) else { return nil }
            return Self.snippet(from: row)
        }
    }

    func snippetsSortedByIndex() -> [BoardManSnippet] {
        try! database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT identifier, sortIndex, enable, title, content FROM templates ORDER BY sortIndex ASC, identifier ASC"
            ).map(Self.snippet)
        }
    }

    func uncategorizedSnippetsSortedByIndex() -> [BoardManSnippet] {
        try! database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT t.identifier, t.sortIndex, t.enable, t.title, t.content
                    FROM templates t
                    LEFT JOIN template_folder_membership m ON m.snippetIdentifier = t.identifier
                    WHERE m.snippetIdentifier IS NULL
                    ORDER BY t.sortIndex ASC, t.identifier ASC
                    """
            ).map(Self.snippet)
        }
    }

    func folderIdentifier(forSnippetIdentifier identifier: String) -> String? {
        try! database.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT folderIdentifier FROM template_folder_membership WHERE snippetIdentifier = ? LIMIT 1",
                arguments: [identifier]
            )
        }
    }

    func upsertFolder(_ folder: BoardManFolder) {
        try! database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO template_folders (identifier, sortIndex, enable, title)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(identifier) DO UPDATE SET
                        sortIndex = excluded.sortIndex,
                        enable = excluded.enable,
                        title = excluded.title
                    """,
                arguments: [folder.identifier, folder.index, folder.enable, folder.title]
            )
        }
        postTemplatesDidChange()
    }

    func deleteFolder(identifier: String) {
        try! database.write { db in
            let snippetIdentifiers = try String.fetchAll(
                db,
                sql: "SELECT snippetIdentifier FROM template_folder_membership WHERE folderIdentifier = ?",
                arguments: [identifier]
            )
            for snippetIdentifier in snippetIdentifiers {
                try db.execute(sql: "DELETE FROM templates WHERE identifier = ?", arguments: [snippetIdentifier])
            }
            try db.execute(sql: "DELETE FROM template_folders WHERE identifier = ?", arguments: [identifier])
        }
        postTemplatesDidChange()
    }

    func upsertSnippet(_ snippet: BoardManSnippet, folderIdentifier: String?) {
        try! database.write { db in
            try Self.upsertSnippet(snippet, in: db)
            try Self.setMembership(
                snippetIdentifier: snippet.identifier,
                folderIdentifier: folderIdentifier,
                position: snippet.index,
                in: db
            )
        }
        postTemplatesDidChange()
    }

    func deleteSnippet(identifier: String) {
        try! database.write { db in
            try db.execute(sql: "DELETE FROM templates WHERE identifier = ?", arguments: [identifier])
        }
        postTemplatesDidChange()
    }

    func moveSnippet(identifier: String, toFolderIdentifier: String?, index: Int) {
        try! database.write { db in
            try db.execute(
                sql: "UPDATE templates SET sortIndex = ? WHERE identifier = ?",
                arguments: [index, identifier]
            )
            guard db.changesCount > 0 else { return }
            try Self.setMembership(
                snippetIdentifier: identifier,
                folderIdentifier: toFolderIdentifier,
                position: index,
                in: db
            )
        }
        postTemplatesDidChange()
    }

    func reorderFolders(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        try! database.write { db in
            for (index, identifier) in identifiers.enumerated() {
                try db.execute(
                    sql: "UPDATE template_folders SET sortIndex = ? WHERE identifier = ?",
                    arguments: [index, identifier]
                )
            }
        }
        postTemplatesDidChange()
    }

    func reorderSnippets(_ identifiers: [String], folderIdentifier: String?) {
        guard !identifiers.isEmpty else { return }
        try! database.write { db in
            for (index, identifier) in identifiers.enumerated() {
                try db.execute(
                    sql: "UPDATE templates SET sortIndex = ? WHERE identifier = ?",
                    arguments: [index, identifier]
                )
                try Self.setMembership(
                    snippetIdentifier: identifier,
                    folderIdentifier: folderIdentifier,
                    position: index,
                    in: db
                )
            }
        }
        postTemplatesDidChange()
    }

    func replaceAllTemplatesSafely(
        folders: [BoardManFolderMigrationSnapshot],
        snippets: [BoardManSnippetMigrationSnapshot]
    ) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM template_folder_membership")
            try db.execute(sql: "DELETE FROM templates")
            try db.execute(sql: "DELETE FROM template_folders")

            for folder in folders {
                try db.execute(
                    sql: """
                        INSERT INTO template_folders (identifier, sortIndex, enable, title)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [folder.identifier, folder.index, folder.enable, folder.title]
                )
            }
            for snippet in snippets {
                try db.execute(
                    sql: """
                        INSERT INTO templates (identifier, sortIndex, enable, title, content)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        snippet.identifier,
                        snippet.index,
                        snippet.enable,
                        snippet.title,
                        snippet.content
                    ]
                )
                if let folderIdentifier = snippet.folderIdentifier,
                   let position = snippet.folderPosition {
                    try db.execute(
                        sql: """
                            INSERT INTO template_folder_membership (
                                snippetIdentifier, folderIdentifier, position
                            ) VALUES (?, ?, ?)
                            """,
                        arguments: [snippet.identifier, folderIdentifier, position]
                    )
                } else if snippet.folderIdentifier != nil || snippet.folderPosition != nil {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
        }
        postTemplatesDidChange()
    }

    func templateSnapshotsForVerification() throws -> (
        folders: [BoardManFolderMigrationSnapshot],
        snippets: [BoardManSnippetMigrationSnapshot]
    ) {
        try database.read { db in
            let folders = try Row.fetchAll(
                db,
                sql: "SELECT identifier, sortIndex, enable, title FROM template_folders ORDER BY identifier ASC"
            ).map {
                BoardManFolderMigrationSnapshot(
                    identifier: $0["identifier"],
                    index: $0["sortIndex"],
                    enable: $0["enable"],
                    title: $0["title"]
                )
            }
            let snippets = try Row.fetchAll(
                db,
                sql: """
                    SELECT t.identifier, t.sortIndex, t.enable, t.title, t.content,
                           m.folderIdentifier, m.position
                    FROM templates t
                    LEFT JOIN template_folder_membership m ON m.snippetIdentifier = t.identifier
                    ORDER BY t.identifier ASC
                    """
            ).map { row in
                BoardManSnippetMigrationSnapshot(
                    identifier: row["identifier"],
                    index: row["sortIndex"],
                    enable: row["enable"],
                    title: row["title"],
                    content: row["content"],
                    folderIdentifier: row["folderIdentifier"],
                    folderPosition: row["position"]
                )
            }
            return (folders, snippets)
        }
    }

    private func postTemplatesDidChange() {
        NotificationCenter.default.post(name: .boardManTemplatesStoreDidChange, object: self)
    }

    private static func upsert(_ snapshot: BoardManClipSnapshot, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO history_items (
                    dataHash, dataPath, title, primaryType,
                    createdTime, updateTime, thumbnailPath, isColorCode
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(dataHash) DO UPDATE SET
                    dataPath = excluded.dataPath,
                    title = excluded.title,
                    primaryType = excluded.primaryType,
                    createdTime = excluded.createdTime,
                    updateTime = excluded.updateTime,
                    thumbnailPath = excluded.thumbnailPath,
                    isColorCode = excluded.isColorCode
                """,
            arguments: [
                snapshot.dataHash,
                snapshot.dataPath,
                snapshot.title,
                snapshot.primaryType,
                snapshot.createdTime,
                snapshot.updateTime,
                snapshot.thumbnailPath,
                snapshot.isColorCode,
            ]
        )
    }

    private static func upsertSnippet(_ snippet: BoardManSnippet, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO templates (identifier, sortIndex, enable, title, content)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(identifier) DO UPDATE SET
                    sortIndex = excluded.sortIndex,
                    enable = excluded.enable,
                    title = excluded.title,
                    content = excluded.content
                """,
            arguments: [snippet.identifier, snippet.index, snippet.enable, snippet.title, snippet.content]
        )
    }

    private static func setMembership(
        snippetIdentifier: String,
        folderIdentifier: String?,
        position: Int,
        in db: Database
    ) throws {
        try db.execute(
            sql: "DELETE FROM template_folder_membership WHERE snippetIdentifier = ?",
            arguments: [snippetIdentifier]
        )
        guard let folderIdentifier else { return }
        guard try Int.fetchOne(
            db,
            sql: "SELECT 1 FROM template_folders WHERE identifier = ? LIMIT 1",
            arguments: [folderIdentifier]
        ) != nil else { return }
        try db.execute(
            sql: """
                INSERT INTO template_folder_membership (snippetIdentifier, folderIdentifier, position)
                VALUES (?, ?, ?)
                """,
            arguments: [snippetIdentifier, folderIdentifier, position]
        )
    }

    private static func migrate(_ database: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("Create history_items") { db in
            try db.execute(
                sql: """
                    CREATE TABLE history_items (
                        dataHash TEXT NOT NULL PRIMARY KEY,
                        dataPath TEXT NOT NULL,
                        title TEXT NOT NULL,
                        primaryType TEXT NOT NULL,
                        createdTime INTEGER NOT NULL,
                        updateTime INTEGER NOT NULL,
                        thumbnailPath TEXT NOT NULL,
                        isColorCode INTEGER NOT NULL
                    ) STRICT
                    """
            )
            try db.execute(
                sql: "CREATE INDEX history_items_updateTime_idx ON history_items(updateTime DESC)"
            )
        }
        migrator.registerMigration("Create templates and folders") { db in
            try db.execute(
                sql: """
                    CREATE TABLE template_folders (
                        identifier TEXT NOT NULL PRIMARY KEY,
                        sortIndex INTEGER NOT NULL,
                        enable INTEGER NOT NULL,
                        title TEXT NOT NULL
                    ) STRICT
                    """
            )
            try db.execute(
                sql: """
                    CREATE TABLE templates (
                        identifier TEXT NOT NULL PRIMARY KEY,
                        sortIndex INTEGER NOT NULL,
                        enable INTEGER NOT NULL,
                        title TEXT NOT NULL,
                        content TEXT NOT NULL
                    ) STRICT
                    """
            )
            try db.execute(
                sql: """
                    CREATE TABLE template_folder_membership (
                        snippetIdentifier TEXT NOT NULL PRIMARY KEY REFERENCES templates(identifier) ON DELETE CASCADE,
                        folderIdentifier TEXT NOT NULL REFERENCES template_folders(identifier) ON DELETE CASCADE,
                        position INTEGER NOT NULL
                    ) STRICT
                    """
            )
            try db.execute(sql: "CREATE INDEX template_folders_sort_idx ON template_folders(sortIndex ASC)")
            try db.execute(sql: "CREATE INDEX templates_sort_idx ON templates(sortIndex ASC)")
            try db.execute(
                sql: "CREATE INDEX template_membership_folder_position_idx ON template_folder_membership(folderIdentifier, position ASC)"
            )
        }
        try migrator.migrate(database)
    }

    private static func clip(from row: Row) -> BoardManClip {
        let clip = BoardManClip()
        clip.dataHash = row["dataHash"]
        clip.dataPath = row["dataPath"]
        clip.title = row["title"]
        clip.primaryType = row["primaryType"]
        clip.createdTime = row["createdTime"]
        clip.updateTime = row["updateTime"]
        clip.thumbnailPath = row["thumbnailPath"]
        clip.isColorCode = row["isColorCode"]
        return clip
    }

    private static func snippet(from row: Row) -> BoardManSnippet {
        let snippet = BoardManSnippet()
        snippet.identifier = row["identifier"]
        snippet.index = row["sortIndex"]
        snippet.enable = row["enable"]
        snippet.title = row["title"]
        snippet.content = row["content"]
        return snippet
    }

    private static func folder(from row: Row, database db: Database) throws -> BoardManFolder {
        let folder = BoardManFolder()
        folder.identifier = row["identifier"]
        folder.index = row["sortIndex"]
        folder.enable = row["enable"]
        folder.title = row["title"]
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT t.identifier, t.sortIndex, t.enable, t.title, t.content
                FROM template_folder_membership m
                JOIN templates t ON t.identifier = m.snippetIdentifier
                WHERE m.folderIdentifier = ?
                ORDER BY m.position ASC, t.sortIndex ASC, t.identifier ASC
                """,
            arguments: [folder.identifier]
        )
        rows.forEach { folder.snippets.append(snippet(from: $0)) }
        return folder
    }
}
