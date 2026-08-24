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

import Cocoa
import Foundation
import RealmSwift

private var isRunningBoardManTests: Bool {
    let processInfo = ProcessInfo.processInfo
    let environment = processInfo.environment
    if environment.keys.contains(where: {
        $0.localizedCaseInsensitiveContains("xctest")
            || $0.localizedCaseInsensitiveContains("xcinject")
    }) {
        return true
    }
    if environment["DYLD_INSERT_LIBRARIES"]?.localizedCaseInsensitiveContains("xctest") == true {
        return true
    }
    if processInfo.arguments.contains(where: {
        $0.localizedCaseInsensitiveContains(".xctest")
            || $0.localizedCaseInsensitiveContains("xctestconfiguration")
    }) {
        return true
    }
    return NSClassFromString("XCTestCase") != nil
        || Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
}

private func applyBoardManMigration(_ migration: Migration, oldSchemaVersion: UInt64) {
    // Swift type names are Board-Man owned. Objective-C runtime names stay historical at this
    // persistence compatibility boundary, so Realm's className() addresses existing tables.
    let snippetObjectName = BoardManSnippet.className()
    let folderObjectName = BoardManFolder.className()
    let clipObjectName = BoardManClip.className()

    if oldSchemaVersion <= 2 {
        migration.enumerateObjects(ofType: snippetObjectName) { _, newObject in
            newObject?["identifier"] = NSUUID().uuidString
        }
    }
    if oldSchemaVersion <= 4 {
        migration.enumerateObjects(ofType: folderObjectName) { _, newObject in
            newObject?["identifier"] = NSUUID().uuidString
        }
    }
    if oldSchemaVersion <= 5 {
        migration.enumerateObjects(ofType: clipObjectName) { oldObject, newObject in
            newObject?["dataPath"] = oldObject?["dataPath"]
            newObject?["title"] = oldObject?["title"]
            newObject?["dataHash"] = oldObject?["dataHash"]
            newObject?["primaryType"] = oldObject?["primaryType"]
            newObject?["updateTime"] = oldObject?["updateTime"]
            newObject?["thumbnailPath"] = oldObject?["thumbnailPath"]
        }
        migration.enumerateObjects(ofType: snippetObjectName) { oldObject, newObject in
            newObject?["index"] = oldObject?["index"]
            newObject?["enable"] = oldObject?["enable"]
            newObject?["title"] = oldObject?["title"]
            newObject?["content"] = oldObject?["content"]
            if oldSchemaVersion >= 3 {
                newObject?["identifier"] = oldObject?["identifier"]
            }
        }
        migration.enumerateObjects(ofType: folderObjectName) { oldObject, newObject in
            newObject?["index"] = oldObject?["index"]
            newObject?["enable"] = oldObject?["enable"]
            newObject?["title"] = oldObject?["title"]
            if oldSchemaVersion >= 5 {
                newObject?["identifier"] = oldObject?["identifier"]
            }
        }
    }
    if oldSchemaVersion < 8 {
        migration.enumerateObjects(ofType: clipObjectName) { oldObject, newObject in
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
}

extension Realm {
    static func migration() {
        if isRunningBoardManTests {
            Realm.Configuration.defaultConfiguration = Realm.Configuration(
                inMemoryIdentifier: "BoardManTests-\(ProcessInfo.processInfo.processIdentifier)"
            )
            return
        }

        let config = Realm.Configuration(
            schemaVersion: LegacySnippetMigrationService.schemaVersion,
            migrationBlock: applyBoardManMigration
        )
        Realm.Configuration.defaultConfiguration = config

        let realm = try! Realm()
        let snippetResult = LegacySnippetMigrationService.migrateIfNeeded(into: realm)
        LegacySnippetMigrationService.publishDiagnostic(snippetResult)
        let historyResult = LegacyHistoryRecoveryService.migrateIfNeeded(into: realm)
        LegacyHistoryRecoveryService.publishDiagnostic(historyResult, destination: realm)
    }
}

enum LegacyRecoverySupport {
    static func withMigratedRealm<T>(at sourceURL: URL, body: (Realm) throws -> T) throws -> T {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BoardMan-LegacyRecovery-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let temporaryURL = temporaryDirectory.appendingPathComponent("default.realm")
        try fileManager.copyItem(at: sourceURL, to: temporaryURL)

        var configuration = Realm.Configuration(fileURL: temporaryURL)
        configuration.schemaVersion = LegacySnippetMigrationService.schemaVersion
        configuration.migrationBlock = applyBoardManMigration
        let realm = try Realm(configuration: configuration)
        defer {
            realm.invalidate()
            _ = try? Realm.deleteFiles(for: configuration)
            try? fileManager.removeItem(at: temporaryDirectory)
        }
        return try body(realm)
    }

    static func modificationDate(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    static func createBackup(of realm: Realm, in directoryURL: URL, prefix: String) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let backupURL = directoryURL.appendingPathComponent(
            "\(prefix)-\(formatter.string(from: Date()))-\(UUID().uuidString).realm"
        )
        try realm.writeCopy(toFile: backupURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
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

        let existingSnippetIdentifiers = Set(destination.objects(BoardManSnippet.self).map(\.identifier))
        let missingSnippetSnapshots = source.snippets.filter {
            !existingSnippetIdentifiers.contains($0.identifier)
        }
        let folderChangeCount = source.folders.reduce(into: 0) { count, snapshot in
            guard let existingFolder = destination.object(
                ofType: BoardManFolder.self,
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
            try LegacyRecoverySupport.createBackup(
                of: destination,
                in: backupDirectoryURL,
                prefix: "before-snippet-recovery"
            )
            try destination.write {
                for snapshot in missingSnippetSnapshots {
                    let snippet = BoardManSnippet()
                    snippet.index = snapshot.index
                    snippet.enable = snapshot.enable
                    snippet.title = snapshot.title
                    snippet.content = snapshot.content
                    snippet.identifier = snapshot.identifier
                    destination.add(snippet)
                }

                for snapshot in source.folders {
                    let folder: BoardManFolder
                    if let existingFolder = destination.object(
                        ofType: BoardManFolder.self,
                        forPrimaryKey: snapshot.identifier
                    ) {
                        folder = existingFolder
                    } else {
                        let newFolder = BoardManFolder()
                        newFolder.index = snapshot.index
                        newFolder.enable = snapshot.enable
                        newFolder.title = snapshot.title
                        newFolder.identifier = snapshot.identifier
                        destination.add(newFolder)
                        folder = newFolder
                    }

                    var linkedIdentifiers = Set(folder.snippets.map(\.identifier))
                    for identifier in snapshot.snippetIdentifiers where !linkedIdentifiers.contains(identifier) {
                        if let snippet = destination.object(ofType: BoardManSnippet.self, forPrimaryKey: identifier) {
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
        return try LegacyRecoverySupport.withMigratedRealm(at: sourceURL) { source in
            let snippets = Array(source.objects(BoardManSnippet.self).map {
                SnippetSnapshot(
                    index: $0.index,
                    enable: $0.enable,
                    title: $0.title,
                    content: $0.content,
                    identifier: $0.identifier
                )
            })
            let folders = Array(source.objects(BoardManFolder.self).map {
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
                modificationDate: LegacyRecoverySupport.modificationDate(of: sourceURL),
                snippets: snippets,
                folders: folders
            )
        }
    }

    static func defaultCandidateURLs(fileManager: FileManager = .default) -> [URL] {
        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return []
        }
        return [
            "com.uniplanck.BoardMan2",
            "com.uniplanck.BoardManDogfood"
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
}

enum LegacyHistoryRecoveryResult: Equatable {
    case skippedExistingData
    case noRecoverableSource
    case unsupportedOnly(sourceDirectory: String, skippedCount: Int)
    case restored(sourceDirectory: String, historyCount: Int, skippedCount: Int)
    case failed
}

enum LegacyHistoryRecoveryService {
    private struct HistorySnapshot {
        let dataPath: String
        let title: String
        let dataHash: String
        let primaryType: String
        let createdTime: Int
        let updateTime: Int
        let isColorCode: Bool
    }

    private struct SourceSnapshot {
        let url: URL
        let modificationDate: Date
        let clips: [HistorySnapshot]
    }

    static func migrateIfNeeded(
        into destination: Realm,
        candidateURLs: [URL] = LegacySnippetMigrationService.defaultCandidateURLs(),
        backupDirectoryURL: URL = LegacySnippetMigrationService.defaultBackupDirectoryURL(),
        dataDirectoryURL: URL = URL(fileURLWithPath: BoardManRuntimeSupport.applicationSupportFolder(), isDirectory: true)
    ) -> LegacyHistoryRecoveryResult {
        let destinationURL = destination.configuration.fileURL?.standardizedFileURL
        let snapshots = candidateURLs
            .filter { $0.standardizedFileURL != destinationURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .compactMap { try? sourceSnapshot(at: $0) }
            .filter { !$0.clips.isEmpty }
        guard let source = snapshots.max(by: { lhs, rhs in
            if lhs.clips.count == rhs.clips.count {
                return lhs.modificationDate < rhs.modificationDate
            }
            return lhs.clips.count < rhs.clips.count
        }) else {
            return .noRecoverableSource
        }

        let existingIdentifiers = Set(destination.objects(BoardManClip.self).map(\.dataHash))
        let missing = source.clips.filter { !existingIdentifiers.contains($0.dataHash) }
        guard !missing.isEmpty else { return .skippedExistingData }

        let recoverable = missing.filter { snapshot in
            FileManager.default.fileExists(atPath: snapshot.dataPath) || isRecoverableText(snapshot)
        }
        let unsupportedCount = missing.count - recoverable.count
        guard !recoverable.isEmpty else {
            return .unsupportedOnly(
                sourceDirectory: source.url.deletingLastPathComponent().lastPathComponent,
                skippedCount: unsupportedCount
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: dataDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            var prepared: [(snapshot: HistorySnapshot, path: String)] = []
            var didCommit = false
            defer {
                if !didCommit {
                    prepared.forEach { try? FileManager.default.removeItem(atPath: $0.path) }
                }
            }
            for snapshot in recoverable {
                let destinationPath = dataDirectoryURL
                    .appendingPathComponent("\(UUID().uuidString).data")
                    .path
                if prepareArchive(for: snapshot, destinationPath: destinationPath) {
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o600],
                        ofItemAtPath: destinationPath
                    )
                    prepared.append((snapshot, destinationPath))
                }
            }
            guard !prepared.isEmpty else {
                return .unsupportedOnly(
                    sourceDirectory: source.url.deletingLastPathComponent().lastPathComponent,
                    skippedCount: missing.count
                )
            }

            try LegacyRecoverySupport.createBackup(
                of: destination,
                in: backupDirectoryURL,
                prefix: "before-history-recovery"
            )
            try destination.write {
                for preparedClip in prepared {
                    let snapshot = preparedClip.snapshot
                    let clip = BoardManClip()
                    clip.dataPath = preparedClip.path
                    clip.title = snapshot.title
                    clip.dataHash = snapshot.dataHash.isEmpty ? UUID().uuidString : snapshot.dataHash
                    clip.primaryType = snapshot.primaryType
                    clip.createdTime = snapshot.createdTime > 0
                        ? snapshot.createdTime
                        : snapshot.updateTime * 1000
                    clip.updateTime = snapshot.updateTime
                    clip.thumbnailPath = ""
                    clip.isColorCode = snapshot.isColorCode
                    destination.add(clip)
                }
            }
            didCommit = true

            return .restored(
                sourceDirectory: source.url.deletingLastPathComponent().lastPathComponent,
                historyCount: prepared.count,
                skippedCount: unsupportedCount + recoverable.count - prepared.count
            )
        } catch {
            return .failed
        }
    }

    static func publishDiagnostic(
        _ result: LegacyHistoryRecoveryResult,
        destination: Realm,
        defaults: UserDefaults = .standard
    ) {
        switch result {
        case .skippedExistingData:
            if defaults.string(forKey: "BoardManLegacyHistoryRecoveryStatus") == nil {
                defaults.set("skippedExistingData", forKey: "BoardManLegacyHistoryRecoveryStatus")
            }
        case .noRecoverableSource:
            if defaults.string(forKey: "BoardManLegacyHistoryRecoveryStatus") == nil {
                defaults.set("noRecoverableSource", forKey: "BoardManLegacyHistoryRecoveryStatus")
            }
        case let .unsupportedOnly(sourceDirectory, skippedCount):
            if defaults.string(forKey: "BoardManLegacyHistoryRecoveryStatus") != "restored" {
                defaults.set("unsupportedOnly", forKey: "BoardManLegacyHistoryRecoveryStatus")
                defaults.set(sourceDirectory, forKey: "BoardManLegacyHistoryRecoverySource")
                defaults.set(skippedCount, forKey: "BoardManLegacyHistoryRecoverySkippedCount")
            }
        case let .restored(sourceDirectory, historyCount, skippedCount):
            defaults.set("restored", forKey: "BoardManLegacyHistoryRecoveryStatus")
            defaults.set(sourceDirectory, forKey: "BoardManLegacyHistoryRecoverySource")
            defaults.set(historyCount, forKey: "BoardManLegacyHistoryRecoveryCount")
            defaults.set(skippedCount, forKey: "BoardManLegacyHistoryRecoverySkippedCount")
            defaults.set(Date(), forKey: "BoardManLegacyHistoryRecoveryDate")
        case .failed:
            defaults.set("failed", forKey: "BoardManLegacyHistoryRecoveryStatus")
        }
        defaults.set(destination.objects(BoardManClip.self).count, forKey: "BoardManRecoveryDestinationClipCount")
        defaults.set(destination.objects(BoardManSnippet.self).count, forKey: "BoardManRecoveryDestinationSnippetCount")
        defaults.set(destination.objects(BoardManFolder.self).count, forKey: "BoardManRecoveryDestinationFolderCount")
    }

    private static func sourceSnapshot(at sourceURL: URL) throws -> SourceSnapshot {
        return try LegacyRecoverySupport.withMigratedRealm(at: sourceURL) { source in
            let clips = source.objects(BoardManClip.self).map {
                HistorySnapshot(
                    dataPath: $0.dataPath,
                    title: $0.title,
                    dataHash: $0.dataHash,
                    primaryType: $0.primaryType,
                    createdTime: $0.createdTime,
                    updateTime: $0.updateTime,
                    isColorCode: $0.isColorCode
                )
            }
            return SourceSnapshot(
                url: sourceURL,
                modificationDate: LegacyRecoverySupport.modificationDate(of: sourceURL),
                clips: Array(clips)
            )
        }
    }

    private static func isRecoverableText(_ snapshot: HistorySnapshot) -> Bool {
        let stringTypes: Set<String> = [
            NSPasteboard.PasteboardType.string.rawValue,
            NSPasteboard.PasteboardType.deprecatedString.rawValue,
            "NSStringPboardType"
        ]
        return stringTypes.contains(snapshot.primaryType) && !snapshot.title.isEmpty
    }

    private static func prepareArchive(for snapshot: HistorySnapshot, destinationPath: String) -> Bool {
        if !snapshot.dataPath.isEmpty,
           FileManager.default.fileExists(atPath: snapshot.dataPath) {
            do {
                try FileManager.default.copyItem(
                    atPath: snapshot.dataPath,
                    toPath: destinationPath
                )
                return true
            } catch {
                return false
            }
        }
        guard isRecoverableText(snapshot) else { return false }
        let pasteboardType = NSPasteboard.PasteboardType(rawValue: snapshot.primaryType)
        let data = BoardManClipData(string: snapshot.title, type: pasteboardType)
        return NSKeyedArchiver.archiveRootObject(data, toFile: destinationPath)
    }
}
