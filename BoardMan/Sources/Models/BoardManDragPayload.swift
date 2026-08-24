//
//  BoardManDragPayload.swift
//  Board-Man
//

import Foundation

final class BoardManDragPayload: NSObject, NSCoding {
    enum DragType: Int {
        case folder
        case snippet
    }

    let type: DragType
    let folderIdentifier: String?
    let snippetIdentifier: String?
    let index: Int

    init(type: DragType,
         folderIdentifier: String?,
         snippetIdentifier: String?,
         index: Int) {
        self.type = type
        self.folderIdentifier = folderIdentifier
        self.snippetIdentifier = snippetIdentifier
        self.index = index
        super.init()
    }

    required init?(coder decoder: NSCoder) {
        type = DragType(rawValue: decoder.decodeInteger(forKey: "type")) ?? .folder
        folderIdentifier = decoder.decodeObject(forKey: "folderIdentifier") as? String
        snippetIdentifier = decoder.decodeObject(forKey: "snippetIdentifier") as? String
        index = decoder.decodeInteger(forKey: "index")
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(type.rawValue, forKey: "type")
        coder.encode(folderIdentifier, forKey: "folderIdentifier")
        coder.encode(snippetIdentifier, forKey: "snippetIdentifier")
        coder.encode(index, forKey: "index")
    }
}
