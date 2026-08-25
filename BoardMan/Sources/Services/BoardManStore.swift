//
//  BoardManStore.swift
//  Board-Man
//
//  Persistence boundary introduced during the Realm -> SQLiteData migration.
//

import Foundation
import RealmSwift

struct BoardManClipSnapshot: Sendable, Equatable {
    let dataPath: String
    let title: String
    let dataHash: String
    let primaryType: String
    let createdTime: Int
    let updateTime: Int
    let thumbnailPath: String
    let isColorCode: Bool

    init(_ clip: BoardManClip) {
        dataPath = clip.dataPath
        title = clip.title
        dataHash = clip.dataHash
        primaryType = clip.primaryType
        createdTime = clip.createdTime
        updateTime = clip.updateTime
        thumbnailPath = clip.thumbnailPath
        isColorCode = clip.isColorCode
    }

    func makeClip() -> BoardManClip {
        let clip = BoardManClip()
        clip.dataPath = dataPath
        clip.title = title
        clip.dataHash = dataHash
        clip.primaryType = primaryType
        clip.createdTime = createdTime
        clip.updateTime = updateTime
        clip.thumbnailPath = thumbnailPath
        clip.isColorCode = isColorCode
        return clip
    }
}

struct BoardManHistorySearchMetadata: Sendable, Equatable {
    let text: String
    let filePaths: [String]
    let urls: [String]
    let sourceApplicationName: String
    let sourceApplicationBundleID: String

    init(
        text: String = "",
        filePaths: [String] = [],
        urls: [String] = [],
        sourceApplicationName: String = "",
        sourceApplicationBundleID: String = ""
    ) {
        self.text = text
        self.filePaths = filePaths
        self.urls = urls
        self.sourceApplicationName = sourceApplicationName
        self.sourceApplicationBundleID = sourceApplicationBundleID
    }

    var filePathsSearchText: String { filePaths.joined(separator: "\n") }
    var urlsSearchText: String { urls.joined(separator: "\n") }

    static func make(
        from data: BoardManClipData,
        sourceApplication: (name: String, bundleIdentifier: String)? = nil
    ) -> BoardManHistorySearchMetadata {
        let fullText = String(data.boardManTextValue.prefix(100_000))
        return BoardManHistorySearchMetadata(
            text: fullText,
            filePaths: Array(data.fileNames.prefix(256)).map { String($0.prefix(4_096)) },
            urls: Array(data.URLs.prefix(256)).map { String($0.prefix(4_096)) },
            sourceApplicationName: sourceApplication?.name ?? "",
            sourceApplicationBundleID: sourceApplication?.bundleIdentifier ?? ""
        )
    }
}

enum BoardManSearchSource: String, Sendable, Hashable {
    case history
    case snippet
}

enum BoardManSearchScope: Sendable, Equatable {
    case all
    case history
    case snippets
}

enum BoardManSearchItemType: String, Sendable, Hashable, CaseIterable {
    case text
    case image
    case url
    case file

    func matches(primaryType: String) -> Bool {
        let value = primaryType.lowercased()
        switch self {
        case .text:
            return value.contains("text") || value.contains("string") || value.contains("rtf") || value.contains("html")
        case .image:
            return value.contains("image") || value.contains("png") || value.contains("tiff")
                || value.contains("jpeg") || value.contains("jpg") || value.contains("gif") || value.contains("bmp")
        case .url:
            return value.contains("url") && !value.contains("file")
        case .file:
            return value.contains("file-url") || value.contains("filenames")
        }
    }
}

struct BoardManSearchRequest: Sendable, Equatable {
    let text: String
    let scope: BoardManSearchScope
    let itemTypes: Set<BoardManSearchItemType>
    let sourceApplication: String?
    let copiedAfterMilliseconds: Int?
    let copiedBeforeMilliseconds: Int?

    init(
        text: String,
        scope: BoardManSearchScope,
        itemTypes: Set<BoardManSearchItemType> = [],
        sourceApplication: String? = nil,
        copiedAfterMilliseconds: Int? = nil,
        copiedBeforeMilliseconds: Int? = nil
    ) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scope = scope
        self.itemTypes = itemTypes
        self.sourceApplication = sourceApplication?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.copiedAfterMilliseconds = copiedAfterMilliseconds
        self.copiedBeforeMilliseconds = copiedBeforeMilliseconds
    }

    var hasStoreFilters: Bool {
        !itemTypes.isEmpty || sourceApplication != nil
            || copiedAfterMilliseconds != nil || copiedBeforeMilliseconds != nil
    }
}

