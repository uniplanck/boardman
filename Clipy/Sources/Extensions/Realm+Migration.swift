//
//  Realm+Migration.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/10/16.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import RealmSwift

extension Realm {
    static func migration() {
        let config = Realm.Configuration(schemaVersion: LegacySnippetMigrationService.schemaVersion, migrationBlock: { migration, oldSchemaVersion in
            if oldSchemaVersion <= 2 {
                migration.enumerateObjects(ofType: CPYSnippet.className()) { _, newObject in
                    newObject?["identifier"] = NSUUID().uuidString
                }
            }
            if oldSchemaVersion <= 4 {
                migration.enumerateObjects(ofType: CPYFolder.className()) { _, newObject in
                    newObject?["identifier"] = NSUUID().uuidString
                }
            }
            if oldSchemaVersion <= 5 {
                migration.enumerateObjects(ofType: CPYClip.className()) { oldObject, newObject in
                    newObject?["dataPath"] = oldObject?["dataPath"]
                    newObject?["title"] = oldObject?["title"]
                    newObject?["dataHash"] = oldObject?["dataHash"]
                    newObject?["primaryType"] = oldObject?["primaryType"]
                    newObject?["updateTime"] = oldObject?["updateTime"]
                    newObject?["thumbnailPath"] = oldObject?["thumbnailPath"]
                }
                migration.enumerateObjects(ofType: CPYSnippet.className()) { oldObject, newObject in
                    newObject?["index"] = oldObject?["index"]
                    newObject?["enable"] = oldObject?["enable"]
                    newObject?["title"] = oldObject?["title"]
                    newObject?["content"] = oldObject?["content"]
                    if oldSchemaVersion >= 3 {
                        newObject?["identifier"] = oldObject?["identifier"]
                    }
                }
                migration.enumerateObjects(ofType: CPYFolder.className()) { oldObject, newObject in
                    newObject?["index"] = oldObject?["index"]
                    newObject?["enable"] = oldObject?["enable"]
                    newObject?["title"] = oldObject?["title"]
                    if oldSchemaVersion >= 5 {
                        newObject?["identifier"] = oldObject?["identifier"]
                    }
                }
            }
            if oldSchemaVersion < 8 {
                migration.enumerateObjects(ofType: CPYClip.className()) { oldObject, newObject in
                    let updateTime = oldObject?["updateTime"] as? Int ?? 0
                    var createdTime = updateTime * 1000
                    if let dataPath = oldObject?["dataPath"] as? String,
                       !dataPath.isEmpty,
                       let attributes = try? FileManager.default.attributesOfItem(atPath: dataPath),
                       let fileDate = (attributes[.creationDate] as? Date) ?? (attributes[.modificationDate] as? Date) {
                        createdTime = Int(fileDate.timeIntervalSince1970 * 1000)
                    }
                    newObject?["createdTime"] = createdTime
                }
            }
        })
        Realm.Configuration.defaultConfiguration = config

        let realm = try! Realm()
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        let result = LegacySnippetMigrationService.migrateIfNeeded(into: realm)
        LegacySnippetMigrationService.publishDiagnostic(result)
    }
}

enum LegacySnippetMigrationResult: Equatable {
    case skippedExistingData
    case noRecoverableSource
    case restored(sourceDirectory: String, folderCount: Int, snippetCount: Int)
    case failed
}

enum LegacySnippetMigrationService {
    static let schemaVersion: UInt64 = 8

    private struct SnippetSnapshot {
        let index: Int
        let enable: Bool
        let title: String
        let content: String
        let identifier: String
    }

    private struct FolderSnapshot {
        let index: Int
        let enable: Bool
        let title: String
        let identifier: String
        let snippetIdentifiers: [String]
    }

    private struct SourceSnapshot {
        let url: URL
        let modificationDate: Date
        let snippets: [SnippetSnapshot]
        let folders: [FolderSnapshot]
    }

