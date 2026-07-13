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
    fileprivate var cachedChangeCount = BehaviorRelay<Int>(value: 0)
    fileprivate var storeTypes = [String: NSNumber]()
    fileprivate let scheduler = SerialDispatchQueueScheduler(qos: .userInteractive)
    fileprivate let lock = NSRecursiveLock(name: "com.uniplanck.BoardMan.ClipUpdatable")
    fileprivate var disposeBag = DisposeBag()
    fileprivate var ignoredPasteboardChangeCount: Int?
    fileprivate var ignoredPasteboardFingerprint: Int?

    // MARK: - Clips
    func startMonitoring() {
        disposeBag = DisposeBag()
        storeTypes = AppEnvironment.current.defaults.dictionary(forKey: Constants.UserDefaults.storeTypes) as? [String: NSNumber] ?? AppDelegate.storeTypesDictinary()
        cachedChangeCount.accept(NSPasteboard.general.changeCount)
        // Pasteboard observe timer
        Observable<Int>.interval(.milliseconds(250), scheduler: scheduler)
            .map { _ in NSPasteboard.general.changeCount }
            .withLatestFrom(cachedChangeCount.asObservable()) { ($0, $1) }
            .filter { $0 != $1 }
            .subscribe(onNext: { [weak self] changeCount, _ in
                self?.cachedChangeCount.accept(changeCount)
                self?.create()
            })
            .disposed(by: disposeBag)
        // Store types
        AppEnvironment.current.defaults.rx
            .observe([String: NSNumber].self, Constants.UserDefaults.storeTypes)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.storeTypes = $0
            })
            .disposed(by: disposeBag)
    }

    func clearAll() {
        let realm = try! Realm()
        let clips = realm.objects(CPYClip.self)

        // Delete saved images
        clips
            .filter { !$0.thumbnailPath.isEmpty }
            .map { $0.thumbnailPath }
            .forEach { PINCache.shared.removeObject(forKey: $0) }
        // Delete Realm
        realm.transaction { realm.delete(clips) }
        // Delete writed datas
        AppEnvironment.current.dataCleanService.cleanDatas()
    }

    func delete(with clip: CPYClip) {
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
        cachedChangeCount.accept(cachedChangeCount.value + 1)
    }

    func markCurrentPasteboardChangeAsHandled() {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        cachedChangeCount.accept(pasteboard.changeCount)
        ignoredPasteboardChangeCount = pasteboard.changeCount
        ignoredPasteboardFingerprint = fingerprint(with: pasteboard)
    }

    func ingestCurrentPasteboard() {
        create()
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
        guard let limit = EntitlementGate.historyRetentionLimit(),
              limit > 0 else {
            return
        }

        let clips = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: false)
        guard clips.count > limit else { return }

        let overflowingClips = Array(clips.dropFirst(limit))
        overflowingClips
            .filter { !$0.isInvalidated && !$0.thumbnailPath.isEmpty }
            .map { $0.thumbnailPath }
            .forEach { PINCache.shared.removeObject(forKey: $0) }

        realm.transaction {
            realm.delete(overflowingClips.filter { !$0.isInvalidated })
        }
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
