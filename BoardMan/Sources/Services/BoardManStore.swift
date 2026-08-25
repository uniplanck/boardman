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