struct BoardManParsedSearchQuery: Sendable, Equatable {
    let request: BoardManSearchRequest
    let pinnedOnly: Bool
}

enum BoardManSearchQueryParser {
    static func parse(_ rawQuery: String, defaultScope: BoardManSearchScope) -> BoardManParsedSearchQuery {
        var scope = defaultScope
        var itemTypes = Set<BoardManSearchItemType>()
        var sourceApplication: String?
        var copiedAfterMilliseconds: Int?
        var copiedBeforeMilliseconds: Int?
        var pinnedOnly = false
        var textTokens = [String]()

        for token in tokenize(rawQuery) {
            let lowercased = token.lowercased()
            if lowercased == "is:pinned" {
                pinnedOnly = true
                continue
            }
            if let value = value(after: "in:", in: token) {
                switch value.lowercased() {
                case "history": scope = .history
                case "template", "templates", "snippet", "snippets": scope = .snippets
                case "all": scope = .all
                default: textTokens.append(token)
                }
                continue
            }
            if let value = value(after: "type:", in: token),
               let itemType = BoardManSearchItemType(rawValue: value.lowercased()) {
                itemTypes.insert(itemType)
                continue
            }
            if let value = value(after: "app:", in: token), !value.isEmpty {
                sourceApplication = value
                continue
            }
            if let value = value(after: "after:", in: token),
               let milliseconds = startOfDayMilliseconds(value) {
                copiedAfterMilliseconds = milliseconds
                continue
            }
            if let value = value(after: "before:", in: token),
               let milliseconds = startOfDayMilliseconds(value) {
                copiedBeforeMilliseconds = milliseconds
                continue
            }
            textTokens.append(token)
        }

        return BoardManParsedSearchQuery(
            request: BoardManSearchRequest(
                text: textTokens.joined(separator: " "),
                scope: scope,
                itemTypes: itemTypes,
                sourceApplication: sourceApplication,
                copiedAfterMilliseconds: copiedAfterMilliseconds,
                copiedBeforeMilliseconds: copiedBeforeMilliseconds
            ),
            pinnedOnly: pinnedOnly
        )
    }

    private static func value(after prefix: String, in token: String) -> String? {
        guard token.count > prefix.count,
              token.lowercased().hasPrefix(prefix) else { return nil }
        return String(token.dropFirst(prefix.count))
    }

    private static func tokenize(_ rawQuery: String) -> [String] {
        var tokens = [String]()
        var current = ""
        var isQuoted = false
        for character in rawQuery {
            if character == "\"" {
                isQuoted.toggle()
                continue
            }
            if character.isWhitespace && !isQuoted {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func startOfDayMilliseconds(_ value: String) -> Int? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return nil
        }
        return Int(date.timeIntervalSince1970 * 1_000)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct BoardManSearchHit: Sendable, Equatable {
    let identifier: String
    let source: BoardManSearchSource
    let matchClass: Int
    let relevance: Double
}

struct BoardManSearchRankCandidate: Sendable, Equatable {
    let hit: BoardManSearchHit
    let isPinned: Bool
    let usageCount: Int
    let baseOrder: Int
}

enum BoardManSearchMatcher {
    static func matchClass(query: String, fields: [String]) -> Int? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return nil }
        let normalizedFields = fields.map { $0.lowercased() }
        if normalizedFields.contains(normalizedQuery) { return 0 }
        if normalizedFields.contains(where: { $0.hasPrefix(normalizedQuery) }) { return 1 }
        if normalizedFields.contains(where: { $0.contains(normalizedQuery) }) { return 2 }
        return nil
    }
}

enum BoardManSearchRanker {
    static func rank(_ candidates: [BoardManSearchRankCandidate]) -> [BoardManSearchHit] {
        candidates.sorted { lhs, rhs in
            if lhs.hit.matchClass != rhs.hit.matchClass {
                return lhs.hit.matchClass < rhs.hit.matchClass
            }
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.usageCount != rhs.usageCount {
                return lhs.usageCount > rhs.usageCount
            }
            if lhs.baseOrder != rhs.baseOrder {
                return lhs.baseOrder < rhs.baseOrder
            }
            if lhs.hit.relevance != rhs.hit.relevance {
                return lhs.hit.relevance < rhs.hit.relevance
            }
            if lhs.hit.source != rhs.hit.source {
                return lhs.hit.source.rawValue < rhs.hit.source.rawValue
            }
            return lhs.hit.identifier < rhs.hit.identifier
        }
        .map(\.hit)
    }
}

extension Notification.Name {
    static let boardManHistoryStoreDidChange = Notification.Name("BoardManHistoryStoreDidChange")
    static let boardManTemplatesStoreDidChange = Notification.Name("BoardManTemplatesStoreDidChange")
}

protocol BoardManStore: AnyObject {
    var hasClips: Bool { get }

