//
//  BoardManSQLiteMaintenance.swift
//  Board-Man
//
//  Integrity validation and backup/restore hardening for the authoritative SQLite store.
//

import Foundation
import GRDB

struct BoardManSQLiteIntegrityReport: Sendable, Equatable {
    let quickCheckMessages: [String]
    let foreignKeyViolationCount: Int

    var isHealthy: Bool {
        quickCheckMessages == ["ok"] && foreignKeyViolationCount == 0
    }
}

enum BoardManSQLiteMaintenanceError: Error, Equatable {
    case integrityCheckFailed(BoardManSQLiteIntegrityReport)
}

extension SQLiteBoardManStore {
    func integrityReport() throws -> BoardManSQLiteIntegrityReport {
        try Self.integrityReport(in: database)
    }

    func createBackup(at fileURL: URL, fileManager: FileManager = .default) throws {
        let sourceReport = try integrityReport()
        guard sourceReport.isHealthy else {
            throw BoardManSQLiteMaintenanceError.integrityCheckFailed(sourceReport)
        }
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
        let backupReport = try Self.integrityReport(in: backupDatabase)
        guard backupReport.isHealthy else {
            try? fileManager.removeItem(at: fileURL)
            throw BoardManSQLiteMaintenanceError.integrityCheckFailed(backupReport)
        }
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
        var sourceConfiguration = Configuration()
        sourceConfiguration.readonly = true
        let sourceDatabase = try DatabaseQueue(path: backupURL.path, configuration: sourceConfiguration)
        let sourceReport = try integrityReport(in: sourceDatabase)
        guard sourceReport.isHealthy else {
            throw BoardManSQLiteMaintenanceError.integrityCheckFailed(sourceReport)
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destinationDatabase = try DatabaseQueue(path: destinationURL.path)
        try sourceDatabase.backup(to: destinationDatabase)
        let destinationReport = try integrityReport(in: destinationDatabase)
        guard destinationReport.isHealthy else {
            try? fileManager.removeItem(at: destinationURL)
            throw BoardManSQLiteMaintenanceError.integrityCheckFailed(destinationReport)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
        return try SQLiteBoardManStore(fileURL: destinationURL)
    }

    private static func integrityReport(in database: any DatabaseReader) throws -> BoardManSQLiteIntegrityReport {
        try database.read { db in
            let quickCheckMessages = try String.fetchAll(db, sql: "PRAGMA quick_check")
            let foreignKeyViolationCount = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count
            return BoardManSQLiteIntegrityReport(
                quickCheckMessages: quickCheckMessages,
                foreignKeyViolationCount: foreignKeyViolationCount
            )
        }
    }
}
