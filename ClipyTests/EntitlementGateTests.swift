// swiftlint:disable file_length

import Cocoa
import CryptoKit
import Foundation
import Magnet
import RealmSwift
import Testing
@testable import Board_Man

@Suite
final class EntitlementGateTests {

    @Test
    func freeEntitlementDefaults() {
        let entitlement = EntitlementSnapshot.freeDefault
        let service = EntitlementService(snapshot: entitlement)

        #expect(entitlement.plan == .free)
        #expect(entitlement.licenseState == .free)
        #expect(entitlement.features.isEmpty)
        #expect(entitlement.limits.maxHistoryItems == 100)
        #expect(entitlement.limits.maxPinnedItems == 3)
        #expect(entitlement.limits.maxSnippetItems == 5)
        #expect(entitlement.limits.maxSnippetFolders == 0)
        #expect(!EntitlementGate.canUse(feature: .unlimitedHistory, service: service))
    }

    @Test
    func proEntitlementUnlocksExpectedFeatures() {
        let entitlement = EntitlementSnapshot.proActive()
        let service = EntitlementService(snapshot: entitlement)

        for feature in EntitlementFeature.allCases {
            #expect(EntitlementGate.canUse(feature: feature, service: service))
            #expect(!EntitlementGate.requiresUpgrade(for: feature, service: service))
        }

        #expect(EntitlementGate.limit(for: .historyItems, service: service) == nil)
        #expect(EntitlementGate.limit(for: .pinnedItems, service: service) == nil)
        #expect(EntitlementGate.limit(for: .snippetItems, service: service) == nil)
        #expect(EntitlementGate.limit(for: .snippetFolders, service: service) == nil)
    }

    @Test
    func ownerLifetimeEntitlementUnlocksThroughCentralGate() {
        let metadata = LicenseMetadata(
            licenseKeyMasked: "owner-token-placeholder",
            deviceIdMasked: "****ABCD",
            activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: LicenseState.ownerLifetime.rawValue,
            licenseKind: .ownerLifetime,
            issuedTo: "developer-owner"
        )
        let entitlement = EntitlementSnapshot.ownerLifetime(metadata: metadata)
        let service = EntitlementService(snapshot: entitlement)

        #expect(entitlement.plan == .ownerLifetime)
        #expect(entitlement.licenseState == .ownerLifetime)
        #expect(entitlement.isProEntitled)

        for feature in EntitlementFeature.allCases {
            #expect(EntitlementGate.canUse(feature: feature, service: service))
        }

        #expect(EntitlementGate.limit(for: .historyItems, service: service) == nil)
        #expect(EntitlementGate.limit(for: .pinnedItems, service: service) == nil)
        #expect(EntitlementGate.limit(for: .snippetItems, service: service) == nil)
        #expect(EntitlementGate.limit(for: .snippetFolders, service: service) == nil)
    }

    @Test
    func freeHistoryLimitIsOneHundred() {
        let service = EntitlementService(snapshot: .freeDefault)

        #expect(EntitlementGate.canAddHistoryItem(currentCount: 99, service: service))
        #expect(!EntitlementGate.canAddHistoryItem(currentCount: 100, service: service))
        #expect(EntitlementGate.historyRetentionLimit(service: service) == 100)
    }

    @Test
    func freeHistoryUsesRetentionInsteadOfCreationBlocking() {
        let service = EntitlementService(snapshot: .freeDefault)
        var storedHistoryCount = 100

        storedHistoryCount += 1
        if let limit = EntitlementGate.historyRetentionLimit(service: service),
           storedHistoryCount > limit {
            storedHistoryCount = limit
        }

        #expect(storedHistoryCount == 100)
    }

    @Test
    func freePinnedLimitIsThree() {
        let service = EntitlementService(snapshot: .freeDefault)

        #expect(EntitlementGate.canPinItem(currentPinnedCount: 2, service: service))
        #expect(!EntitlementGate.canPinItem(currentPinnedCount: 3, service: service))
    }

    @Test
    func pinnedHistorySurvivesStoreReloadAndIsExcludedFromRetentionDeletion() throws {
        let suiteName = "PinnedSnippetStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PinnedSnippetStore(defaults: defaults, timedPinIdentifiers: { [] })
        #expect(store.add("pinned-history"))
        #expect(PinnedSnippetStore(defaults: defaults, timedPinIdentifiers: { [] }).isPinned("pinned-history"))

        let removable = store.oldestUnpinnedIdentifiers(
            in: ["newest", "pinned-history", "oldest"],
            maximumCount: 2
        )
        #expect(removable == Set(["oldest", "newest"]))
        #expect(!removable.contains("pinned-history"))
    }

    @Test
    func historyDisplayNamePersistsAndNameOnlyRequiresAName() throws {
        let suiteName = "HistoryDisplayNameStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HistoryDisplayNameStore(defaults: defaults)
        store.setName("Deploy command", for: "history-1")
        store.setNameOnly(true, for: "history-1")

        let reloaded = HistoryDisplayNameStore(defaults: defaults)
        #expect(reloaded.name(for: "history-1") == "Deploy command")
        #expect(reloaded.isNameOnly("history-1"))

        reloaded.setName("", for: "history-1")
        #expect(reloaded.name(for: "history-1") == nil)
        #expect(!reloaded.isNameOnly("history-1"))
    }

    @Test
    func configuredHistoryLimitIsCappedByEntitlement() throws {
        let suiteName = "HistoryRetentionPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(40, forKey: Constants.UserDefaults.maxHistorySize)
        #expect(BoardManHistoryRetentionPolicy.effectiveLimit(defaults: defaults, entitlementLimit: 100) == 40)
        #expect(BoardManHistoryRetentionPolicy.effectiveLimit(defaults: defaults, entitlementLimit: nil) == 40)

        defaults.set(500, forKey: Constants.UserDefaults.maxHistorySize)
        #expect(BoardManHistoryRetentionPolicy.effectiveLimit(defaults: defaults, entitlementLimit: 100) == 100)
    }

    @Test
    func overflowArchiveStoresTextWithDateAndSkipsImages() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextHistoryArchiveStoreTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("history.jsonl")
        defer { try? FileManager.default.removeItem(at: root) }

        let textClip = CPYClip()
        textClip.dataHash = "text-entry"
        textClip.title = "git status --short"
        textClip.updateTime = 1_700_000_000
        textClip.primaryType = NSPasteboard.PasteboardType.string.rawValue

        let imageClip = CPYClip()
        imageClip.dataHash = "image-entry"
        imageClip.title = "image pixels"
        imageClip.updateTime = 1_700_000_001
        imageClip.primaryType = NSPasteboard.PasteboardType.png.rawValue

