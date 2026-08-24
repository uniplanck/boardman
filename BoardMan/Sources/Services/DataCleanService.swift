//
//  DataCleanService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/20.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RxSwift
import RealmSwift
import PINCache

struct ArchivedTextHistoryEntry: Codable, Equatable {
    let identifier: String
    let copiedAt: Date
    let content: String
}

enum BoardManHistoryRetentionPolicy {
    static func effectiveLimit(
        defaults: UserDefaults = AppEnvironment.current.defaults,
        entitlementLimit: Int? = nil
    ) -> Int? {
        let configuredLimit = max(1, defaults.integer(forKey: Constants.UserDefaults.maxHistorySize))
        guard let entitlementLimit, entitlementLimit > 0 else { return configuredLimit }
        return min(configuredLimit, entitlementLimit)
    }
}

final class TextHistoryArchiveStore {

    static let shared = TextHistoryArchiveStore()

    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL = TextHistoryArchiveStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    var archiveFileURL: URL {
        return fileURL
    }

    static func defaultFileURL(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directoryName = BoardManRuntimeEnvironment.isBenchmarkProfile(environment: environment)
            ? "Board-Man Benchmark Archive"
            : "Board-Man Archive"
        return applicationSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("Text History.jsonl", isDirectory: false)
    }

    @discardableResult
    func archive(_ clips: [BoardManClip]) -> Set<String> {
        let entries = clips.compactMap(Self.archiveEntry(for:))
        guard !entries.isEmpty else { return [] }
        do {
            try append(entries)
            return Set(entries.map(\.identifier))
        } catch {
            BoardManRuntimeSupport.sendDiagnosticLog("Text history archive write failed: \(error.localizedDescription)")
            return []
        }
    }

    func clipsSafeToRemove(_ clips: [BoardManClip]) -> [BoardManClip] {
        let archivedIdentifiers = archive(clips)
        return clips.filter { clip in
            clip.isBoardManImageHistory || archivedIdentifiers.contains(clip.dataHash)
        }
    }

    func ensureArchiveFileExists() throws {
        lock.lock(); defer { lock.unlock() }
        try prepareArchiveFile()
    }

    func readEntries() throws -> [ArchivedTextHistoryEntry] {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try contents
            .split(whereSeparator: \.isNewline)
            .map { try decoder.decode(ArchivedTextHistoryEntry.self, from: Data($0.utf8)) }
    }

    private func append(_ entries: [ArchivedTextHistoryEntry]) throws {
        lock.lock(); defer { lock.unlock() }
        try prepareArchiveFile()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var payload = Data()
        for entry in entries {
            payload.append(try encoder.encode(entry))
            payload.append(0x0A)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: payload)
    }

    private func prepareArchiveFile() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    private static func archiveEntry(for clip: BoardManClip) -> ArchivedTextHistoryEntry? {
        guard !clip.isBoardManImageHistory else { return nil }
        let content = archivedText(for: clip).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let unixTime = clip.updateTime > 0
            ? TimeInterval(clip.updateTime)
            : TimeInterval(clip.createdTime) / 1000
        return ArchivedTextHistoryEntry(
            identifier: clip.dataHash,
            copiedAt: Date(timeIntervalSince1970: max(0, unixTime)),
            content: content
        )
    }

    private static func archivedText(for clip: BoardManClip) -> String {
        if let data = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? BoardManClipData,
           !data.stringValue.isEmpty {
            return data.stringValue
        }
        return clip.title
    }
}

extension BoardManClip {
    var isBoardManImageHistory: Bool {
        let type = NSPasteboard.PasteboardType(rawValue: primaryType)
        return (!thumbnailPath.isEmpty && !isColorCode)
            || type == .png
            || type == .tiff
            || type == .deprecatedTIFF
    }

    var boardManRecoverableText: String? {
        let stringTypes: Set<String> = [
            NSPasteboard.PasteboardType.string.rawValue,
            NSPasteboard.PasteboardType.deprecatedString.rawValue,
            "NSStringPboardType"
        ]
        guard stringTypes.contains(primaryType), !title.isEmpty else { return nil }
        return title
    }
}

final class DataCleanService {

    // MARK: - Properties
    fileprivate var disposeBag = DisposeBag()
    fileprivate let scheduler = SerialDispatchQueueScheduler(qos: .utility)
    private let fileCleanupQueue = DispatchQueue(label: "com.uniplanck.BoardMan.DataCleanService.files", qos: .utility)

    // MARK: - Monitoring
    func startMonitoring() {
        disposeBag = DisposeBag()
        // Clean datas every 30 minutes
        Observable<Int>.interval(.seconds(60 * 30), scheduler: scheduler)
            .subscribe(onNext: { [weak self] _ in
                self?.cleanDatas()
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Delete Data
    func cleanDatas() {
        let realm = try! Realm()
        let overflowingClips = overflowingClips(with: realm)
        let removableClips = TextHistoryArchiveStore.shared.clipsSafeToRemove(overflowingClips)
        removableClips
            .filter { !$0.isInvalidated && !$0.thumbnailPath.isEmpty }
            .map { $0.thumbnailPath }
            .forEach { PINCache.shared.removeObject(forKey: $0) }
        let dataPaths = removableClips.filter { !$0.isInvalidated }.map(\.dataPath)
        let identifiers = removableClips.filter { !$0.isInvalidated }.map(\.dataHash)
        realm.transaction { realm.delete(removableClips.filter { !$0.isInvalidated }) }
        HistoryDisplayNameStore.shared.remove(identifiers)
        dataPaths.filter { !$0.isEmpty }.forEach { BoardManRuntimeSupport.deleteData(at: $0) }
        cleanFiles(with: realm)
    }

    private func overflowingClips(with realm: Realm) -> [BoardManClip] {
        let clips = Array(
            realm.objects(BoardManClip.self).sorted(byKeyPath: #keyPath(BoardManClip.updateTime), ascending: false)
        )
        guard let maxHistorySize = BoardManHistoryRetentionPolicy.effectiveLimit(),
              clips.count > maxHistorySize else { return [] }

        let removableIdentifiers = PinnedSnippetStore.shared.oldestUnpinnedIdentifiers(
            in: clips.map(\.dataHash),
            maximumCount: clips.count - maxHistorySize
        )
        return clips.filter { removableIdentifiers.contains($0.dataHash) }
    }

    private func cleanFiles(with realm: Realm) {
        let liveClipFileNames = Set(realm.objects(BoardManClip.self)
            .filter { !$0.isInvalidated }
            .compactMap { URL(fileURLWithPath: $0.dataPath).lastPathComponent })
        let applicationSupportFolder = BoardManRuntimeSupport.applicationSupportFolder()

        // File-system cleanup has no reason to block AppKit. Only Board-Man's archived
        // *.data payloads are eligible; unrelated support files are never touched.
        fileCleanupQueue.async {
            let fileManager = FileManager.default
            guard let paths = try? fileManager.contentsOfDirectory(atPath: applicationSupportFolder) else { return }
            paths
                .filter { $0.hasSuffix(".data") && !liveClipFileNames.contains($0) }
                .map { (applicationSupportFolder as NSString).appendingPathComponent($0) }
                .forEach { BoardManRuntimeSupport.deleteData(at: $0) }
        }
    }
}
