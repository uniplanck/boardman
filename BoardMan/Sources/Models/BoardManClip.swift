//
//  BoardManClip.swift
//
//  Board-Man
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RealmSwift

@objc(CPYClip)
final class BoardManClip: Object {

    // MARK: - Properties
    @objc dynamic var dataPath = ""
    @objc dynamic var title = ""
    @objc dynamic var dataHash = ""
    @objc dynamic var primaryType = ""
    @objc dynamic var createdTime = 0
    @objc dynamic var updateTime = 0
    @objc dynamic var thumbnailPath = ""
    @objc dynamic var isColorCode = false

    override static func primaryKey() -> String? {
        return "dataHash"
    }
}

// Compatibility boundary for source paths that are migrated independently from the Realm schema.