        let store = TextHistoryArchiveStore(fileURL: fileURL)
        let removable = store.clipsSafeToRemove([textClip, imageClip])
        #expect(Set(removable.map(\.dataHash)) == Set(["text-entry", "image-entry"]))
        let entries = try store.readEntries()
        #expect(entries == [ArchivedTextHistoryEntry(
            identifier: "text-entry",
            copiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            content: "git status --short"
        )])
        let rawContents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(rawContents.contains("2023-11-14T22:13:20Z"))
        #expect(!rawContents.contains("image pixels"))
    }

    @Test
    func freeSnippetLimitIsFive() {
        let service = EntitlementService(snapshot: .freeDefault)

        #expect(EntitlementGate.canCreateSnippet(currentSnippetCount: 4, service: service))
        #expect(!EntitlementGate.canCreateSnippet(currentSnippetCount: 5, service: service))
    }

    @Test
    func freeCannotCreateSnippetFolders() {
        let service = EntitlementService(snapshot: .freeDefault)

        #expect(!EntitlementGate.canCreateSnippetFolder(currentFolderCount: 0, service: service))
        #expect(!EntitlementGate.canCreateSnippetFolder(currentFolderCount: 1, service: service))
    }

    @Test
    func overLimitExistingCountsAreNotMutatedByGate() {
        let service = EntitlementService(snapshot: .freeDefault)
        let existingPinnedCount = 10
        let existingSnippetCount = 12

        #expect(!EntitlementGate.canPinItem(currentPinnedCount: existingPinnedCount, service: service))
        #expect(!EntitlementGate.canCreateSnippet(currentSnippetCount: existingSnippetCount, service: service))
        #expect(existingPinnedCount == 10)
        #expect(existingSnippetCount == 12)
    }

    @Test
    func proAllowsRuntimeActions() {
        let service = EntitlementService(snapshot: .proActive())

        #expect(EntitlementGate.canAddHistoryItem(currentCount: 10_000, service: service))
        #expect(EntitlementGate.canPinItem(currentPinnedCount: 10_000, service: service))
        #expect(EntitlementGate.canCreateSnippet(currentSnippetCount: 10_000, service: service))
        #expect(EntitlementGate.canCreateSnippetFolder(currentFolderCount: 10_000, service: service))
    }

    @Test
    func timedPinStoreEnforcesFreeLimitAndExpires() {
        let suiteName = "BoardManTimedPinStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var currentDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = BoardManTimedPinStore(defaults: defaults, now: { currentDate })

        #expect(store.setPin("first", durationValue: 1, unit: .hours, maximumActiveCount: 3))
        #expect(store.setPin("second", durationValue: 1, unit: .hours, maximumActiveCount: 3))
        #expect(store.setPin("third", durationValue: 1, unit: .weeks, maximumActiveCount: 3))
        #expect(!store.setPin("fourth", durationValue: 1, unit: .days, maximumActiveCount: 3))
        #expect(store.isPinned("first"))

        currentDate = currentDate.addingTimeInterval(3_601)
        #expect(store.removeExpired())
        #expect(!store.isPinned("first"))
        #expect(!store.isPinned("second"))
        #expect(store.isPinned("third"))
        #expect(store.setPin("fourth", durationValue: 1, unit: .days, maximumActiveCount: 3))
    }

    @Test
    func itemHighlightStoreRoundTripsAndClears() {
        let suiteName = "BoardManHighlightStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BoardManItemHighlightStore(defaults: defaults)

        store.set(.purple, for: "item")
        #expect(store.highlight(for: "item") == .purple)
        store.set(nil, for: "item")
        #expect(store.highlight(for: "item") == nil)
    }

    @Test
    func historyCSVExporterEscapesCommasQuotesAndNewlines() {
        let row = BoardManHistoryCSVRow(
            copiedAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 1),
            displayName: "name, one",
            content: "line \"one\"\nline two",
            pasteCount: 3,
            isPinned: true,
            primaryType: "public.utf8-plain-text"
        )
        let csv = BoardManHistoryCSVExporter.csv(rows: [row])

        #expect(csv.contains("\"name, one\""))
        #expect(csv.contains("\"line \"\"one\"\"\nline two\""))
        #expect(csv.contains(",3,true,public.utf8-plain-text"))
    }

    @Test
    func inactiveStatesDoNotBehaveAsActivePro() {
        let inactiveStates: [LicenseState] = [.locked, .invalid, .proExpired]

        for state in inactiveStates {
            let entitlement = EntitlementSnapshot(
                plan: .pro,
                licenseState: state,
                features: Set(EntitlementFeature.allCases),
                limits: .proDefault
            )
            let service = EntitlementService(snapshot: entitlement)

            #expect(!entitlement.isProEntitled)
            #expect(!EntitlementGate.canUse(feature: .unlimitedHistory, service: service))
        }
    }

    @Test
    func offlineGraceIsConservativeInMVP() {
        let entitlement = EntitlementSnapshot(
            plan: .pro,
            licenseState: .offlineGrace,
            features: Set(EntitlementFeature.allCases),
            limits: .proDefault,
            offlineGraceExpiresAt: Date().addingTimeInterval(3600)
        )
        let service = EntitlementService(snapshot: entitlement)

        #expect(!entitlement.isProEntitled)
        #expect(!EntitlementGate.canUse(feature: .unlimitedHistory, service: service))
    }

    @Test
    func signedOwnerTokenRequiresValidSignatureAndDeviceBinding() throws {
        let privateKey = P256.Signing.PrivateKey()
        let deviceID = UUID().uuidString
        let token = try makeOwnerToken(privateKey: privateKey, deviceID: deviceID)
        let verifier = P256SignedLicenseTokenVerifier(
            publicKeyBase64: privateKey.publicKey.x963Representation.base64EncodedString()
        )
        let context = SignedLicenseTokenVerificationContext(
            deviceID: deviceID,
            bundleID: "com.uniplanck.BoardMan",
            verificationDate: Date()
        )

        let verified = verifier.verify(token, context: context)
        if case .verified(let payload) = verified {
            #expect(payload.plan == .ownerLifetime)
            #expect(payload.state == .ownerLifetime)
            #expect(payload.isLifetime)
        } else {
            Issue.record("Expected the valid owner token to verify.")
        }

        let wrongDevice = SignedLicenseTokenVerificationContext(
            deviceID: UUID().uuidString,
            bundleID: "com.uniplanck.BoardMan",
            verificationDate: Date()
        )
        #expect(verifier.verify(token, context: wrongDevice) == .invalid(.deviceMismatch))

        let tampered = token + "x"
        #expect(verifier.verify(tampered, context: context) == .invalid(.signatureInvalid))
    }

    @Test
    func signedLicenseTokenFileStoreRoundTripsWithoutKeychain() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManLicenseStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let deviceID = UUID().uuidString
        let rawToken = try makeOwnerToken(privateKey: P256.Signing.PrivateKey(), deviceID: deviceID)
        let token = try SignedLicenseToken(rawValue: rawToken)
        let fileURL = directoryURL.appendingPathComponent("owner-license.jwt")
        let store = SignedLicenseTokenFileStore(fileURL: fileURL)

        try store.storeVerifiedSignedLicenseToken(token)

        #expect(store.loadSignedLicenseToken() == rawToken)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test
    func localDeviceIdentityPersistsWithoutKeychain() {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManDeviceIdentityTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("device-id")
        let firstID = LocalDeviceIdentityService(fileURL: fileURL).deviceID()
        let secondID = LocalDeviceIdentityService(fileURL: fileURL).deviceID()

        #expect(UUID(uuidString: firstID) != nil)
        #expect(secondID == firstID)
    }

    private func makeOwnerToken(privateKey: P256.Signing.PrivateKey,
                                deviceID: String) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: [
            "alg": "ES256",
            "kid": "test-owner-v1",
            "typ": "JWT"
        ], options: [.sortedKeys])
        let payload = try JSONSerialization.data(withJSONObject: [
            "license_id": "OWNER-TEST",
            "license_kind": "ownerLifetime",
            "plan": "ownerLifetime",
            "state": "ownerLifetime",
            "features": EntitlementFeature.allCases.map(\.rawValue),
            "issued_to": "test-owner",
            "sub": "test-owner",
            "iat": Int(Date().timeIntervalSince1970),
            "is_lifetime": true,
            "device_id": deviceID,
            "bundle_id": "com.uniplanck.BoardMan",
            "token_version": 1
        ], options: [.sortedKeys])
        let signingInput = "\(base64URL(header)).\(base64URL(payload))"
        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64URL(signature.rawRepresentation))"
    }

    private func base64URL(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

@Suite(.serialized)
final class LegacySnippetMigrationTests {

    @Test
    func restoresNewestLegacySnippetsWithoutCopyingHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationURL = root.appendingPathComponent("current/default.realm")
        let olderSourceURL = root.appendingPathComponent("older/default.realm")
        let newerSourceURL = root.appendingPathComponent("newer/default.realm")
        let backupURL = root.appendingPathComponent("backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = try makeRealm(at: destinationURL)
        try destination.write {
            let clip = CPYClip()
            clip.dataHash = "keep-current-history"
            clip.title = "Current history"
            destination.add(clip)
        }

        try createLegacyRealm(at: olderSourceURL, snippetCount: 1)
        try createLegacyRealm(at: newerSourceURL, snippetCount: 2)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: olderSourceURL.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: newerSourceURL.path)

        let result = LegacySnippetMigrationService.migrateIfNeeded(
            into: destination,
            candidateURLs: [olderSourceURL, newerSourceURL],
            backupDirectoryURL: backupURL
        )

        #expect(result == .restored(sourceDirectory: "newer", folderCount: 1, snippetCount: 2))
        #expect(destination.objects(CPYClip.self).count == 1)
        #expect(destination.objects(CPYFolder.self).count == 1)
        #expect(destination.objects(CPYSnippet.self).count == 2)
        #expect(destination.objects(CPYFolder.self).first?.snippets.count == 2)
        #expect((try FileManager.default.contentsOfDirectory(at: backupURL, includingPropertiesForKeys: nil)).count == 1)
    }

    @Test
    func mergesMissingLegacySnippetsWithoutOverwritingCurrentData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationURL = root.appendingPathComponent("current/default.realm")
        let sourceURL = root.appendingPathComponent("legacy/default.realm")
        let backupURL = root.appendingPathComponent("backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = try makeRealm(at: destinationURL)
        try destination.write {
            let snippet = CPYSnippet()
            snippet.identifier = "current-only"
            snippet.title = "Current"
            snippet.content = "Keep me"
            destination.add(snippet)
        }
        try createLegacyRealm(at: sourceURL, snippetCount: 2)

        let result = LegacySnippetMigrationService.migrateIfNeeded(
            into: destination,
            candidateURLs: [sourceURL],
            backupDirectoryURL: backupURL
        )

        #expect(result == .restored(sourceDirectory: "legacy", folderCount: 1, snippetCount: 2))
        #expect(destination.objects(CPYSnippet.self).count == 3)
        #expect(destination.object(ofType: CPYSnippet.self, forPrimaryKey: "current-only")?.content == "Keep me")
        #expect((try FileManager.default.contentsOfDirectory(at: backupURL, includingPropertiesForKeys: nil)).count == 1)
    }

    @Test
    func skipsMigrationWhenAllLegacyIdentifiersAlreadyExist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationURL = root.appendingPathComponent("current/default.realm")
        let sourceURL = root.appendingPathComponent("legacy/default.realm")
        let backupURL = root.appendingPathComponent("backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = try makeRealm(at: destinationURL)
        try addLegacyData(to: destination, snippetCount: 2)
        try createLegacyRealm(at: sourceURL, snippetCount: 2)

        let result = LegacySnippetMigrationService.migrateIfNeeded(
            into: destination,
            candidateURLs: [sourceURL],
            backupDirectoryURL: backupURL
        )

        #expect(result == .skippedExistingData)
        #expect(destination.objects(CPYSnippet.self).count == 2)
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
    }

    private func makeRealm(at url: URL) throws -> Realm {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Realm.Configuration(fileURL: url)
        configuration.schemaVersion = LegacySnippetMigrationService.schemaVersion
        configuration.objectTypes = [CPYClip.self, CPYFolder.self, CPYSnippet.self]
        return try Realm(configuration: configuration)
    }

    private func createLegacyRealm(at url: URL, snippetCount: Int) throws {
        let seedURL = url.deletingLastPathComponent()
            .appendingPathComponent("seed-\(UUID().uuidString).realm")
        let realm = try makeRealm(at: seedURL)
        try addLegacyData(to: realm, snippetCount: snippetCount)
        try realm.writeCopy(toFile: url)
        realm.invalidate()
    }

    private func addLegacyData(to realm: Realm, snippetCount: Int) throws {
        try realm.write {
            let folder = CPYFolder()
            folder.identifier = "legacy-folder"
            folder.title = "Legacy"
            folder.index = 0
            for index in 0..<snippetCount {
                let snippet = CPYSnippet()
                snippet.identifier = "legacy-snippet-\(index)"
                snippet.index = index
                snippet.title = "Snippet \(index)"
                snippet.content = "Content \(index)"
                folder.snippets.append(snippet)
            }
            realm.add(folder)

            let clip = CPYClip()
            clip.dataHash = "legacy-history-\(snippetCount)"
            realm.add(clip)
        }
    }
}