    func clip(identifier: String) -> BoardManClip?
    func clipsSortedByUpdateTimeDescending() -> [BoardManClip]
    func clipsSortedByCreatedTimeDescending() -> [BoardManClip]
    func latestClip(title: String, primaryTypes: [String]) -> BoardManClip?
    func search(_ request: BoardManSearchRequest, limit: Int) -> [BoardManSearchHit]
    func historyClipsMissingSearchMetadata(limit: Int) -> [BoardManClip]
    func upsertHistorySearchMetadata(identifier: String, metadata: BoardManHistorySearchMetadata)
    @discardableResult func updateClipUsage(identifier: String, updateTime: Int) -> Bool
    func upsertClip(_ clip: BoardManClip)
    func deleteClip(identifier: String)
    func deleteClips(identifiers: Set<String>)

    func folder(identifier: String) -> BoardManFolder?
    func foldersSortedByIndex() -> [BoardManFolder]
    func snippet(identifier: String) -> BoardManSnippet?
    func snippetsSortedByIndex() -> [BoardManSnippet]
    func uncategorizedSnippetsSortedByIndex() -> [BoardManSnippet]
    func folderIdentifier(forSnippetIdentifier identifier: String) -> String?
    func upsertFolder(_ folder: BoardManFolder)
    func deleteFolder(identifier: String)
    func upsertSnippet(_ snippet: BoardManSnippet, folderIdentifier: String?)
    func deleteSnippet(identifier: String)
    func moveSnippet(identifier: String, toFolderIdentifier: String?, index: Int)
    func reorderFolders(_ identifiers: [String])
    func reorderSnippets(_ identifiers: [String], folderIdentifier: String?)
}

final class BoardManStoreRouter: BoardManStore {
    private let lock = NSLock()
    private var backend: BoardManStore

    init(initialBackend: BoardManStore) {
        backend = initialBackend
    }

    func replaceBackend(with backend: BoardManStore) {
        lock.lock()
        self.backend = backend
        lock.unlock()
        NotificationCenter.default.post(name: .boardManHistoryStoreDidChange, object: self)
        NotificationCenter.default.post(name: .boardManTemplatesStoreDidChange, object: self)
    }

    var hasClips: Bool {
        currentBackend().hasClips
    }

    func clip(identifier: String) -> BoardManClip? {
        currentBackend().clip(identifier: identifier)
    }

    func clipsSortedByUpdateTimeDescending() -> [BoardManClip] {
        currentBackend().clipsSortedByUpdateTimeDescending()
    }

    func clipsSortedByCreatedTimeDescending() -> [BoardManClip] {
        currentBackend().clipsSortedByCreatedTimeDescending()
    }

    func latestClip(title: String, primaryTypes: [String]) -> BoardManClip? {
        currentBackend().latestClip(title: title, primaryTypes: primaryTypes)
    }

    func search(_ request: BoardManSearchRequest, limit: Int) -> [BoardManSearchHit] {
        currentBackend().search(request, limit: limit)
    }

    func historyClipsMissingSearchMetadata(limit: Int) -> [BoardManClip] {
        currentBackend().historyClipsMissingSearchMetadata(limit: limit)
    }

    func upsertHistorySearchMetadata(identifier: String, metadata: BoardManHistorySearchMetadata) {
        currentBackend().upsertHistorySearchMetadata(identifier: identifier, metadata: metadata)
    }

    @discardableResult
    func updateClipUsage(identifier: String, updateTime: Int) -> Bool {
        let changed = currentBackend().updateClipUsage(identifier: identifier, updateTime: updateTime)
        if changed {
            postHistoryDidChange()
        }
        return changed
    }

