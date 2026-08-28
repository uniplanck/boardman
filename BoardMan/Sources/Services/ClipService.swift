//
//  ClipService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import PINCache

final class ClipService {

    // MARK: - Properties
    fileprivate var cachedChangeCount = 0
    fileprivate var storeTypes = [String: NSNumber]()
    fileprivate let monitorQueue = DispatchQueue(label: "com.uniplanck.BoardMan.ClipService.pasteboard", qos: .utility)
    fileprivate let persistenceQueue = DispatchQueue(label: "com.uniplanck.BoardMan.ClipService.persistence", qos: .utility)
    fileprivate var pasteboardTimer: DispatchSourceTimer?
    fileprivate let lock = NSRecursiveLock(name: "com.uniplanck.BoardMan.ClipUpdatable")
    fileprivate var defaultsObserver: NSObjectProtocol?
    fileprivate var ignoredPasteboardChangeCount: Int?
    fileprivate var ignoredPasteboardFingerprint: Int?
    private let store: BoardManStore
    private let livePlainTextTypeRawValues: Set<String> = [
        NSPasteboard.PasteboardType.string.rawValue,
        NSPasteboard.PasteboardType.deprecatedString.rawValue,
        "public.utf16-external-plain-text",
        "public.utf16-plain-text"
    ]

    init(store: BoardManStore = BoardManStores.authoritative) {
        self.store = store
    }

    deinit {
        pasteboardTimer?.cancel()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    // MARK: - Clips
    func startMonitoring() {
        lock.lock()
        cachedChangeCount = NSPasteboard.general.changeCount
        lock.unlock()

        pasteboardTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + .milliseconds(100),
                       repeating: .milliseconds(100),
                       leeway: .milliseconds(25))
        timer.setEventHandler { [weak self] in
            self?.pollPasteboard()
        }
        pasteboardTimer = timer
        timer.resume()

        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        let defaults = AppEnvironment.current.defaults
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: nil
        ) { [weak self, weak defaults] _ in
            guard let self, let defaults else { return }
            self.refreshStoreTypes(from: defaults)
        }
        refreshStoreTypes(from: defaults)
    }

    private func refreshStoreTypes(from defaults: UserDefaults) {
        let types = defaults.dictionary(forKey: Constants.UserDefaults.storeTypes) as? [String: NSNumber]
            ?? AppDelegate.storeTypesDictinary()
        lock.lock()
        storeTypes = types
        lock.unlock()
    }

    func clearAll() {
        let clips = store.clipsSortedByUpdateTimeDescending()
        let deletableClips = clips.filter { !PinnedSnippetStore.shared.isPinned($0.dataHash) }

        // Pinned history is durable until the user explicitly unpins it.
        deletableClips
            .filter { !$0.thumbnailPath.isEmpty }
            .map { $0.thumbnailPath }
            .forEach { PINCache.shared.removeObject(forKey: $0) }
        store.deleteClips(identifiers: Set(deletableClips.map(\.dataHash)))
        AppEnvironment.current.dataCleanService.cleanDatas()
    }

    func delete(with clip: BoardManClip) {
        guard !PinnedSnippetStore.shared.isPinned(clip.dataHash) else { return }
        // Delete saved images
        let path = clip.thumbnailPath
        if !path.isEmpty {
            PINCache.shared.removeObject(forKey: path)
        }
        store.deleteClip(identifier: clip.dataHash)
    }

    func incrementChangeCount() {
        lock.lock(); defer { lock.unlock() }
        cachedChangeCount += 1
    }

    func markCurrentPasteboardChangeAsHandled() {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        cachedChangeCount = pasteboard.changeCount
        ignoredPasteboardChangeCount = pasteboard.changeCount
        ignoredPasteboardFingerprint = fingerprint(with: pasteboard)
    }

    func ingestCurrentPasteboard() {
        create(detectedAt: CFAbsoluteTimeGetCurrent())
    }

    func sanitizePasteboardSoonAfterUserCopy() {
        monitorQueue.asyncAfter(deadline: .now() + .milliseconds(35)) { [weak self] in
            self?.processPasteboardChangeIfNeeded()
        }
    }

    private func pollPasteboard() {
        processPasteboardChangeIfNeeded()
    }

    private func processPasteboardChangeIfNeeded() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        lock.lock()
        guard changeCount != cachedChangeCount else {
            lock.unlock()
            return
        }
        cachedChangeCount = changeCount
        lock.unlock()
        let detectedAt = CFAbsoluteTimeGetCurrent()

        if sanitizeLivePlainTextIfNeeded(pasteboard) {
            lock.lock()
            cachedChangeCount = pasteboard.changeCount
            lock.unlock()
        }
        create(detectedAt: detectedAt)
    }

    @discardableResult
    private func sanitizeLivePlainTextIfNeeded(_ pasteboard: NSPasteboard) -> Bool {
        guard !AppEnvironment.current.excludeAppService.frontProcessIsExcludedApplication() else { return false }
        guard !AppEnvironment.current.excludeAppService.copiedProcessIsExcludedApplications(pasteboard: pasteboard) else { return false }
        guard let corrected = BoardManClipData.liveSanitizedPlainText(from: pasteboard),
              let items = pasteboard.pasteboardItems,
              !items.isEmpty else {
            return false
        }

        let originalChangeCount = pasteboard.changeCount
        var replacements: [NSPasteboardItem] = []
        replacements.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            let replacement = NSPasteboardItem()
            for type in item.types {
                if index == 0, livePlainTextTypeRawValues.contains(type.rawValue) {
                    _ = replacement.setString(corrected, forType: type)
                } else if let data = item.data(forType: type) {
                    _ = replacement.setData(data, forType: type)
                } else if let string = item.string(forType: type) {
                    _ = replacement.setString(string, forType: type)
                } else if let propertyList = item.propertyList(forType: type) {
                    _ = replacement.setPropertyList(propertyList, forType: type)
                }
            }
            replacements.append(replacement)
        }

        // Never overwrite a newer clipboard value that arrived while lazy pasteboard data was
        // being materialized.
        guard pasteboard.changeCount == originalChangeCount else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(replacements)
    }
}

