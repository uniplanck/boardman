//
//  BoardManRecoveryArchive.swift
//  Board-Man
//
//  Versioned, local-only recovery archive for authoritative SQLite metadata and payload files.
//

import CryptoKit
import Foundation
import GRDB

struct BoardManRecoveryArchiveManifest: Codable, Sendable, Equatable {
    struct Payload: Codable, Sendable, Equatable {
        let dataHash: String
        let relativePath: String?
        let byteCount: Int?
        let sha256: String?
    }

    let schemaVersion: Int
    let createdAt: Date
    let payloads: [Payload]
}

enum BoardManRecoveryArchiveError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case malformedManifest
    case unsafePayloadPath(String)
    case missingPayload(String)
    case payloadSizeMismatch(String)
    case payloadDigestMismatch(String)
    case historyManifestMismatch
}

enum BoardManRecoveryArchiveService {
    static let schemaVersion = 1
    private static let databaseFileName = "BoardMan.sqlite"
    private static let manifestFileName = "manifest.json"
    private static let payloadDirectoryName = "Payloads"

    static func createArchive(
        from store: SQLiteBoardManStore,
        at archiveURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !fileManager.fileExists(atPath: archiveURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let stagingURL = archiveURL.deletingLastPathComponent()
            .appendingPathComponent(".boardman-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingURL) }
        try fileManager.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        try store.createBackup(at: stagingURL.appendingPathComponent(databaseFileName))
        let payloadDirectoryURL = stagingURL.appendingPathComponent(payloadDirectoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: payloadDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let payloads = try store.clipsSortedByCreatedTimeDescending().map { clip in
            try archivePayload(for: clip, into: payloadDirectoryURL, fileManager: fileManager)
        }
        let manifest = BoardManRecoveryArchiveManifest(
            schemaVersion: schemaVersion,
            createdAt: Date(),
            payloads: payloads
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: stagingURL.appendingPathComponent(manifestFileName), options: .atomic)
        try fileManager.moveItem(at: stagingURL, to: archiveURL)
    }

    static func restoreArchive(
        from archiveURL: URL,
        to destinationRootURL: URL,
        fileManager: FileManager = .default
    ) throws -> SQLiteBoardManStore {
        guard !fileManager.fileExists(atPath: destinationRootURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let manifest = try readManifest(from: archiveURL)
        guard manifest.schemaVersion == schemaVersion else {
            throw BoardManRecoveryArchiveError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard Set(manifest.payloads.map(\.dataHash)).count == manifest.payloads.count else {
            throw BoardManRecoveryArchiveError.malformedManifest
        }

        let stagingURL = destinationRootURL.deletingLastPathComponent()
            .appendingPathComponent(".boardman-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingURL) }
        try fileManager.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let stagedPayloadDirectory = stagingURL.appendingPathComponent(payloadDirectoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: stagedPayloadDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var finalPayloadPaths = [String: String]()
        for payload in manifest.payloads {
            guard let relativePath = payload.relativePath else {
                finalPayloadPaths[payload.dataHash] = ""
                continue
            }
            try validateSafeRelativePayloadPath(relativePath)
            let sourceURL = archiveURL
                .appendingPathComponent(payloadDirectoryName, isDirectory: true)
                .appendingPathComponent(relativePath)
            try validatePayload(payload, at: sourceURL, fileManager: fileManager)
            let stagedURL = stagedPayloadDirectory.appendingPathComponent(relativePath)
            try fileManager.copyItem(at: sourceURL, to: stagedURL)
            try validatePayload(payload, at: stagedURL, fileManager: fileManager)
            finalPayloadPaths[payload.dataHash] = destinationRootURL
                .appendingPathComponent(payloadDirectoryName, isDirectory: true)
                .appendingPathComponent(relativePath).path
        }

        let sourceDatabaseURL = archiveURL.appendingPathComponent(databaseFileName)
        let stagedDatabaseURL = stagingURL.appendingPathComponent(databaseFileName)
        try prepareRestoredDatabase(
            from: sourceDatabaseURL,
            to: stagedDatabaseURL,
            manifest: manifest,
            finalPayloadPaths: finalPayloadPaths,
            fileManager: fileManager
        )
        try fileManager.moveItem(at: stagingURL, to: destinationRootURL)
        return try SQLiteBoardManStore(fileURL: destinationRootURL.appendingPathComponent(databaseFileName))
    }

    private static func archivePayload(
        for clip: BoardManClip,
        into payloadDirectoryURL: URL,
        fileManager: FileManager
    ) throws -> BoardManRecoveryArchiveManifest.Payload {
        guard !clip.dataPath.isEmpty, fileManager.fileExists(atPath: clip.dataPath) else {
            return .init(dataHash: clip.dataHash, relativePath: nil, byteCount: nil, sha256: nil)
        }
        let sourceURL = URL(fileURLWithPath: clip.dataPath)
        let relativePath = "\(UUID().uuidString).data"
        let destinationURL = payloadDirectoryURL.appendingPathComponent(relativePath)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        let byteCount = try fileSize(at: destinationURL, fileManager: fileManager)
        let sha256 = try digest(at: destinationURL)
        return .init(
            dataHash: clip.dataHash,
            relativePath: relativePath,
            byteCount: byteCount,
            sha256: sha256
        )
    }

    private static func prepareRestoredDatabase(
        from sourceURL: URL,
        to destinationURL: URL,
        manifest: BoardManRecoveryArchiveManifest,
        finalPayloadPaths: [String: String],
        fileManager: FileManager
    ) throws {
        let restored = try SQLiteBoardManStore.restoreBackup(
            from: sourceURL,
            to: destinationURL,
            fileManager: fileManager
        )
        try restored.database.write { database in
            let storedIdentifiers = Set(try String.fetchAll(database, sql: "SELECT dataHash FROM history_items"))
            let manifestIdentifiers = Set(manifest.payloads.map(\.dataHash))
            guard storedIdentifiers == manifestIdentifiers else {
                throw BoardManRecoveryArchiveError.historyManifestMismatch
            }
            for payload in manifest.payloads {
                try database.execute(
                    sql: "UPDATE history_items SET dataPath = ? WHERE dataHash = ?",
                    arguments: [finalPayloadPaths[payload.dataHash] ?? "", payload.dataHash]
                )
            }
        }
        let report = try restored.integrityReport()
        guard report.isHealthy else {
            throw BoardManSQLiteMaintenanceError.integrityCheckFailed(report)
        }
    }

    private static func readManifest(from archiveURL: URL) throws -> BoardManRecoveryArchiveManifest {
        do {
            let data = try Data(contentsOf: archiveURL.appendingPathComponent(manifestFileName))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(BoardManRecoveryArchiveManifest.self, from: data)
        } catch let error as BoardManRecoveryArchiveError {
            throw error
        } catch {
            throw BoardManRecoveryArchiveError.malformedManifest
        }
    }

    private static func validateSafeRelativePayloadPath(_ path: String) throws {
        guard !path.isEmpty,
              !path.contains("/"),
              !path.contains("\\"),
              path == URL(fileURLWithPath: path).lastPathComponent,
              URL(fileURLWithPath: path).pathExtension == "data" else {
            throw BoardManRecoveryArchiveError.unsafePayloadPath(path)
        }
    }

    private static func validatePayload(
        _ payload: BoardManRecoveryArchiveManifest.Payload,
        at url: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw BoardManRecoveryArchiveError.missingPayload(payload.relativePath ?? "")
        }
        if let expectedCount = payload.byteCount,
           try fileSize(at: url, fileManager: fileManager) != expectedCount {
            throw BoardManRecoveryArchiveError.payloadSizeMismatch(payload.relativePath ?? "")
        }
        if let expectedDigest = payload.sha256,
           try digest(at: url) != expectedDigest {
            throw BoardManRecoveryArchiveError.payloadDigestMismatch(payload.relativePath ?? "")
        }
    }

    private static func fileSize(at url: URL, fileManager: FileManager) throws -> Int {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    private static func digest(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
