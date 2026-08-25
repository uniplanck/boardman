//
//  PasteCountStore.swift
//
//  Clipy
//

import Cocoa
import Foundation

final class PasteCountStore {

    static let shared = PasteCountStore()

    private let defaults: UserDefaults
    private let store: BoardManStore
    private let lock = NSRecursiveLock(name: "com.uniplanck.BoardMan.PasteCountStore")
    private let persistenceQueue = DispatchQueue(label: "com.uniplanck.BoardMan.PasteCountStore.persistence", qos: .utility)
    private let persistenceDelay: TimeInterval = 0.45
    private var cachedCounts: [String: NSNumber]
    private var pendingPersistence: DispatchWorkItem?

    init(
        defaults: UserDefaults = AppEnvironment.current.defaults,
        store: BoardManStore = BoardManStores.authoritative
    ) {
        self.defaults = defaults
        self.store = store
        self.cachedCounts = defaults.dictionary(forKey: Constants.UserDefaults.pasteCounts) as? [String: NSNumber] ?? [:]
    }

    func key(for clip: BoardManClip) -> String {
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

    func count(for clip: BoardManClip) -> Int {
        return count(forKey: key(for: clip))
    }

    func count(for clip: BoardManClip, in snapshot: [String: NSNumber]) -> Int {
        return snapshot[key(for: clip)]?.intValue ?? 0
    }

    func countsSnapshot() -> [String: NSNumber] {
        lock.lock(); defer { lock.unlock() }
        return cachedCounts
    }

    func label(for clip: BoardManClip) -> String {
        return "\(count(for: clip)) "
    }

    func keyForLatestClip(matching string: String) -> String? {
        let textTypes = [
            NSPasteboard.PasteboardType.string.rawValue,
            NSPasteboard.PasteboardType.deprecatedString.rawValue,
            NSPasteboard.PasteboardType.deprecatedRTF.rawValue,
            NSPasteboard.PasteboardType.deprecatedRTFD.rawValue
        ]
        guard let clip = store.latestClip(
            title: storedTitle(forText: string),
            primaryTypes: textTypes
        ) else {
            return nil
        }
        return markUsedAndReturnKey(for: clip)
    }

    func keyForLatestImageClip(matching image: NSImage) -> String? {
        guard let targetFingerprint = Self.imageFingerprint(for: image) else { return nil }
        let candidates = store.clipsSortedByUpdateTimeDescending()
            .filter { self.isImageClip($0) }
            .prefix(120)

        for clip in candidates {
            guard !clip.dataPath.isEmpty,
                  let archivedData = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? BoardManClipData,
                  let archivedImage = archivedData.image,
                  Self.imageFingerprint(for: archivedImage) == targetFingerprint else {
                continue
            }
            return markUsedAndReturnKey(for: clip)
        }
        return nil
    }

    static func imageFingerprint(for image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return "\(bitmap.pixelsWide)x\(bitmap.pixelsHigh):\(stableHash(pngData))"
    }

    @discardableResult
    func markUsed(clip: BoardManClip) -> Bool {
        return store.updateClipUsage(
            identifier: clip.dataHash,
            updateTime: Int(Date().timeIntervalSince1970)
        )
    }

    @discardableResult
    func increment(for clip: BoardManClip) -> Bool {
        return increment(forKey: key(for: clip))
    }

    @discardableResult
    func increment(forKey key: String) -> Bool {
        lock.lock()
        let nextCount = (cachedCounts[key]?.intValue ?? 0) + 1
        cachedCounts[key] = NSNumber(value: nextCount)
        schedulePersistenceLocked()
        lock.unlock()

        postPasteCountDidChange()
        return true
    }

    func flushPendingPersistence() {
        lock.lock()
        pendingPersistence?.cancel()
        pendingPersistence = nil
        let snapshot = cachedCounts
        lock.unlock()

        defaults.set(snapshot, forKey: Constants.UserDefaults.pasteCounts)
        defaults.synchronize()
    }

    private func count(forKey key: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return cachedCounts[key]?.intValue ?? 0
    }

    private func schedulePersistenceLocked() {
        pendingPersistence?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistCachedCounts()
        }
        pendingPersistence = workItem
        persistenceQueue.asyncAfter(deadline: .now() + persistenceDelay, execute: workItem)
    }

    private func persistCachedCounts() {
        lock.lock()
        let snapshot = cachedCounts
        pendingPersistence = nil
        lock.unlock()
        defaults.set(snapshot, forKey: Constants.UserDefaults.pasteCounts)
    }

    private func markUsedAndReturnKey(for clip: BoardManClip) -> String? {
        let pasteCountKey = key(for: clip)
        return markUsed(clip: clip) ? pasteCountKey : nil
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
        return Self.stableHash(Data(string.utf8))
    }

    private static func stableHash(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func imageKey(for clip: BoardManClip) -> String {
        let insertedAt = imageInsertedAtComponent(for: clip)
        let pathHash = clip.dataPath.isEmpty ? "" : stableHash(clip.dataPath)
        return "\(clip.primaryType):image:\(insertedAt):\(pathHash):\(clip.dataHash)"
    }

    private func imageInsertedAtComponent(for clip: BoardManClip) -> String {
        if !clip.thumbnailPath.isEmpty {
            return clip.thumbnailPath
        }
        if clip.updateTime > 0 {
            return "\(clip.updateTime)"
        }
        return "unknown"
    }

    private func isImageClip(_ clip: BoardManClip) -> Bool {
        if !clip.thumbnailPath.isEmpty && !clip.isColorCode {
            return true
        }
        let type = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        return type == .png || type == .tiff || type == .deprecatedTIFF
    }
}