// MARK: - Create Clip
extension ClipService {
    fileprivate func create(detectedAt: CFAbsoluteTime? = nil) {
        lock.lock(); defer { lock.unlock() }

        // Store types
        if !storeTypes.values.contains(NSNumber(value: true)) { return }
        // Pasteboard types
        let pasteboard = NSPasteboard.general
        if shouldIgnorePasteboardChange(pasteboard) { return }
        let types = self.types(with: pasteboard)
        if types.isEmpty { return }

        // Excluded application
        guard !AppEnvironment.current.excludeAppService.frontProcessIsExcludedApplication() else { return }
        // Special applications
        guard !AppEnvironment.current.excludeAppService.copiedProcessIsExcludedApplications(pasteboard: pasteboard) else { return }

        // Create data
        let data = BoardManClipData(pasteboard: pasteboard, types: types)
        let sourceApplication = AppEnvironment.current.excludeAppService.frontApplicationSearchMetadata()
        save(with: data, sourceApplication: sourceApplication, detectedAt: detectedAt)
    }

    func create(with image: NSImage) {
        lock.lock(); defer { lock.unlock() }

        // Create only image data
        let data = BoardManClipData(image: image)
        save(with: data)
    }

    fileprivate func save(
        with data: BoardManClipData,
        sourceApplication: (name: String, bundleIdentifier: String)? = nil,
        detectedAt: CFAbsoluteTime? = nil
    ) {
        // Copy already copied history
        let isCopySameHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.copySameHistory)
        if store.clip(identifier: "\(data.hash)") != nil, !isCopySameHistory { return }

        // Don't save empty string history
        if data.isOnlyStringType && data.stringValue.isEmpty { return }