    func upsertClip(_ clip: BoardManClip) {
        currentBackend().upsertClip(clip)
        postHistoryDidChange()
    }

    func deleteClip(identifier: String) {
        currentBackend().deleteClip(identifier: identifier)
        postHistoryDidChange()
    }

    func deleteClips(identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }
        currentBackend().deleteClips(identifiers: identifiers)
        postHistoryDidChange()
    }

    func folder(identifier: String) -> BoardManFolder? {
        currentBackend().folder(identifier: identifier)
    }

    func foldersSortedByIndex() -> [BoardManFolder] {
        currentBackend().foldersSortedByIndex()
    }

    func snippet(identifier: String) -> BoardManSnippet? {
        currentBackend().snippet(identifier: identifier)
    }

    func snippetsSortedByIndex() -> [BoardManSnippet] {
        currentBackend().snippetsSortedByIndex()
    }

    func uncategorizedSnippetsSortedByIndex() -> [BoardManSnippet] {
        currentBackend().uncategorizedSnippetsSortedByIndex()
    }

    func folderIdentifier(forSnippetIdentifier identifier: String) -> String? {
        currentBackend().folderIdentifier(forSnippetIdentifier: identifier)
    }

    func upsertFolder(_ folder: BoardManFolder) {
        currentBackend().upsertFolder(folder)
        postTemplatesDidChange()
    }

    func deleteFolder(identifier: String) {
        currentBackend().deleteFolder(identifier: identifier)
        postTemplatesDidChange()
    }

    func upsertSnippet(_ snippet: BoardManSnippet, folderIdentifier: String?) {
        currentBackend().upsertSnippet(snippet, folderIdentifier: folderIdentifier)
        postTemplatesDidChange()
    }

    func deleteSnippet(identifier: String) {
        currentBackend().deleteSnippet(identifier: identifier)
        postTemplatesDidChange()
    }

    func moveSnippet(identifier: String, toFolderIdentifier: String?, index: Int) {
        currentBackend().moveSnippet(identifier: identifier, toFolderIdentifier: toFolderIdentifier, index: index)
        postTemplatesDidChange()
    }

    func reorderFolders(_ identifiers: [String]) {
        currentBackend().reorderFolders(identifiers)
        postTemplatesDidChange()
    }

    func reorderSnippets(_ identifiers: [String], folderIdentifier: String?) {
        currentBackend().reorderSnippets(identifiers, folderIdentifier: folderIdentifier)
        postTemplatesDidChange()
    }

    private func currentBackend() -> BoardManStore {
        lock.lock()
        defer { lock.unlock() }
        return backend
    }

    private func postHistoryDidChange() {
        NotificationCenter.default.post(name: .boardManHistoryStoreDidChange, object: self)
    }

    private func postTemplatesDidChange() {
        NotificationCenter.default.post(name: .boardManTemplatesStoreDidChange, object: self)
    }
}

enum BoardManStores {
    static let authoritative = BoardManStoreRouter(initialBackend: RealmBoardManStore.shared)

    @discardableResult
    static func useSQLiteHistory(at fileURL: URL) throws -> SQLiteBoardManStore {
        let store = try SQLiteBoardManStore(fileURL: fileURL)
        authoritative.replaceBackend(with: store)
        return store
    }

    static func useRealmHistory() {
        authoritative.replaceBackend(with: RealmBoardManStore.shared)
    }
}

enum BoardManHistorySearchMetadataBackfiller {
    static let defaultBatchSize = 50

    private static let queue = DispatchQueue(
        label: "com.uniplanck.BoardMan.HistorySearchMetadataBackfill",
        qos: .utility
    )

    static func start(
        store: BoardManStore = BoardManStores.authoritative,
        batchSize: Int = defaultBatchSize
    ) {
        guard batchSize > 0 else { return }
        scheduleNextBatch(store: store, batchSize: batchSize)
    }

    @discardableResult
    static func backfillNextBatch(store: BoardManStore, batchSize: Int = defaultBatchSize) -> Int {
        guard batchSize > 0 else { return 0 }
        let clips = store.historyClipsMissingSearchMetadata(limit: batchSize)
        for clip in clips {
            let metadata: BoardManHistorySearchMetadata
            if let data = archivedClipData(at: clip.dataPath) {
                metadata = .make(from: data)
            } else {
                // Mark unreadable/missing legacy payloads as processed so the backfill is bounded.
                metadata = BoardManHistorySearchMetadata()
            }
            store.upsertHistorySearchMetadata(identifier: clip.dataHash, metadata: metadata)
        }
        return clips.count
    }

