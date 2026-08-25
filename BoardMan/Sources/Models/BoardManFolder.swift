//
//  BoardManFolder.swift
//
//  Board-Man
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RealmSwift

@objc(CPYFolder)
final class BoardManFolder: Object {

    @objc dynamic var index = 0
    @objc dynamic var enable = true
    @objc dynamic var title = ""
    @objc dynamic var identifier = UUID().uuidString
    let snippets = List<BoardManSnippet>()

    override static func primaryKey() -> String? {
        return "identifier"
    }
}

extension BoardManFolder {
    func deepCopy() -> BoardManFolder {
        let folder = BoardManFolder(value: self)
        var snippets = [BoardManSnippet]()
        if realm == nil {
            self.snippets.forEach {
                snippets.append(BoardManSnippet(value: $0))
            }
        } else {
            self.snippets.sorted(byKeyPath: #keyPath(BoardManSnippet.index), ascending: true).forEach {
                snippets.append(BoardManSnippet(value: $0))
            }
        }
        folder.snippets.removeAll()
        folder.snippets.append(objectsIn: snippets)
        return folder
    }

    func createSnippet() -> BoardManSnippet {
        let snippet = BoardManSnippet()
        snippet.title = "untitled snippet"
        snippet.index = Int(snippets.count)
        return snippet
    }

    func mergeSnippet(_ snippet: BoardManSnippet) {
        let store = BoardManStores.authoritative
        let copy = BoardManSnippet(value: snippet)
        copy.index = store.folder(identifier: identifier)?.snippets.count ?? 0
        store.upsertSnippet(copy, folderIdentifier: identifier)
    }

    func insertSnippet(_ snippet: BoardManSnippet, index: Int) {
        let store = BoardManStores.authoritative
        var identifiers = store.folder(identifier: identifier)?.snippets.map(\.identifier) ?? []
        identifiers.removeAll { $0 == snippet.identifier }
        let insertionIndex = min(max(0, index), identifiers.count)
        identifiers.insert(snippet.identifier, at: insertionIndex)
        store.moveSnippet(identifier: snippet.identifier, toFolderIdentifier: identifier, index: insertionIndex)
        store.reorderSnippets(identifiers, folderIdentifier: identifier)
    }

    func removeSnippet(_ snippet: BoardManSnippet) {
        let store = BoardManStores.authoritative
        var identifiers = store.folder(identifier: identifier)?.snippets.map(\.identifier) ?? []
        identifiers.removeAll { $0 == snippet.identifier }
        store.moveSnippet(identifier: snippet.identifier, toFolderIdentifier: nil, index: snippet.index)
        store.reorderSnippets(identifiers, folderIdentifier: identifier)
    }

    static func create() -> BoardManFolder {
        let folder = BoardManFolder()
        folder.title = "untitled folder"
        folder.index = (BoardManStores.authoritative.foldersSortedByIndex().last?.index ?? -1) + 1
        return folder
    }

    func merge() {
        BoardManStores.authoritative.upsertFolder(self)
    }

    func remove() {
        BoardManStores.authoritative.deleteFolder(identifier: identifier)
    }

    static func rearrangesIndex(_ folders: [BoardManFolder]) {
        folders.enumerated().forEach { index, folder in
            if folder.realm == nil { folder.index = index }
        }
        BoardManStores.authoritative.reorderFolders(folders.map(\.identifier))
    }

    func rearrangesSnippetIndex() {
        snippets.enumerated().forEach { index, snippet in
            if snippet.realm == nil { snippet.index = index }
        }
        BoardManStores.authoritative.reorderSnippets(snippets.map(\.identifier), folderIdentifier: identifier)
    }
}

// Persistence/source compatibility boundary while callers are migrated to the Board-Man name.
