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
import RealmSwift
import PINCache
import RxSwift
import RxCocoa

final class ClipService {

    // MARK: - Properties
    fileprivate var cachedChangeCount = 0
    fileprivate var storeTypes = [String: NSNumber]()
    fileprivate let monitorQueue = DispatchQueue(label: "com.uniplanck.BoardMan.ClipService.pasteboard", qos: .utility)
    fileprivate var pasteboardTimer: DispatchSourceTimer?
    fileprivate let lock = NSRecursiveLock(name: "com.uniplanck.BoardMan.ClipUpdatable")
    fileprivate var disposeBag = DisposeBag()
    fileprivate var ignoredPasteboardChangeCount: Int?
    fileprivate var ignoredPasteboardFingerprint: Int?
    private let livePlainTextTypeRawValues: Set<String> = [
        NSPasteboard.PasteboardType.string.rawValue,
        NSPasteboard.PasteboardType.deprecatedString.rawValue,
        "public.utf16-external-plain-text",
        "public.utf16-plain-text"
    ]

    deinit {
        pasteboardTimer?.cancel()
    }

    // MARK: - Clips
    func startMonitoring() {
        disposeBag = DisposeBag()
        storeTypes = AppEnvironment.current.defaults.dictionary(forKey: Constants.UserDefaults.storeTypes) as? [String: NSNumber] ?? AppDelegate.storeTypesDictinary()
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

        // Store types
        AppEnvironment.current.defaults.rx
            .observe([String: NSNumber].self, Constants.UserDefaults.storeTypes)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] storeTypes in
                guard let self else { return }
                self.lock.lock()
                self.storeTypes = storeTypes
                self.lock.unlock()
            })
            .disposed(by: disposeBag)
    }

    func clearAll() {
        let realm = try! Realm()
        let clips = Array(realm.objects(CPYClip.self))
        let deletableClips = clips.filter { !PinnedSnippetStore.shared.isPinned($0.dataHash) }

        // Pinned history is durable until the user explicitly unpins it.
        deletableClips
            .filter { !$0.thumbnailPath.isEmpty }
            .map { $0.thumbnailPath }
            .forEach { PINCache.shared.removeObject(forKey: $0) }
        realm.transaction { realm.delete(deletableClips.filter { !$0.isInvalidated }) }
        AppEnvironment.current.dataCleanService.cleanDatas()
    }

    func delete(with clip: CPYClip) {
        guard !PinnedSnippetStore.shared.isPinned(clip.dataHash) else { return }
        let realm = try! Realm()
        // Delete saved images
        let path = clip.thumbnailPath
        if !path.isEmpty {
            PINCache.shared.removeObject(forKey: path)
        }
        // Delete Realm
        realm.transaction { realm.delete(clip) }
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
        create()
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

        if sanitizeLivePlainTextIfNeeded(pasteboard) {
            lock.lock()
            cachedChangeCount = pasteboard.changeCount
            lock.unlock()
        }
        create()
    }

    @discardableResult
    private func sanitizeLivePlainTextIfNeeded(_ pasteboard: NSPasteboard) -> Bool {
        guard !AppEnvironment.current.excludeAppService.frontProcessIsExcludedApplication() else { return false }
        guard !AppEnvironment.current.excludeAppService.copiedProcessIsExcludedApplications(pasteboard: pasteboard) else { return false }
        guard let corrected = CPYClipData.liveSanitizedPlainText(from: pasteboard),
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
    fileprivate func create() {
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
        let data = CPYClipData(pasteboard: pasteboard, types: types)
        save(with: data)
    }

    func create(with image: NSImage) {
        lock.lock(); defer { lock.unlock() }

        // Create only image data
        let data = CPYClipData(image: image)
        save(with: data)
    }

    fileprivate func save(with data: CPYClipData) {
        let realm = try! Realm()
        // Copy already copied history
        let isCopySameHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.copySameHistory)
        if realm.object(ofType: CPYClip.self, forPrimaryKey: "\(data.hash)") != nil, !isCopySameHistory { return }
        // Don't save invalidated clip
        if let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: "\(data.hash)"), clip.isInvalidated { return }

        // Don't save empty string history
        if data.isOnlyStringType && data.stringValue.isEmpty { return }

        // Overwrite same history
        let isOverwriteHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory)
        let savedHash = isOverwriteHistory ? data.hash : Int.random(in: 0..<1_000_000)

        // Saved time and path
        let unixTime = Int(Date().timeIntervalSince1970)
        let savedPath = CPYUtilities.applicationSupportFolder() + "/\(NSUUID().uuidString).data"
        // Create Realm object
        let clip = CPYClip()
        clip.dataPath = savedPath
        let title = data.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (data.imageDisplayTitle ?? data.stringValue) : data.stringValue
        clip.title = title[0...10000]
        clip.dataHash = "\(savedHash)"
        clip.createdTime = Int(Date().timeIntervalSince1970 * 1000)
        clip.updateTime = unixTime
        clip.primaryType = data.primaryType?.rawValue ?? ""

        DispatchQueue.main.async {
            // Save thumbnail image
            if let thumbnailImage = data.thumbnailImage {
                PINCache.shared.setObjectAsync(thumbnailImage, forKey: "\(unixTime)", completion: nil)
                clip.thumbnailPath = "\(unixTime)"
            }
            if let colorCodeImage = data.colorCodeImage {
                PINCache.shared.setObjectAsync(colorCodeImage, forKey: "\(unixTime)", completion: nil)
                clip.thumbnailPath = "\(unixTime)"
                clip.isColorCode = true
            }
            // Save Realm and .data file
            let dispatchRealm = try! Realm()
            if CPYUtilities.prepareSaveToPath(CPYUtilities.applicationSupportFolder()) {
                if NSKeyedArchiver.archiveRootObject(data, toFile: savedPath) {
                    dispatchRealm.transaction {
                        dispatchRealm.add(clip, update: .all)
                    }
                    self.trimHistoryIfNeeded(in: dispatchRealm)
                }
            }
        }
    }

    private func trimHistoryIfNeeded(in realm: Realm) {
        guard let limit = BoardManHistoryRetentionPolicy.effectiveLimit(),
              limit > 0 else { return }

        let clips = Array(
            realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: false)
        )
        guard clips.count > limit else { return }

        let removableIdentifiers = PinnedSnippetStore.shared.oldestUnpinnedIdentifiers(
            in: clips.map(\.dataHash),
            maximumCount: clips.count - limit
        )
        let overflowingClips = clips.filter { removableIdentifiers.contains($0.dataHash) }
        let removableClips = TextHistoryArchiveStore.shared.clipsSafeToRemove(overflowingClips)
        removableClips
            .filter { !$0.isInvalidated && !$0.thumbnailPath.isEmpty }
            .map { $0.thumbnailPath }
            .forEach { PINCache.shared.removeObject(forKey: $0) }
        let dataPaths = removableClips.filter { !$0.isInvalidated }.map(\.dataPath)
        let identifiers = removableClips.filter { !$0.isInvalidated }.map(\.dataHash)

        realm.transaction {
            realm.delete(removableClips.filter { !$0.isInvalidated })
        }
        HistoryDisplayNameStore.shared.remove(identifiers)
        dataPaths.filter { !$0.isEmpty }.forEach { CPYUtilities.deleteData(at: $0) }
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
        let dictionary = CPYClipData.availableTypesDictinary
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