@Suite(.serialized)
final class LegacyHistoryRecoveryTests {

    @Test
    func restoresMissingTextHistoryAndPreservesCurrentData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationURL = root.appendingPathComponent("current/default.realm")
        let sourceURL = root.appendingPathComponent("legacy/default.realm")
        let backupURL = root.appendingPathComponent("backups", isDirectory: true)
        let dataURL = root.appendingPathComponent("data", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = try makeRealm(at: destinationURL)
        try destination.write {
            let current = CPYClip()
            current.dataHash = "current"
            current.title = "Keep current"
            destination.add(current)
        }

        let source = try makeRealm(at: sourceURL)
        try source.write {
            let text = CPYClip()
            text.dataHash = "legacy-text"
            text.title = "git status --short"
            text.primaryType = NSPasteboard.PasteboardType.deprecatedString.rawValue
            text.createdTime = 1_700_000_000_000
            text.updateTime = 1_700_000_000
            text.dataPath = root.appendingPathComponent("missing-text.data").path
            source.add(text)

            let image = CPYClip()
            image.dataHash = "legacy-image"
            image.title = "PNG image"
            image.primaryType = NSPasteboard.PasteboardType.png.rawValue
            image.dataPath = root.appendingPathComponent("missing-image.data").path
            source.add(image)
        }
        source.invalidate()

        let result = LegacyHistoryRecoveryService.migrateIfNeeded(
            into: destination,
            candidateURLs: [sourceURL],
            backupDirectoryURL: backupURL,
            dataDirectoryURL: dataURL
        )

        #expect(result == .restored(sourceDirectory: "legacy", historyCount: 1, skippedCount: 1))
        #expect(destination.objects(CPYClip.self).count == 2)
        #expect(destination.object(ofType: CPYClip.self, forPrimaryKey: "current")?.title == "Keep current")
        let restored = try #require(destination.object(ofType: CPYClip.self, forPrimaryKey: "legacy-text"))
        #expect(restored.title == "git status --short")
        #expect(restored.createdTime == 1_700_000_000_000)
        #expect(FileManager.default.fileExists(atPath: restored.dataPath))
        #expect(destination.object(ofType: CPYClip.self, forPrimaryKey: "legacy-image") == nil)
        #expect((try FileManager.default.contentsOfDirectory(at: backupURL, includingPropertiesForKeys: nil)).count == 1)
    }

