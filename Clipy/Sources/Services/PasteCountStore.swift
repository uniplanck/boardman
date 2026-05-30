//
//  PasteCountStore.swift
//
//  Clipy
//

import Foundation
import RealmSwift

final class PasteCountStore {

    static let shared = PasteCountStore()

    private let defaults: UserDefaults
    private let lock = NSRecursiveLock(name: "com.uniplanck.BoardMan.PasteCountStore")

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    func key(for clip: CPYClip) -> String {
        return key(forString: clip.title, primaryType: clip.primaryType, dataHash: clip.dataHash)
    }

    func key(forString string: String, primaryType: String, dataHash: String = "") -> String {
        let normalizedTitle = string
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !normalizedTitle.isEmpty {
            return "\(primaryType):text:\(stableHash(normalizedTitle))"
        }
        return "\(primaryType):clip:\(dataHash)"
    }

    func count(for clip: CPYClip) -> Int {
        return count(forKey: key(for: clip))
    }

    func label(for clip: CPYClip) -> String {
        return "\(count(for: clip)) "
    }

    func keyForLatestClip(matching string: String) -> String? {
        let realm = try! Realm()
        let clips = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: false)

        for clip in clips {
            if clip.isInvalidated { continue }
            guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? CPYClipData else { continue }
            if data.stringValue == string {
                let unixTime = Int(Date().timeIntervalSince1970)
                do {
                    try realm.write {
                        clip.updateTime = unixTime
                    }
                } catch {
                    return nil
                }
                NotificationCenter.default.post(name: Notification.Name(rawValue: Constants.Notification.pasteCountDidChange), object: nil)
                return key(for: clip)
            }
        }

        return nil
    }

    @discardableResult
    func markUsed(clip: CPYClip, in realm: Realm) -> Bool {
        guard !clip.isInvalidated else { return false }

        let unixTime = Int(Date().timeIntervalSince1970)
        do {
            try realm.write {
                guard !clip.isInvalidated else { return }
                clip.updateTime = unixTime
            }
            NotificationCenter.default.post(name: Notification.Name(rawValue: Constants.Notification.pasteCountDidChange), object: nil)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func increment(for clip: CPYClip) -> Bool {
        return increment(forKey: key(for: clip))
    }

    @discardableResult
    func increment(forKey key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }

        var pasteCounts = counts()
        let nextCount = (pasteCounts[key]?.intValue ?? 0) + 1
        pasteCounts[key] = NSNumber(value: nextCount)
        defaults.set(pasteCounts, forKey: Constants.UserDefaults.pasteCounts)
        defaults.synchronize()

        NotificationCenter.default.post(name: Notification.Name(rawValue: Constants.Notification.pasteCountDidChange), object: nil)
        return true
    }

    private func count(forKey key: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts()[key]?.intValue ?? 0
    }

    private func counts() -> [String: NSNumber] {
        return defaults.dictionary(forKey: Constants.UserDefaults.pasteCounts) as? [String: NSNumber] ?? [:]
    }

    private func stableHash(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
