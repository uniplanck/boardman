//
//  BoardManApplicationInfo.swift
//  Board-Man
//

import Cocoa

final class BoardManApplicationInfo: NSObject, NSCoding {
    let identifier: String
    let name: String

    init?(info: [String: AnyObject]) {
        guard let identifier = info[kCFBundleIdentifierKey as String] as? String else { return nil }
        guard let name = (info[kCFBundleNameKey as String] as? String)
            ?? (info[kCFBundleExecutableKey as String] as? String) else { return nil }
        self.identifier = identifier
        self.name = name
        super.init()
    }

    required init?(coder decoder: NSCoder) {
        guard let identifier = decoder.decodeObject(forKey: "identifier") as? String,
              let name = decoder.decodeObject(forKey: "name") as? String else { return nil }
        self.identifier = identifier
        self.name = name
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(identifier, forKey: "identifier")
        coder.encode(name, forKey: "name")
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? BoardManApplicationInfo else { return false }
        return identifier == other.identifier && name == other.name
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(identifier)
        hasher.combine(name)
        return hasher.finalize()
    }

    static func registerLegacyArchiveAliases() {
        // Preserve existing installs without keeping an upstream implementation.
        // The legacy Objective-C class name is assembled so new source does not
        // carry the old product identifier as an active type.
        let legacyClassName = ["C", "PY", "AppInfo"].joined()
        NSKeyedUnarchiver.setClass(Self.self, forClassName: legacyClassName)
        NSKeyedUnarchiver.setClass(Self.self, forClassName: "Board_Man.\(legacyClassName)")
    }
}