    private func makeRealm(at url: URL) throws -> Realm {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Realm.Configuration(fileURL: url)
        configuration.schemaVersion = LegacySnippetMigrationService.schemaVersion
        configuration.objectTypes = [CPYClip.self, CPYFolder.self, CPYSnippet.self]
        return try Realm(configuration: configuration)
    }
}

@Suite
struct PasteCountInputServiceTests {
    @Test
    func eventTapUsesAccessibilityFallbackWithoutInputMonitoring() {
        #expect(PasteCountInputService.eventTapMode(
            accessibilityTrusted: true,
            listenEventAccess: false
        ) == .accessibilityFallback)
        #expect(PasteCountInputService.eventTapMode(
            accessibilityTrusted: false,
            listenEventAccess: true
        ) == .listenOnly)
        #expect(PasteCountInputService.eventTapMode(
            accessibilityTrusted: false,
            listenEventAccess: false
        ) == nil)
    }

    @Test
    func recentUseOrderDoesNotOverwriteCopyOrder() throws {
        var configuration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        configuration.objectTypes = [CPYClip.self]
        let realm = try Realm(configuration: configuration)
        let defaultsSuite = "BoardManHistoryOrderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let olderClip = CPYClip()
        olderClip.dataHash = "older"
        olderClip.createdTime = 1_000
        olderClip.updateTime = 100

        let newerClip = CPYClip()
        newerClip.dataHash = "newer"
        newerClip.createdTime = 2_000
        newerClip.updateTime = 200

        try realm.write {
            realm.add([olderClip, newerClip])
        }

        #expect(realm.objects(CPYClip.self)
            .sorted(byKeyPath: #keyPath(CPYClip.createdTime), ascending: false)
            .first?.dataHash == "newer")
        #expect(PasteCountStore(defaults: defaults).markUsed(clip: olderClip, in: realm))
        #expect(olderClip.createdTime == 1_000)
        #expect(realm.objects(CPYClip.self)
            .sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: false)
            .first?.dataHash == "older")
        #expect(realm.objects(CPYClip.self)
            .sorted(byKeyPath: #keyPath(CPYClip.createdTime), ascending: false)
            .first?.dataHash == "newer")
    }

    @Test
    func clipboardTextReconciliationRemovesOnlyExactDuplicatedLineBreaks() {
        let richText = "A\nB\n\nC"
        let duplicatedPlainText = "A\n\nB\n\n\n\nC"

        #expect(CPYClipData.preferredTextValue(
            plainText: duplicatedPlainText,
            richText: richText
        ) == richText)
    }

    @Test
    func clipboardTextReconciliationHandlesChromeHTMLTrailingLineBreak() {
        let chromePlainText = "A\n\nB\n\nC"
        let htmlAsText = "A\nB\nC\n"
        #expect(CPYClipData.preferredTextValue(
            plainText: chromePlainText,
            richText: htmlAsText
        ) == "A\nB\nC")
    }

    @Test
    func clipboardTextReconciliationPreservesIntentionalBlankLinesWithoutProof() {
        let intentionalBlankLine = "A\nB\n\nC"
        #expect(CPYClipData.preferredTextValue(
            plainText: intentionalBlankLine,
            richText: nil
        ) == intentionalBlankLine)

        let nonMatchingRichText = "A\nB\nC"
        #expect(CPYClipData.preferredTextValue(
            plainText: intentionalBlankLine,
            richText: nonMatchingRichText
        ) == intentionalBlankLine)
    }

    @Test
    func clipboardTextReconciliationCanonicalizesLineEndingEncoding() {
        #expect(CPYClipData.preferredTextValue(
            plainText: "A\r\nB\r\n\r\nC",
            richText: nil
        ) == "A\nB\n\nC")
    }

    @Test
    func pasteCountCacheUpdatesImmediatelyAndFlushesToDefaults() throws {
        let defaultsSuite = "PasteCountCacheTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let clip = CPYClip()
        clip.dataHash = "cached-count"
        clip.title = "cached paste count"
        clip.primaryType = NSPasteboard.PasteboardType.string.rawValue

        let seedStore = PasteCountStore(defaults: defaults)
        let key = seedStore.key(for: clip)
        defaults.set([key: NSNumber(value: 41)], forKey: Constants.UserDefaults.pasteCounts)

        let store = PasteCountStore(defaults: defaults)
        #expect(store.count(for: clip) == 41)
        #expect(store.increment(forKey: key))
        #expect(store.count(for: clip) == 42)

        store.flushPendingPersistence()
        let persisted = defaults.dictionary(forKey: Constants.UserDefaults.pasteCounts) as? [String: NSNumber]
        #expect(persisted?[key]?.intValue == 42)
    }

    @Test
    func pasteCountRequiresObservedEditableTargetChange() {
        let unchanged = PasteTargetSnapshot(
            processIdentifier: 100,
            role: "AXTextArea",
            valueFingerprint: 10,
            selectedTextFingerprint: 20,
            selectedRange: CFRange(location: 4, length: 0),
            numberOfCharacters: 12,
            childrenCount: 0
        )
        #expect(!PasteCountInputService.pasteTargetChanged(from: unchanged, to: unchanged))

        let changedValue = PasteTargetSnapshot(
            processIdentifier: 100,
            role: "AXTextArea",
            valueFingerprint: 11,
            selectedTextFingerprint: 20,
            selectedRange: CFRange(location: 4, length: 0),
            numberOfCharacters: 13,
            childrenCount: 0
        )
        #expect(PasteCountInputService.pasteTargetChanged(from: unchanged, to: changedValue))

        let differentApplication = PasteTargetSnapshot(
            processIdentifier: 200,
            role: "AXTextArea",
            valueFingerprint: 11,
            selectedTextFingerprint: 21,
            selectedRange: CFRange(location: 5, length: 0),
            numberOfCharacters: 13,
            childrenCount: 1
        )
        #expect(!PasteCountInputService.pasteTargetChanged(from: unchanged, to: differentApplication))
    }

    @Test
    func historyConditionCombinesLengthWordsExclusionsAndShellDetection() {
        let condition = BoardManHistoryCondition(
            isEnabled: true,
            minimumLength: 12,
            includedTerms: ["git", "status"],
            excludedTerms: ["force"],
            matchesAllIncludedTerms: true,
            shellLikeOnly: true
        )
        #expect(condition.matches("git status && echo done"))
        #expect(!condition.matches("git status --force"))
        #expect(!condition.matches("A normal sentence mentioning git status."))
        #expect(!condition.matches("git"))

        let anyCondition = BoardManHistoryCondition(
            isEnabled: true,
            minimumLength: 0,
            includedTerms: ["lambda", "cloudflare"],
            excludedTerms: [],
            matchesAllIncludedTerms: false,
            shellLikeOnly: false
        )
        #expect(anyCondition.matches("Cloudflare deployment finished"))
        #expect(!anyCondition.matches("No matching platform"))
        #expect(BoardManHistoryCondition.parsedTerms("git, docker\ncloudflare") == ["git", "docker", "cloudflare"])
    }

    @Test
    func imageFingerprintSurvivesArchiveRoundTripAndDistinguishesPixels() throws {
        let firstImage = testImage(color: .systemRed)
        let secondImage = testImage(color: .systemBlue)
        let encoded = try NSKeyedArchiver.archivedData(
            withRootObject: CPYClipData(image: firstImage),
            requiringSecureCoding: false
        )
        let decodedObject = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encoded)
        let decodedData = try #require(decodedObject as? CPYClipData)
        let decodedImage = try #require(decodedData.image)

        #expect(PasteCountStore.imageFingerprint(for: firstImage) == PasteCountStore.imageFingerprint(for: decodedImage))
        #expect(PasteCountStore.imageFingerprint(for: firstImage) != PasteCountStore.imageFingerprint(for: secondImage))
    }

    private func testImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 12, height: 12)).fill()
        image.unlockFocus()
        return image
    }
}