        // Overwrite same history
        let isOverwriteHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory)
        let savedHash = isOverwriteHistory ? data.hash : Int.random(in: 0..<1_000_000)

        // Saved time and path
        let unixTime = Int(Date().timeIntervalSince1970)
        let savedPath = BoardManRuntimeSupport.applicationSupportFolder() + "/\(NSUUID().uuidString).data"
        // Create Realm object
        let clip = BoardManClip()
        clip.dataPath = savedPath
        let title = data.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (data.imageDisplayTitle ?? data.stringValue) : data.stringValue
        clip.title = title[0...10000]
        clip.dataHash = "\(savedHash)"
        clip.createdTime = Int(Date().timeIntervalSince1970 * 1000)
        clip.updateTime = unixTime
        clip.primaryType = data.primaryType?.rawValue ?? ""

        let fullText = String(data.boardManTextValue.prefix(100_000))
        let searchMetadata = BoardManHistorySearchMetadata(
            text: fullText == clip.title ? "" : fullText,
            filePaths: Array(data.fileNames.prefix(256)).map { String($0.prefix(4_096)) },
            urls: Array(data.URLs.prefix(256)).map { String($0.prefix(4_096)) },
            sourceApplicationName: sourceApplication?.name ?? "",
            sourceApplicationBundleID: sourceApplication?.bundleIdentifier ?? ""
        )

        persistenceQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                assert(!Thread.isMainThread, "Clipboard persistence must never run on the main thread")

                // Commercial limits are admission gates, never retention/deletion gates. A
                // downgrade therefore leaves grandfathered history untouched and only refuses
                // a record that would grow the collection past the current plan limit.
                let replacesExistingRecord = self.store.clip(identifier: clip.dataHash) != nil
                if !replacesExistingRecord {
                    let currentCount = self.store.clipsSortedByUpdateTimeDescending().count
                    guard EntitlementGate.canAddHistoryItem(currentCount: currentCount) else {
                        return
                    }
                }

                // Thumbnail generation, archive encoding, and database writes are deliberately
                // serialized away from AppKit presentation work.
                if let thumbnailImage = data.thumbnailImage {
                    PINCache.shared.setObjectAsync(thumbnailImage, forKey: "\(unixTime)", completion: nil)
                    clip.thumbnailPath = "\(unixTime)"
                }
                if let colorCodeImage = data.colorCodeImage {
                    PINCache.shared.setObjectAsync(colorCodeImage, forKey: "\(unixTime)", completion: nil)
                    clip.thumbnailPath = "\(unixTime)"
                    clip.isColorCode = true
                }
                guard BoardManRuntimeSupport.prepareDirectory(
                    at: BoardManRuntimeSupport.applicationSupportFolder()
                ), BoardManRuntimeSupport.archiveRootObjectAtomically(data, to: savedPath) else {
                    return
                }

                self.store.upsertClip(clip, searchMetadata: searchMetadata)
                if let detectedAt {
                    PasteCountInputService.shared.logBoardManPerformance(
                        "clipboard_capture_to_queryable",
                        startedAt: detectedAt,
                        details: "type=\(clip.primaryType.isEmpty ? "unknown" : clip.primaryType)"
                    )
                }
                self.trimHistoryIfNeeded()
            }
        }
    }

    private func trimHistoryIfNeeded() {
        guard let limit = BoardManHistoryRetentionPolicy.effectiveLimit(),
              limit > 0 else { return }

        let clips = store.clipsSortedByUpdateTimeDescending()
        guard clips.count > limit else { return }

        let removableIdentifiers = PinnedSnippetStore.shared.oldestUnpinnedIdentifiers(
            in: clips.map(\.dataHash),
            maximumCount: clips.count - limit
        )
        let overflowingClips = clips.filter { removableIdentifiers.contains($0.dataHash) }
        let removableClips = TextHistoryArchiveStore.shared.clipsSafeToRemove(overflowingClips)
        removableClips
            .filter { !$0.thumbnailPath.isEmpty }
            .map { $0.thumbnailPath }
            .forEach { PINCache.shared.removeObject(forKey: $0) }
        let dataPaths = removableClips.map(\.dataPath)
        let identifiers = removableClips.map(\.dataHash)

        store.deleteClips(identifiers: Set(identifiers))
        HistoryDisplayNameStore.shared.remove(identifiers)
        dataPaths.filter { !$0.isEmpty }.forEach { BoardManRuntimeSupport.deleteData(at: $0) }
    }

    private func types(with pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        let types = pasteboard.types?.compactMap { storableType(for: $0, pasteboard: pasteboard) } ?? []
        return NSOrderedSet(array: types).array as? [NSPasteboard.PasteboardType] ?? []
    }

    private func storableType(for type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.PasteboardType? {
        if type == .string && pasteboard.string(forType: .string) != nil {
            return canSave(with: .deprecatedString) ? .deprecatedString : nil
        }
        if type == .png || type == .tiff {
            return canSave(with: .deprecatedTIFF) ? type : nil
        }
        return canSave(with: type) ? type : nil
    }

    private func canSave(with type: NSPasteboard.PasteboardType) -> Bool {
        let dictionary = BoardManClipData.availableTypesDictinary
        guard let value = dictionary[type] else { return false }
        guard let number = storeTypes[value] else { return false }
        return number.boolValue
    }

    private func shouldIgnorePasteboardChange(_ pasteboard: NSPasteboard) -> Bool {
        guard ignoredPasteboardChangeCount == pasteboard.changeCount else { return false }
        guard ignoredPasteboardFingerprint == fingerprint(with: pasteboard) else { return false }
        ignoredPasteboardChangeCount = nil
        ignoredPasteboardFingerprint = nil
        return true
    }

    private func fingerprint(with pasteboard: NSPasteboard) -> Int {
        var fingerprint = pasteboard.types?.map { $0.rawValue }.joined(separator: "|").hash ?? 0
        if let string = pasteboard.string(forType: .string) ?? pasteboard.string(forType: .deprecatedString) {
            fingerprint ^= string.hash
        }
        return fingerprint
    }
}