    static func migrateIfNeeded(
        into destination: Realm,
        candidateURLs: [URL] = defaultCandidateURLs(),
        backupDirectoryURL: URL = defaultBackupDirectoryURL()
    ) -> LegacySnippetMigrationResult {
        let destinationURL = destination.configuration.fileURL?.standardizedFileURL
        let candidates = candidateURLs
            .filter { $0.standardizedFileURL != destinationURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        let sourceSnapshots = candidates.compactMap { try? sourceSnapshot(at: $0) }
            .filter { !$0.snippets.isEmpty }
        guard let source = sourceSnapshots.max(by: { lhs, rhs in
            if lhs.snippets.count == rhs.snippets.count {
                return lhs.modificationDate < rhs.modificationDate
            }
            return lhs.snippets.count < rhs.snippets.count
        }) else {
            return .noRecoverableSource
        }

        let existingSnippetIdentifiers = Set(destination.objects(CPYSnippet.self).map(\.identifier))
        let missingSnippetSnapshots = source.snippets.filter {
            !existingSnippetIdentifiers.contains($0.identifier)
        }
        let folderChangeCount = source.folders.reduce(into: 0) { count, snapshot in
            guard let existingFolder = destination.object(
                ofType: CPYFolder.self,
                forPrimaryKey: snapshot.identifier
            ) else {
                count += 1
                return
            }
            let linkedIdentifiers = Set(existingFolder.snippets.map(\.identifier))
            if snapshot.snippetIdentifiers.contains(where: { !linkedIdentifiers.contains($0) }) {
                count += 1
            }
        }

        guard !missingSnippetSnapshots.isEmpty || folderChangeCount > 0 else {
            return .skippedExistingData
        }

        do {
            try createBackup(of: destination, in: backupDirectoryURL)
            try destination.write {
                for snapshot in missingSnippetSnapshots {
                    let snippet = CPYSnippet()
                    snippet.index = snapshot.index
                    snippet.enable = snapshot.enable
                    snippet.title = snapshot.title
                    snippet.content = snapshot.content
                    snippet.identifier = snapshot.identifier
                    destination.add(snippet)
                }

                for snapshot in source.folders {
                    let folder: CPYFolder
                    if let existingFolder = destination.object(
                        ofType: CPYFolder.self,
                        forPrimaryKey: snapshot.identifier
                    ) {
                        folder = existingFolder
                    } else {
                        let newFolder = CPYFolder()
                        newFolder.index = snapshot.index
                        newFolder.enable = snapshot.enable
                        newFolder.title = snapshot.title
                        newFolder.identifier = snapshot.identifier
                        destination.add(newFolder)
                        folder = newFolder
                    }

                    var linkedIdentifiers = Set(folder.snippets.map(\.identifier))
                    for identifier in snapshot.snippetIdentifiers where !linkedIdentifiers.contains(identifier) {
                        if let snippet = destination.object(ofType: CPYSnippet.self, forPrimaryKey: identifier) {
                            folder.snippets.append(snippet)
                            linkedIdentifiers.insert(identifier)
                        }
                    }
                }
            }
        } catch {
            return .failed
        }

        return .restored(
            sourceDirectory: source.url.deletingLastPathComponent().lastPathComponent,
            folderCount: folderChangeCount,
            snippetCount: missingSnippetSnapshots.count
        )
    }

    private static func sourceSnapshot(at sourceURL: URL) throws -> SourceSnapshot {
        var configuration = Realm.Configuration(fileURL: sourceURL, readOnly: true)
        configuration.schemaVersion = schemaVersion
        let source = try Realm(configuration: configuration)
        let snippets = Array(source.objects(CPYSnippet.self).map {
            SnippetSnapshot(
                index: $0.index,
                enable: $0.enable,
                title: $0.title,
                content: $0.content,
                identifier: $0.identifier
            )
        })
        let folders = Array(source.objects(CPYFolder.self).map {
            FolderSnapshot(
                index: $0.index,
                enable: $0.enable,
                title: $0.title,
                identifier: $0.identifier,
                snippetIdentifiers: $0.snippets.map(\.identifier)
            )
        })
        return SourceSnapshot(
            url: sourceURL,
            modificationDate: modificationDate(of: sourceURL),
            snippets: snippets,
            folders: folders
        )
    }

    static func defaultCandidateURLs(fileManager: FileManager = .default) -> [URL] {
        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return []
        }
        return [
            "com.uniplanck.BoardMan2",
            "com.uniplanck.BoardManDogfood",
            "com.clipy-app.Clipy"
        ].map { supportURL.appendingPathComponent($0).appendingPathComponent("default.realm") }
    }

    static func defaultBackupDirectoryURL(fileManager: FileManager = .default) -> URL {
        let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return cacheURL
            .appendingPathComponent("Board-Man", isDirectory: true)
            .appendingPathComponent("DataBackups.noindex", isDirectory: true)
    }

    static func publishDiagnostic(_ result: LegacySnippetMigrationResult, defaults: UserDefaults = .standard) {
        switch result {
        case .skippedExistingData:
            if defaults.string(forKey: "BoardManLegacySnippetMigrationStatus") == nil {
                defaults.set("skippedExistingData", forKey: "BoardManLegacySnippetMigrationStatus")
            }
        case .noRecoverableSource:
            defaults.set("noRecoverableSource", forKey: "BoardManLegacySnippetMigrationStatus")
        case .restored(let sourceDirectory, let folderCount, let snippetCount):
            defaults.set("restored", forKey: "BoardManLegacySnippetMigrationStatus")
            defaults.set(sourceDirectory, forKey: "BoardManLegacySnippetMigrationSource")
            defaults.set(folderCount, forKey: "BoardManLegacySnippetMigrationFolderCount")
            defaults.set(snippetCount, forKey: "BoardManLegacySnippetMigrationSnippetCount")
            defaults.set(Date(), forKey: "BoardManLegacySnippetMigrationDate")
        case .failed:
            defaults.set("failed", forKey: "BoardManLegacySnippetMigrationStatus")
        }
    }

    private static func modificationDate(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private static func createBackup(of realm: Realm, in directoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let backupURL = directoryURL.appendingPathComponent("before-snippet-recovery-\(formatter.string(from: Date())).realm")
        try realm.writeCopy(toFile: backupURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
    }
}