@MainActor @Suite(.serialized)
final class BoardManInteractionRuleTests {

    @Test
    func previewScaleAndHorizontalNavigationRulesAreBounded() {
        #expect(BoardManPanel.clampedPreviewScale(0) == 100)
        #expect(BoardManPanel.clampedPreviewScale(20) == 50)
        #expect(BoardManPanel.clampedPreviewScale(250) == 200)
        #expect(BoardManPanel.effectivePreviewScale(storedValue: 50, isPro: false) == 100)
        #expect(BoardManPanel.effectivePreviewScale(storedValue: 50, isPro: true) == 50)
        #expect(BoardManPanel.effectivePreviewScale(storedValue: 200, isPro: true) == 200)

        #expect(BoardManPanel.tabDelta(horizontalDelta: -30, verticalDelta: 3) == 1)
        #expect(BoardManPanel.tabDelta(horizontalDelta: 30, verticalDelta: 3) == -1)
        #expect(BoardManPanel.tabDelta(horizontalDelta: 10, verticalDelta: 0) == nil)
        #expect(BoardManPanel.tabDelta(horizontalDelta: 30, verticalDelta: 28) == nil)
        #expect(BoardManPanel.restoredSnippetSelectionIndex(origin: 2, itemCount: 4) == 2)
        #expect(BoardManPanel.restoredSnippetSelectionIndex(origin: -1, itemCount: 4) == -1)
        #expect(BoardManPanel.restoredSnippetSelectionIndex(origin: 4, itemCount: 4) == -1)

        #expect(BoardManPanel.shouldBeginEditorContainerClick(
            isSnippetTab: true,
            isEditing: false,
            hasSelection: true
        ))
        #expect(!BoardManPanel.shouldBeginEditorContainerClick(
            isSnippetTab: true,
            isEditing: true,
            hasSelection: true
        ))
    }

    @Test
    func snippetDraftPersistenceUpdatesTitleContentAndEnabledStates() throws {
        let configuration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        let realm = try Realm(configuration: configuration)
        let snippet = CPYSnippet()
        snippet.title = "Before"
        snippet.content = "old"
        snippet.enable = false
        let folder = CPYFolder()
        folder.title = "Commands"
        folder.enable = false
        folder.snippets.append(snippet)
        try realm.write { realm.add(folder) }

        BoardManPanel.persistSnippetDraft(
            title: "tmux",
            content: "tmux new -A -s",
            snippetEnabled: true,
            folderEnabled: true,
            canEditFolder: true,
            snippet: snippet,
            folder: folder,
            realm: realm
        )
        #expect(snippet.title == "tmux")
        #expect(snippet.content == "tmux new -A -s")
        #expect(snippet.enable)
        #expect(folder.enable)

        BoardManPanel.persistSnippetDraft(
            title: "free edit",
            content: "echo free",
            snippetEnabled: false,
            folderEnabled: false,
            canEditFolder: false,
            snippet: snippet,
            folder: folder,
            realm: realm
        )
        #expect(snippet.title == "free edit")
        #expect(!snippet.enable)
        #expect(folder.enable, "Free editing must not mutate Pro-only folder state.")
    }

    @Test
    func timedPinWeeksAndLocalizedThemeTitlesAreSupported() {
        #expect(BoardManTimedPinUnit.weeks.interval(value: 2) == 1_209_600)
        #expect(BoardManTimedPinUnit.weeks.summary(value: 2).contains("2"))

        let defaults = AppEnvironment.current.defaults
        let originalLanguage = defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        defaults.set("日本語", forKey: Constants.UserDefaults.boardManLanguage)
        defer { defaults.set(originalLanguage, forKey: Constants.UserDefaults.boardManLanguage) }
        #expect(BoardManThemePreset.graphite.title == "グラファイト")
        #expect(BoardManThemePreset.ocean.title == "オーシャン")
    }

    @Test
    func hoverPopupTracksPointerStateWithoutOpeningDuringTests() {
        let popup = BoardManHoverPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 30), pullsDown: false)
        #expect(!popup.isHovering)
        popup.setHoveringForTesting(true)
        #expect(popup.isHovering)
        popup.setHoveringForTesting(false)
        #expect(!popup.isHovering)
    }

    @Test
    func relativeTimestampDropdownStylesCoverPaddingUnitsSuffixAndNow() {
        let defaults = AppEnvironment.current.defaults
        let originalLanguage = defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        defaults.set(BoardManLanguage.english.rawValue, forKey: Constants.UserDefaults.boardManLanguage)
        defer { defaults.set(originalLanguage, forKey: Constants.UserDefaults.boardManLanguage) }

        let singleSymbol = BoardManRelativeTimestampStyle(
            number: .single,
            unit: .symbol,
            suffix: .none,
            now: .localized
        )
        #expect(singleSymbol.text(seconds: 30, language: .japanese) == "今")
        #expect(singleSymbol.text(seconds: 61, language: .english) == "1m")
        #expect(singleSymbol.text(seconds: 3_661, language: .english) == "1h")
        #expect(singleSymbol.text(seconds: 90_000, language: .english) == "1d")

        let paddedFull = BoardManRelativeTimestampStyle(
            number: .twoDigits,
            unit: .full,
            suffix: .ago,
            now: .now
        )
        #expect(paddedFull.text(seconds: 61, language: .english) == "01 min ago")
        #expect(paddedFull.text(seconds: 3_661, language: .english) == "01 hour ago")
        #expect(BoardManRelativeNumberStyle.twoDigits.text(123) == "123")

        let localized = BoardManRelativeTimestampStyle(
            number: .single,
            unit: .localized,
            suffix: .localized,
            now: .localized
        )
        #expect(localized.text(seconds: 61, language: .japanese) == "1分前")
        #expect(localized.text(seconds: 3_661, language: .simplifiedChinese) == "1小时前")
        #expect(localized.text(seconds: 90_000, language: .korean) == "1 일 전")

        let now = Date(timeIntervalSince1970: 100_000)
        #expect(BoardManPanel.timestampText(
            for: 99_939,
            format: "relative",
            relativeStyle: singleSymbol,
            now: now
        ) == "1m")
    }

    @Test
    func timestampShortcutDefaultsToCommandVAndPersistsCustomValue() throws {
        let suiteName = "BoardManTimestampShortcutTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let defaultShortcut = BoardManTimestampShortcutStore.keyCombo(defaults: defaults)
        #expect(defaultShortcut.QWERTYKeyCode == 9)
        #expect(defaultShortcut.keyEquivalentModifierMask.contains(.command))
        #expect(defaultShortcut.keyEquivalent.uppercased() == "V")
        #expect(BoardManTimestampInteraction.allowed(nil) == .click)
        #expect(BoardManTimestampInteraction.allowed("longPress") == .longPress)

        let customShortcut = KeyCombo(QWERTYKeyCode: 11, cocoaModifiers: [.command, .shift])
        BoardManTimestampShortcutStore.save(try #require(customShortcut), defaults: defaults)
        let restored = BoardManTimestampShortcutStore.keyCombo(defaults: defaults)
        #expect(restored.QWERTYKeyCode == 11)
        #expect(restored.keyEquivalentModifierMask.contains(.command))
        #expect(restored.keyEquivalentModifierMask.contains(.shift))
        #expect(BoardManPanel.clampedTimestampShortcutDelay(-1) == 0)
        #expect(BoardManPanel.clampedTimestampShortcutDelay(0.1) == 0.1)
        #expect(BoardManPanel.clampedTimestampShortcutDelay(120) == 60)
    }

    @Test
    func timedPinPresetsCanBeAddedEditedSelectedRemovedAndPersisted() throws {
        let suiteName = "BoardManTimedPinPresetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(2, forKey: Constants.UserDefaults.boardManTimedPinDurationValue)
        defaults.set(BoardManTimedPinUnit.hours.rawValue, forKey: Constants.UserDefaults.boardManTimedPinDurationUnit)

        let initial = BoardManTimedPinPresetStore.presets(defaults: defaults)
        #expect(initial.count >= 3)
        #expect(initial[0].value == 2)
        #expect(initial[0].unit == .hours)

        let added = BoardManTimedPinPresetStore.add(defaults: defaults)
        #expect(BoardManTimedPinPresetStore.selectedPreset(defaults: defaults).id == added.id)
        let edited = BoardManTimedPinPresetStore.updateSelected(value: 15, unit: .minutes, defaults: defaults)
        #expect(edited.value == 15)
        #expect(edited.unit == .minutes)
        #expect(BoardManTimedPinPresetStore.presets(defaults: defaults).contains(edited))
        #expect(BoardManTimedPinPresetStore.removeSelected(defaults: defaults))
        #expect(!BoardManTimedPinPresetStore.presets(defaults: defaults).contains(where: { $0.id == added.id }))
    }

}

