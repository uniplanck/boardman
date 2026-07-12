//
//  PasteCountStore.swift
//
//  Clipy
//

import Cocoa
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
        if isImageClip(clip) {
            return imageKey(for: clip)
        }
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

    func count(for clip: CPYClip, in snapshot: [String: NSNumber]) -> Int {
        return snapshot[key(for: clip)]?.intValue ?? 0
    }

    func countsSnapshot() -> [String: NSNumber] {
        lock.lock(); defer { lock.unlock() }
        return counts()
    }

    func label(for clip: CPYClip) -> String {
        return "\(count(for: clip)) "
    }

    func keyForLatestClip(matching string: String) -> String? {
        let realm = try! Realm()

        guard let clip = latestTextClip(in: realm, matching: string) else {
            return nil
        }

        let pasteCountKey = key(for: clip)
        let unixTime = Int(Date().timeIntervalSince1970)
        do {
            try realm.write {
                clip.updateTime = unixTime
            }
        } catch {
            return nil
        }

        postPasteCountDidChange()
        return pasteCountKey
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
            postPasteCountDidChange()
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

        postPasteCountDidChange()
        return true
    }

    private func count(forKey key: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts()[key]?.intValue ?? 0
    }

    private func counts() -> [String: NSNumber] {
        return defaults.dictionary(forKey: Constants.UserDefaults.pasteCounts) as? [String: NSNumber] ?? [:]
    }

    private func latestTextClip(in realm: Realm, matching string: String) -> CPYClip? {
        // Manual Cmd+V count must stay fast: use Realm metadata only.
        // Reading every archived CPYClipData file blocks UI on large histories.
        let storedTitle = storedTitle(forText: string)
        let textTypes = [
            NSPasteboard.PasteboardType.string.rawValue,
            NSPasteboard.PasteboardType.deprecatedString.rawValue,
            NSPasteboard.PasteboardType.deprecatedRTF.rawValue,
            NSPasteboard.PasteboardType.deprecatedRTFD.rawValue
        ]
        return realm.objects(CPYClip.self)
            .filter("title == %@ AND primaryType IN %@", storedTitle, textTypes)
            .sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: false)
            .first
    }

    private func storedTitle(forText string: String) -> String {
        let title = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? string : string
        return title[0...10000]
    }

    private func postPasteCountDidChange() {
        let post = {
            NotificationCenter.default.post(name: Notification.Name(rawValue: Constants.Notification.pasteCountDidChange), object: nil)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    private func stableHash(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func imageKey(for clip: CPYClip) -> String {
        let insertedAt = imageInsertedAtComponent(for: clip)
        let pathHash = clip.dataPath.isEmpty ? "" : stableHash(clip.dataPath)
        return "\(clip.primaryType):image:\(insertedAt):\(pathHash):\(clip.dataHash)"
    }

    private func imageInsertedAtComponent(for clip: CPYClip) -> String {
        if !clip.thumbnailPath.isEmpty {
            return clip.thumbnailPath
        }
        if clip.updateTime > 0 {
            return "\(clip.updateTime)"
        }
        return "unknown"
    }

    private func isImageClip(_ clip: CPYClip) -> Bool {
        if !clip.thumbnailPath.isEmpty && !clip.isColorCode {
            return true
        }
        let type = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        return type == .png || type == .tiff || type == .deprecatedTIFF
    }
}
