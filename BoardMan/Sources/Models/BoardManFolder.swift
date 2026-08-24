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
        let realm = try! Realm()
        guard let folder = realm.object(ofType: BoardManFolder.self, forPrimaryKey: identifier) else { return }
        let copySnippet = BoardManSnippet(value: snippet)
        folder.realm?.transaction { folder.snippets.append(copySnippet) }
    }

    func insertSnippet(_ snippet: BoardManSnippet, index: Int) {
        let realm = try! Realm()
        guard let folder = realm.object(ofType: BoardManFolder.self, forPrimaryKey: identifier) else { return }
        guard let savedSnippet = realm.object(ofType: BoardManSnippet.self, forPrimaryKey: snippet.identifier) else { return }
        folder.realm?.transaction { folder.snippets.insert(savedSnippet, at: index) }
        folder.rearrangesSnippetIndex()
    }

    func removeSnippet(_ snippet: BoardManSnippet) {
        let realm = try! Realm()
        guard let folder = realm.object(ofType: BoardManFolder.self, forPrimaryKey: identifier) else { return }
        guard let savedSnippet = realm.object(ofType: BoardManSnippet.self, forPrimaryKey: snippet.identifier),
              let index = folder.snippets.index(of: savedSnippet) else { return }
        folder.realm?.transaction { folder.snippets.remove(at: index) }
        folder.rearrangesSnippetIndex()
    }

    static func create() -> BoardManFolder {
        let realm = try! Realm()
        let folder = BoardManFolder()
        folder.title = "untitled folder"
        let lastFolder = realm.objects(BoardManFolder.self)
            .sorted(byKeyPath: #keyPath(BoardManFolder.index), ascending: true)
            .last
        folder.index = (lastFolder?.index ?? -1) + 1
        return folder
    }

    func merge() {
        let realm = try! Realm()
        if let folder = realm.object(ofType: BoardManFolder.self, forPrimaryKey: identifier) {
            folder.realm?.transaction {
                folder.index = index
                folder.enable = enable
                folder.title = title
            }
        } else {
            let copyFolder = BoardManFolder(value: self)
            realm.transaction { realm.add(copyFolder, update: .all) }
        }
    }

    func remove() {
        let realm = try! Realm()
        guard let folder = realm.object(ofType: BoardManFolder.self, forPrimaryKey: identifier) else { return }
        folder.realm?.transaction { folder.realm?.delete(folder.snippets) }
        folder.realm?.transaction { folder.realm?.delete(folder) }
    }

    static func rearrangesIndex(_ folders: [BoardManFolder]) {
        for (index, folder) in folders.enumerated() {
            if folder.realm == nil { folder.index = index }
            let realm = try! Realm()
            guard let savedFolder = realm.object(ofType: BoardManFolder.self, forPrimaryKey: folder.identifier) else { return }
            savedFolder.realm?.transaction {
                savedFolder.index = index
            }
        }
    }

    func rearrangesSnippetIndex() {
        for (index, snippet) in snippets.enumerated() {
            if snippet.realm == nil { snippet.index = index }
            let realm = try! Realm()
            guard let savedSnippet = realm.object(ofType: BoardManSnippet.self, forPrimaryKey: snippet.identifier) else { return }
            savedSnippet.realm?.transaction {
                savedSnippet.index = index
            }
        }
    }
}

// Persistence/source compatibility boundary while callers are migrated to the Board-Man name.