@MainActor @Suite(.serialized)
final class BoardManPanelLayoutTests {

    @Test
    func majorTabsAndSettingsCategoriesStayInsidePanel() async {
        let originalRealmConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        defer { Realm.Configuration.defaultConfiguration = originalRealmConfiguration }

        let defaults = AppEnvironment.current.defaults
        let originalTimestampFormat = defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat)
        let originalTimestampPosition = defaults.string(forKey: Constants.UserDefaults.boardManTimestampPosition)
        let originalLanguage = defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        defaults.set("relative", forKey: Constants.UserDefaults.boardManTimestampFormat)
        defaults.set("below", forKey: Constants.UserDefaults.boardManTimestampPosition)
        defaults.set("English", forKey: Constants.UserDefaults.boardManLanguage)
        defer {
            defaults.set(originalTimestampFormat, forKey: Constants.UserDefaults.boardManTimestampFormat)
            defaults.set(originalTimestampPosition, forKey: Constants.UserDefaults.boardManTimestampPosition)
            defaults.set(originalLanguage, forKey: Constants.UserDefaults.boardManLanguage)
        }

        let panel = BoardManPanel()
        panel.setFrame(NSRect(x: 0, y: 0, width: 680, height: 760), display: false)
        await settlePanelLayout(panel)
        #expect(panel.presentationItemScope == .historyOnly)
        assertTopLevelLayout(panel, mode: "History", expectsSearch: true)
        assertHeaderChrome(panel, expectsSearch: true)
        assertHistoryToolbar(panel, expectsVisible: true)
        assertHistoryRowGeometry(panel)