    private static func archivedClipData(at path: String) -> BoardManClipData? {
        guard let archiveData = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archiveData) else {
            return nil
        }
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? BoardManClipData
    }

    private static func scheduleNextBatch(store: BoardManStore, batchSize: Int) {
        queue.async {
            let processed = autoreleasepool {
                backfillNextBatch(store: store, batchSize: batchSize)
            }
            guard processed == batchSize else { return }
            queue.asyncAfter(deadline: .now() + .milliseconds(10)) {
                scheduleNextBatch(store: store, batchSize: batchSize)
            }
        }
    }
}

extension BoardManStore {
    func historyClipsMissingSearchMetadata(limit: Int) -> [BoardManClip] {
        return []
    }

    func upsertHistorySearchMetadata(identifier: String, metadata: BoardManHistorySearchMetadata) {
        // The legacy compatibility backend has no supplemental search metadata table.
    }

    func search(_ query: String, scope: BoardManSearchScope, limit: Int) -> [BoardManSearchHit] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return search(BoardManSearchRequest(text: query, scope: scope), limit: limit)
    }

    func search(_ request: BoardManSearchRequest, limit: Int) -> [BoardManSearchHit] {
        let normalizedQuery = request.text.lowercased()
        guard limit > 0 else { return [] }

        var candidates: [(hit: BoardManSearchHit, order: Int)] = []
        var order = 0

        if request.scope != .snippets, request.sourceApplication == nil {
            for clip in clipsSortedByUpdateTimeDescending() {
                if !request.itemTypes.isEmpty,
                   !request.itemTypes.contains(where: { $0.matches(primaryType: clip.primaryType) }) {
                    continue
                }
                if let after = request.copiedAfterMilliseconds, clip.createdTime < after { continue }
                if let before = request.copiedBeforeMilliseconds, clip.createdTime >= before { continue }
                let matchClass: Int
                if normalizedQuery.isEmpty {
                    matchClass = 2
                } else if let matched = BoardManSearchMatcher.matchClass(
                    query: normalizedQuery,
                    fields: [clip.title, clip.primaryType]
                ) {
                    matchClass = matched
                } else {
                    continue
                }
                candidates.append((
                    BoardManSearchHit(
                        identifier: clip.dataHash,
                        source: .history,
                        matchClass: matchClass,
                        relevance: Double(matchClass)
                    ),
                    order
                ))
                order += 1
            }
        }

        let hasHistoryOnlyFilters = !request.itemTypes.isEmpty || request.sourceApplication != nil
            || request.copiedAfterMilliseconds != nil || request.copiedBeforeMilliseconds != nil
        if request.scope != .history, !hasHistoryOnlyFilters {
            let folders = foldersSortedByIndex()
            var groupedIdentifiers = Set<String>()
            for folder in folders {
                for snippet in folder.snippets {
                    groupedIdentifiers.insert(snippet.identifier)
                    let matchClass: Int
                    if normalizedQuery.isEmpty {
                        matchClass = 2
                    } else if let matched = BoardManSearchMatcher.matchClass(
                        query: normalizedQuery,
                        fields: [snippet.title, snippet.content, folder.title]
                    ) {
                        matchClass = matched
                    } else {
                        continue
                    }
                    candidates.append((
                        BoardManSearchHit(
                            identifier: snippet.identifier,
                            source: .snippet,
                            matchClass: matchClass,
                            relevance: Double(matchClass)
                        ),
                        order
                    ))
                    order += 1
                }
            }
            for snippet in uncategorizedSnippetsSortedByIndex() where !groupedIdentifiers.contains(snippet.identifier) {
                let matchClass: Int
                if normalizedQuery.isEmpty {
                    matchClass = 2
                } else if let matched = BoardManSearchMatcher.matchClass(
                    query: normalizedQuery,
                    fields: [snippet.title, snippet.content, "Uncategorized"]
                ) {
                    matchClass = matched
                } else {
                    continue
                }
                candidates.append((
                    BoardManSearchHit(
                        identifier: snippet.identifier,
                        source: .snippet,
                        matchClass: matchClass,
                        relevance: Double(matchClass)
                    ),
                    order
                ))
                order += 1
            }
        }

        return candidates
            .sorted {
                if $0.hit.matchClass != $1.hit.matchClass {
                    return $0.hit.matchClass < $1.hit.matchClass
                }
                return $0.order < $1.order
            }
            .prefix(limit)
            .map(\.hit)
    }
}

