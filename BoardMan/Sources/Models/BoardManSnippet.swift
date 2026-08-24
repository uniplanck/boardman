//
//  BoardManSnippet.swift
//
//  Board-Man
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RealmSwift

@objc(CPYSnippet)
final class BoardManSnippet: Object {

    @objc dynamic var index = 0
    @objc dynamic var enable = true
    @objc dynamic var title = ""
    @objc dynamic var content = ""
    @objc dynamic var identifier = UUID().uuidString
    let folders = LinkingObjects(fromType: BoardManFolder.self, property: "snippets")

    var folder: BoardManFolder? {
        return folders.first
    }

    override static func primaryKey() -> String? {
        return "identifier"
    }

    override static func ignoredProperties() -> [String] {
        return ["folder"]
    }
}

extension BoardManSnippet {
    func merge() {
        let realm = try! Realm()
        let copySnippet = BoardManSnippet(value: self)
        realm.transaction { realm.add(copySnippet, update: .all) }
    }

    func remove() {
        let realm = try! Realm()
        guard let snippet = realm.object(ofType: BoardManSnippet.self, forPrimaryKey: identifier) else { return }
        snippet.realm?.transaction { snippet.realm?.delete(snippet) }
    }
}

// Persistence/source compatibility boundary while callers are migrated to the Board-Man name.