        panel.openSnippetsManagerMode()
        await settlePanelLayout(panel)
        #expect(panel.presentationItemScope == .complete)
        assertTopLevelLayout(panel, mode: "Snippets", expectsSearch: true)
        assertHeaderChrome(panel, expectsSearch: true)
        assertHistoryToolbar(panel, expectsVisible: false)
        assertHistoryRowGeometry(panel)
        if let root = panel.contentView {
            let descendants = allSubviews(of: root)
            let titleField = descendants.first { $0.identifier?.rawValue == "BoardManSnippetEditorTitleField" } as? NSTextField
            let saveButton = descendants.first { $0.identifier?.rawValue == "BoardManSnippetSaveButton" } as? NSButton
            let cancelButton = descendants.first { $0.identifier?.rawValue == "BoardManSnippetCancelButton" } as? NSButton
            let hoverGroupPopup = descendants.compactMap { $0 as? BoardManHoverPopUpButton }.first { !$0.isHidden }
            #expect(titleField != nil, "Snippet title editor was not created.")
            #expect(saveButton?.target != nil && saveButton?.action != nil,
                    "Snippet Save button is missing its action wiring.")
            #expect(cancelButton?.target != nil && cancelButton?.action != nil,
                    "Snippet Cancel button is missing its action wiring.")
            #expect(hoverGroupPopup != nil, "Snippet group selector is not hover-aware.")
            #expect((titleField?.frame.width ?? 0) >= 250,
                    "Snippet title editor is still cramped.")
        }

        panel.selectSettingsTab()
        await settlePanelLayout(panel)
        guard let root = panel.contentView else {
            Issue.record("Settings content view was not created.")
            return
        }
        let expectedTitles = Set(["General", "Appearance", "History", "Snippets", "Privacy", "Updates", "License"])
        let categories = root.subviews
            .flatMap { $0.subviews }
            .compactMap { $0 as? NSButton }
            .filter { expectedTitles.contains($0.title) }
            .sorted { $0.tag < $1.tag }
        #expect(panel.presentationItemScope == .historyOnly)
        #expect(categories.count == expectedTitles.count, "Settings sidebar did not create all categories.")
        for category in categories {
            #expect(category is BoardManSettingsCategoryButton,
                    "Settings category is missing hover-aware button behavior.")
            #expect((category.image?.size.width ?? 0) >= 20,
                    "Settings sidebar icon is missing its leading content inset.")
        }
        if let hoverTarget = categories.first(where: { $0.tag != 0 }) as? BoardManSettingsCategoryButton {
            #expect((hoverTarget.layer?.borderWidth ?? 0) == 0)
            hoverTarget.setHoveringForTesting(true)
            #expect(hoverTarget.isHovering)
            #expect((hoverTarget.layer?.borderWidth ?? 0) == 1)
            hoverTarget.setHoveringForTesting(false)
            #expect((hoverTarget.layer?.borderWidth ?? 0) == 0)
        }

        if let appearanceCategory = categories.first(where: { $0.title == "Appearance" }) {
            _ = appearanceCategory.sendAction(appearanceCategory.action, to: appearanceCategory.target)
            await settlePanelLayout(panel)
            let popupTitles = allSubviews(of: root)
                .compactMap { $0 as? NSPopUpButton }
                .filter { !$0.isHidden }
                .map { Set($0.itemTitles) }
            #expect(popupTitles.contains(Set(["System", "Light", "Dark"])),
                    "Appearance mode choices are missing.")
            #expect(popupTitles.contains(Set(["Default", "Simple", "Monochrome"])),
                    "UI style choices are missing.")
            let builtInFonts = Set(["System", "Rounded", "Serif", "Monospaced"])
            #expect(popupTitles.contains { builtInFonts.isSubset(of: $0) },
                    "Built-in font choices are missing from the installed-font picker.")
            if let installedFamily = NSFontManager.shared.availableFontFamilies.first {
                #expect(popupTitles.contains { $0.contains(installedFamily) },
                        "Installed Finder font families are missing from the font picker.")
            }
            #expect(popupTitles.contains { Set(["Hidden", "Below", "Left", "Right"]).isSubset(of: $0) },
                    "Timestamp position choices are missing.")
            #expect(popupTitles.contains { $0.contains("Scarlet") && $0.contains("Emerald") && $0.contains("Violet") },
                    "Expanded theme colors are missing.")
            #expect(popupTitles.contains { $0.contains("Teal") && $0.contains("Green") && $0.contains("Purple") && $0.contains("Indigo") },
                    "Expanded Used colors are missing.")

            let visiblePopups = allSubviews(of: root)
                .compactMap { $0 as? NSPopUpButton }
                .filter { !$0.isHidden }
            let themePopup = visiblePopups.first { Set(["Graphite", "Ocean", "Rose"]).isSubset(of: Set($0.itemTitles)) }
            let modePopup = visiblePopups.first { Set(["System", "Light", "Dark"]).isSubset(of: Set($0.itemTitles)) }
            let uiPopup = visiblePopups.first { Set(["Default", "Simple", "Monochrome"]).isSubset(of: Set($0.itemTitles)) }
            let fontPopup = visiblePopups.first { Set(["System", "Rounded", "Serif", "Monospaced"]).isSubset(of: Set($0.itemTitles)) }
            let timestampPopup = visiblePopups.first { Set(["Relative", "24-hour", "12-hour"]).isSubset(of: Set($0.itemTitles)) }
            let positionPopup = visiblePopups.first { Set(["Hidden", "Below", "Left", "Right"]).isSubset(of: Set($0.itemTitles)) }
            let alignedPopups = [themePopup, modePopup, uiPopup, fontPopup, timestampPopup, positionPopup].compactMap { $0 }
            #expect(alignedPopups.count == 6, "Appearance form popups could not be identified.")
            for popup in alignedPopups {
                #expect(abs(popup.frame.height - 30) <= 0.5,
                        "Appearance popup height is not aligned to the 30pt form grid.")
            }
            if let themePopup, let uiPopup {
                #expect(abs(themePopup.frame.minX - uiPopup.frame.minX) <= 0.5)
                #expect(abs(themePopup.frame.width - uiPopup.frame.width) <= 0.5)
            }
            if let modePopup, let fontPopup {
                #expect(abs(modePopup.frame.minX - fontPopup.frame.minX) <= 0.5)
                #expect(abs(modePopup.frame.width - fontPopup.frame.width) <= 0.5)
            }
            if let timestampPopup, let positionPopup {
                #expect(abs(timestampPopup.frame.width - positionPopup.frame.width) <= 0.5)
                #expect(abs(timestampPopup.frame.minY - positionPopup.frame.minY) <= 0.5)
            }

            let textScale = allSubviews(of: root).first { $0.identifier?.rawValue == "BoardManTextPreviewScaleSlider" }
            let imageScale = allSubviews(of: root).first { $0.identifier?.rawValue == "BoardManImagePreviewScaleSlider" }
            #expect(textScale is NSSlider)
            #expect(imageScale is NSSlider)
            #expect(abs((textScale?.frame.width ?? 0) - (imageScale?.frame.width ?? 0)) <= 0.5)
        }

        for category in categories {
            _ = category.sendAction(category.action, to: category.target)
            await settlePanelLayout(panel)
            assertTopLevelLayout(panel, mode: "Settings category \(category.tag)", expectsSearch: false)

            let descendants = allSubviews(of: root)
            if category.title == "Appearance" {
                let relativePopupIDs = [
                    "BoardManRelativeNumberStylePopup",
                    "BoardManRelativeUnitStylePopup",
                    "BoardManRelativeSuffixStylePopup",
                    "BoardManRelativeNowStylePopup"
                ]
                for identifier in relativePopupIDs {
                    let popup = descendants.first { $0.identifier?.rawValue == identifier } as? NSPopUpButton
                    #expect(popup?.isHidden == false, "Missing visible relative timestamp popup: \(identifier)")
                    #expect(abs((popup?.frame.height ?? 0) - 30) <= 0.5)
                }
            } else if category.title == "History" {
                let shortcutToggle = descendants.first {
                    $0.identifier?.rawValue == "BoardManTimestampShortcutEnabledButton"
                } as? NSButton
                let shortcutDelay = descendants.first {
                    $0.identifier?.rawValue == "BoardManTimestampShortcutDelayField"
                } as? NSTextField
                let presetPopup = descendants.first {
                    $0.identifier?.rawValue == "BoardManTimedPinPresetPopup"
                } as? NSPopUpButton
                let addPreset = descendants.first {
                    $0.identifier?.rawValue == "BoardManTimedPinPresetAddButton"
                } as? NSButton
                let removePreset = descendants.first {
                    $0.identifier?.rawValue == "BoardManTimedPinPresetRemoveButton"
                } as? NSButton
                #expect(shortcutToggle?.isHidden == false)
                #expect(shortcutToggle?.target != nil && shortcutToggle?.action != nil)
                #expect(shortcutDelay?.isHidden == false)
                #expect(presetPopup?.isHidden == false)
                #expect((presetPopup?.numberOfItems ?? 0) >= 1)
                #expect(addPreset?.target != nil && addPreset?.action != nil)
                #expect(removePreset?.target != nil && removePreset?.action != nil)
            } else if category.title == "Snippets" {
                let manage = descendants.first {
                    $0.identifier?.rawValue == "BoardManManageSnippetsButton"
                } as? NSButton
                let shortcutScroll = descendants.first {
                    $0.identifier?.rawValue == "BoardManSnippetShortcutScrollView"
                } as? NSScrollView
                #expect(manage?.isHidden == false)
                #expect(shortcutScroll?.isHidden == false)
                if let manage, let shortcutScroll {
                    let gap = shortcutScroll.frame.minY - manage.frame.maxY
                    #expect(gap >= 10 && gap <= 18,
                            "Manage Snippets should sit directly below the shortcut list with deliberate spacing.")
                    #expect(manage.frame.minY >= 20,
                            "Manage Snippets is still pinned against the bottom edge.")
                }
            }
        }
    }

    @Test
    func panelHidesWhenApplicationDeactivates() async {
        let panel = BoardManPanel()
        #expect(panel.hidesOnDeactivate)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        await settlePanelLayout(panel)
        #expect(panel.isVisible)

        NotificationCenter.default.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
        await settlePanelLayout(panel)
        #expect(!panel.isVisible)
    }

    @Test
    func quickModeHidesFullHeaderAndUsesThreeItemLimit() async {
        let panel = BoardManPanel()
        panel.setQuickMode(true)
        let size = BoardManPanel.quickPanelSize()
        panel.setFrame(NSRect(origin: .zero, size: size), display: false)
        await settlePanelLayout(panel)

        guard let root = panel.contentView else {
            Issue.record("Quick Mode content view was not created.")
            return
        }
        let descendants = allSubviews(of: root)
        let tabs = descendants.compactMap { $0 as? BoardManHeaderSegmentedControl }.first
        let search = descendants.compactMap { $0 as? NSSearchField }.first
        let conditionButton = descendants
            .compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "BoardManHistoryConditionButton" }
        let historyTable = descendants.compactMap { $0 as? NSTableView }.first

        #expect(BoardManPanel.quickItemLimit == 3)
        #expect(panel.presentationItemScope == .historyOnly)
        #expect(panel.minSize.height == 220)
        #expect(tabs?.isHidden == true)
        #expect(search?.isHidden == true)
        #expect(conditionButton?.isHidden == false)
        #expect((historyTable?.enclosingScrollView?.frame.height ?? 999) < 190)
    }

    private func settlePanelLayout(_ panel: BoardManPanel) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func assertHeaderChrome(_ panel: BoardManPanel, expectsSearch: Bool) {
        guard let root = panel.contentView else {
            Issue.record("Missing content view while checking header chrome.")
            return
        }
        let descendants = allSubviews(of: root)
        #expect(!descendants.contains {
            $0.identifier?.rawValue == "BoardManSegmentedOutline"
                || $0.identifier?.rawValue == "BoardManSearchOutline"
        }, "Legacy duplicate header outline views are still present.")

        guard let tabs = descendants.compactMap({ $0 as? BoardManHeaderSegmentedControl }).first else {
            Issue.record("Hover-aware header tabs were not created.")
            return
        }
        tabs.updateHoveredSegment(at: NSPoint(x: tabs.bounds.midX, y: tabs.bounds.midY))
        #expect(tabs.hoveredSegment == 1, "Header hover tracking did not resolve the middle segment.")

        let search = descendants.compactMap { $0 as? NSSearchField }.first
        #expect((search != nil) == expectsSearch || search?.isHidden == !expectsSearch)
        if expectsSearch, let search {
            #expect(search.cell is BoardManCenteredSearchFieldCell,
                    "Search field is not using the centered interactive AppKit search cell.")
            #expect((search.layer?.borderWidth ?? 0) == 0,
                    "Search field has a second custom layer border.")
            #expect(abs(search.frame.midY - tabs.frame.midY) <= 0.5,
                    "Search control is not vertically centered with the header tabs.")
            #expect(search.frame.height >= 28 && search.frame.height <= 32,
                    "Search control is stretched beyond its native interactive height.")
            #expect(search.isEditable && search.isSelectable && search.isEnabled,
                    "Search control cannot receive text input.")
            #expect(search.target != nil && search.action != nil,
                    "Search control is missing its input action wiring.")
            if let cell = search.cell as? BoardManCenteredSearchFieldCell {
                let textRect = cell.searchTextRect(forBounds: search.bounds)
                let iconRect = cell.searchButtonRect(forBounds: search.bounds)
                #expect(cell.opticalYOffset == 2,
                        "Search optical correction must stay at the requested 2pt downward offset.")
                #expect(abs((textRect.midY - search.bounds.midY) - cell.opticalYOffset) <= 0.5,
                        "Search text does not match its optical vertical offset.")
                #expect(cell.searchButtonOpticalYOffset == 1,
                        "Search icon requires a separate 1pt upward optical correction.")
                #expect(abs((iconRect.midY - search.bounds.midY) - (cell.opticalYOffset + cell.searchButtonOpticalYOffset)) <= 0.5,
                        "Search icon does not include its optical vertical correction.")
            }
        }
    }

    private func assertHistoryToolbar(_ panel: BoardManPanel, expectsVisible: Bool) {
        guard let root = panel.contentView else {
            Issue.record("Missing content view while checking the history toolbar.")
            return
        }
        let descendants = allSubviews(of: root)
        let usageFilter = descendants
            .compactMap { $0 as? NSSegmentedControl }
            .first { !($0 is BoardManHeaderSegmentedControl) && $0.segmentCount == 3 }
        let sortButton = descendants
            .compactMap { $0 as? NSButton }
            .first { ($0.toolTip ?? "").contains("Copy Order") || ($0.toolTip ?? "").contains("Recent Use") }
        let conditionButton = descendants
            .compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "BoardManHistoryConditionButton" }

        #expect(usageFilter != nil, "History usage filter was not created.")
        #expect(sortButton != nil, "History sort toggle was not created.")
        #expect(conditionButton != nil, "History condition button was not created.")
        #expect(usageFilter?.isHidden == !expectsVisible)
        #expect(sortButton?.isHidden == !expectsVisible)
        #expect(conditionButton?.isHidden == !expectsVisible)
        if expectsVisible, let usageFilter {
            #expect(usageFilter.selectedSegment >= 0 && usageFilter.selectedSegment < 3)
            for segment in 0..<usageFilter.segmentCount {
                #expect(!(usageFilter.toolTip(forSegment: segment) ?? "").isEmpty,
                        "History usage filter segment is missing its hover explanation.")
            }
        }
    }

    private func assertHistoryRowGeometry(_ panel: BoardManPanel) {
        guard let root = panel.contentView,
              let table = allSubviews(of: root).compactMap({ $0 as? NSTableView }).first else {
            Issue.record("History table was not created.")
            return
        }
        #expect(table.rowHeight == panel.tableView(table, heightOfRow: 0),
                "Configured and delegated history row heights diverge.")
        #expect(table.rowHeight == 62)

        let rowBounds = NSRect(x: 0, y: 0, width: max(240, table.bounds.width), height: table.rowHeight)
        let badgeFrame = BoardManHistoryCellView.usageBadgeFrame(in: rowBounds, intrinsicWidth: 16)
        #expect(badgeFrame.maxX <= rowBounds.maxX - 13,
                "Usage badge does not reserve enough trailing space inside the rounded row.")
        #expect(abs(badgeFrame.midY - rowBounds.midY) <= 0.5,
                "Usage badge is not vertically centered in the row.")
        #expect(badgeFrame.width >= 38,
                "Usage badge is too narrow and may clip its text.")

        let badgeCell = BoardManCenteredTextFieldCell(textCell: "×567")
        badgeCell.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        let badgeBounds = NSRect(x: 0, y: 0, width: 48, height: 20)
        let textRect = badgeCell.drawingRect(forBounds: badgeBounds)
        #expect(abs(textRect.midY - badgeBounds.midY) <= 0.5,
                "Usage count text is not vertically centered inside its badge.")
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        return view.subviews + view.subviews.flatMap(allSubviews(of:))
    }

    private func assertTopLevelLayout(_ panel: BoardManPanel,
                                      mode: String,
                                      expectsSearch: Bool) {
        guard let root = panel.contentView else {
            Issue.record("\(mode): missing content view.")
            return
        }

        root.layoutSubtreeIfNeeded()
        let visible = root.subviews.filter { !$0.isHidden && $0.alphaValue > 0.01 }
        #expect(!visible.isEmpty, "\(mode): no visible top-level views.")

        let tolerance: CGFloat = 1
        for view in visible {
            let frame = view.frame
            #expect(frame.width > 0 && frame.height > 0, "\(mode): zero-sized \(type(of: view)).")
            #expect(frame.minX >= -tolerance, "\(mode): \(type(of: view)) extends past the left edge.")
            #expect(frame.minY >= -tolerance, "\(mode): \(type(of: view)) extends below the panel.")
            #expect(frame.maxX <= root.bounds.maxX + tolerance, "\(mode): \(type(of: view)) extends past the right edge.")
            #expect(frame.maxY <= root.bounds.maxY + tolerance, "\(mode): \(type(of: view)) extends above the panel.")
        }

        let visibleSearchFields = visible.compactMap { $0 as? NSSearchField }
        #expect((visibleSearchFields.count == 1) == expectsSearch,
                "\(mode): unexpected search field visibility.")
    }
}

// swiftlint:enable file_length