final class RealmBoardManStore: BoardManStore {
    static let shared = RealmBoardManStore()

    private init() {}

    private func postHistoryDidChange() {
        NotificationCenter.default.post(name: .boardManHistoryStoreDidChange, object: self)
    }

    var hasClips: Bool {
        let realm = try! Realm()
        return !realm.objects(BoardManClip.self).isEmpty
    }

    func clip(identifier: String) -> BoardManClip? {
        let realm = try! Realm()
        guard let clip = realm.object(ofType: BoardManClip.self, forPrimaryKey: identifier) else {
            return nil
        }
        return BoardManClipSnapshot(clip).makeClip()
    }

    func clipsSortedByUpdateTimeDescending() -> [BoardManClip] {
        let realm = try! Realm()
        return realm.objects(BoardManClip.self)
            .sorted(byKeyPath: #keyPath(BoardManClip.updateTime), ascending: false)
            .map { BoardManClipSnapshot($0).makeClip() }
    }

    func clipsSortedByCreatedTimeDescending() -> [BoardManClip] {
        let realm = try! Realm()
        return realm.objects(BoardManClip.self)
            .sorted(byKeyPath: #keyPath(BoardManClip.createdTime), ascending: false)
            .map { BoardManClipSnapshot($0).makeClip() }
    }

    func latestClip(title: String, primaryTypes: [String]) -> BoardManClip? {
        guard !primaryTypes.isEmpty else { return nil }
        let realm = try! Realm()
        guard let clip = realm.objects(BoardManClip.self)
            .filter("title == %@ AND primaryType IN %@", title, primaryTypes)
            .sorted(byKeyPath: #keyPath(BoardManClip.updateTime), ascending: false)
            .first else {
            return nil
        }
        return BoardManClipSnapshot(clip).makeClip()
    }

    @discardableResult
    func updateClipUsage(identifier: String, updateTime: Int) -> Bool {
        let realm = try! Realm()
        guard let clip = realm.object(ofType: BoardManClip.self, forPrimaryKey: identifier) else {
            return false
        }
        do {
            try realm.write {
                clip.updateTime = updateTime
            }
            postHistoryDidChange()
            return true
        } catch {
            return false
        }
    }

    func upsertClip(_ clip: BoardManClip) {
        let realm = try! Realm()
        let storedClip = BoardManClipSnapshot(clip).makeClip()
        realm.transaction {
            realm.add(storedClip, update: .all)
        }
        postHistoryDidChange()
    }

    func deleteClip(identifier: String) {
        deleteClips(identifiers: [identifier])
    }

    func deleteClips(identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }
        let realm = try! Realm()
        let clips = realm.objects(BoardManClip.self).filter("dataHash IN %@", Array(identifiers))
        realm.transaction {
            realm.delete(clips)
        }
        postHistoryDidChange()
    }

    func folder(identifier: String) -> BoardManFolder? {
        let realm = try! Realm()
        guard let folder = realm.object(ofType: BoardManFolder.self, forPrimaryKey: identifier) else { return nil }
        return detachedFolder(folder)
    }

    func foldersSortedByIndex() -> [BoardManFolder] {
        let realm = try! Realm()
        return realm.objects(BoardManFolder.self)
            .sorted(byKeyPath: #keyPath(BoardManFolder.index), ascending: true)
            .map(detachedFolder)
    }

    func snippet(identifier: String) -> BoardManSnippet? {
        let realm = try! Realm()
        guard let snippet = realm.object(ofType: BoardManSnippet.self, forPrimaryKey: identifier) else { return nil }
        return BoardManSnippet(value: snippet)
    }

    func snippetsSortedByIndex() -> [BoardManSnippet] {
        let realm = try! Realm()
        return realm.objects(BoardManSnippet.self)
            .sorted(byKeyPath: #keyPath(BoardManSnippet.index), ascending: true)
            .map { BoardManSnippet(value: $0) }
    }

    func uncategorizedSnippetsSortedByIndex() -> [BoardManSnippet] {
        let realm = try! Realm()
        return realm.objects(BoardManSnippet.self)
            .filter("folders.@count == 0")
            .sorted(byKeyPath: #keyPath(BoardManSnippet.index), ascending: true)
            .map { BoardManSnippet(value: $0) }
    }

    func folderIdentifier(forSnippetIdentifier identifier: String) -> String? {
        let realm = try! Realm()
        return realm.object(ofType: BoardManSnippet.self, forPrimaryKey: identifier)?.folder?.identifier
    }

    func upsertFolder(_ folder: BoardManFolder) {
        let realm = try! Realm()
        if let stored = realm.object(ofType: BoardManFolder.self, forPrimaryKey: folder.identifier) {
            realm.transaction {
                stored.index = folder.index
                stored.enable = folder.enable
                stored.title = folder.title
            }
        } else {
            let copy = BoardManFolder()
            copy.index = folder.index
            copy.enable = folder.enable
            copy.title = folder.title
            copy.identifier = folder.identifier
            realm.transaction { realm.add(copy, update: .all) }
        }
    }

    func deleteFolder(identifier: String) {
        let realm = try! Realm()
        guard let folder = realm.object(ofType: BoardManFolder.self, forPrimaryKey: identifier) else { return }
        realm.transaction {
            realm.delete(folder.snippets)
            realm.delete(folder)
        }
    }

    func upsertSnippet(_ snippet: BoardManSnippet, folderIdentifier: String?) {
        let realm = try! Realm()
        let copy = BoardManSnippet()
        copy.index = snippet.index
        copy.enable = snippet.enable
        copy.title = snippet.title
        copy.content = snippet.content
        copy.identifier = snippet.identifier
        realm.transaction { realm.add(copy, update: .all) }
        moveSnippet(identifier: snippet.identifier, toFolderIdentifier: folderIdentifier, index: snippet.index)
    }

    func deleteSnippet(identifier: String) {
        let realm = try! Realm()
        guard let snippet = realm.object(ofType: BoardManSnippet.self, forPrimaryKey: identifier) else { return }
        realm.transaction { realm.delete(snippet) }
    }

    func moveSnippet(identifier: String, toFolderIdentifier: String?, index: Int) {
        let realm = try! Realm()
        guard let snippet = realm.object(ofType: BoardManSnippet.self, forPrimaryKey: identifier) else { return }
        realm.transaction {
            if let currentFolder = snippet.folder,
               let currentIndex = currentFolder.snippets.index(of: snippet) {
                currentFolder.snippets.remove(at: currentIndex)
            }
            snippet.index = index
            if let folderIdentifier = toFolderIdentifier,
               let destination = realm.object(ofType: BoardManFolder.self, forPrimaryKey: folderIdentifier) {
                let insertionIndex = min(max(0, index), destination.snippets.count)
                destination.snippets.insert(snippet, at: insertionIndex)
            }
        }
    }

    func reorderFolders(_ identifiers: [String]) {
        let realm = try! Realm()
        realm.transaction {
            for (index, identifier) in identifiers.enumerated() {
                realm.object(ofType: BoardManFolder.self, forPrimaryKey: identifier)?.index = index
            }
        }
    }

    func reorderSnippets(_ identifiers: [String], folderIdentifier: String?) {
        let realm = try! Realm()
        realm.transaction {
            var snippets = [BoardManSnippet]()
            for (index, identifier) in identifiers.enumerated() {
                guard let snippet = realm.object(ofType: BoardManSnippet.self, forPrimaryKey: identifier) else { continue }
                snippet.index = index
                snippets.append(snippet)
            }
            if let folderIdentifier,
               let folder = realm.object(ofType: BoardManFolder.self, forPrimaryKey: folderIdentifier) {
                folder.snippets.removeAll()
                folder.snippets.append(objectsIn: snippets)
            }
        }
    }

    private func detachedFolder(_ folder: BoardManFolder) -> BoardManFolder {
        let copy = BoardManFolder()
        copy.index = folder.index
        copy.enable = folder.enable
        copy.title = folder.title
        copy.identifier = folder.identifier
        folder.snippets
            .sorted(byKeyPath: #keyPath(BoardManSnippet.index), ascending: true)
            .forEach { copy.snippets.append(BoardManSnippet(value: $0)) }
        return copy
    }
}
