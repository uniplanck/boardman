// swiftlint:disable file_length

import Cocoa
import CryptoKit
import Foundation
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
        #expect(BoardManCommercialPolicy.freeHistoryItems == 100)
        #expect(BoardManCommercialPolicy.freePinnedItems == 3)
        #expect(BoardManCommercialPolicy.freeSnippetItems == 5)
        #expect(BoardManCommercialPolicy.freeSnippetFolders == 1)
        #expect(BoardManCommercialPolicy.lifetimeDeviceLimit == 1)
        #expect(!BoardManCommercialPolicy.supportsSubscription)
        #expect(BoardManCommercialPolicy.lifetimeIncludesFutureAppVersions)
        #expect(entitlement.limits.maxHistoryItems == 100)
        #expect(entitlement.limits.maxPinnedItems == 3)
        #expect(entitlement.limits.maxSnippetItems == 5)
        #expect(entitlement.limits.maxSnippetFolders == 1)
        #expect(!EntitlementGate.canUse(feature: .unlimitedHistory, service: service))
        #expect(!EntitlementGate.canUse(feature: .advancedAppearance, service: service))
        #expect(!EntitlementGate.canUse(feature: .advancedSearch, service: service))
        #expect(!EntitlementGate.canUse(feature: .workflowActions, service: service))
        #expect(EntitlementGate.canUse(feature: .exportImport, service: service))
        #expect(!EntitlementGate.canUse(feature: .futureSync, service: service))
        #expect(!EntitlementGate.canUse(feature: .aiAssist, service: service))
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
        #expect(entitlement.isLifetimeEntitled)
        #expect(EntitlementGate.canUse(feature: .exportImport, service: service))

        for feature in EntitlementFeature.lifetimeLocalFeatures {
            #expect(EntitlementGate.canUse(feature: feature, service: service))
        }
        #expect(!EntitlementGate.canUse(feature: .futureSync, service: service))
        #expect(!EntitlementGate.canUse(feature: .cloudBackup, service: service))
        #expect(!EntitlementGate.canUse(feature: .aiAssist, service: service))

        #expect(EntitlementGate.limit(for: .historyItems, service: service) == nil)
        #expect(EntitlementGate.limit(for: .pinnedItems, service: service) == nil)
        #expect(EntitlementGate.limit(for: .snippetItems, service: service) == nil)
        #expect(EntitlementGate.limit(for: .snippetFolders, service: service) == nil)
    }

    @Test
    func lifetimeUnlocksFutureLocalFeaturesWithoutReissuingOldTokenClaims() {
        let entitlement = EntitlementSnapshot(
            plan: .ownerLifetime,
            licenseState: .ownerLifetime,
            features: [],
            limits: .lifetimeDefault
        )
        let service = EntitlementService(snapshot: entitlement)

        #expect(EntitlementGate.canUse(feature: .advancedSearch, service: service))
        #expect(EntitlementGate.canUse(feature: .workflowActions, service: service))
        #expect(EntitlementGate.canUse(feature: .workspaceSessions, service: service))
        #expect(!EntitlementGate.canUse(feature: .futureSync, service: service))
    }

    @Test
    func lifetimeServiceFeatureRequiresExplicitSignedClaim() {
        let entitlement = EntitlementSnapshot(
            plan: .ownerLifetime,
            licenseState: .ownerLifetime,
            features: [.futureSync],
            limits: .lifetimeDefault
        )
        let service = EntitlementService(snapshot: entitlement)

        #expect(EntitlementGate.canUse(feature: .futureSync, service: service))
        #expect(!EntitlementGate.canUse(feature: .cloudBackup, service: service))
    }

    @Test
    func freePlanEnforcesHistoryLimit() {
        let service = EntitlementService(snapshot: .freeDefault)

        #expect(EntitlementGate.canAddHistoryItem(currentCount: 99, service: service))
        #expect(!EntitlementGate.canAddHistoryItem(currentCount: 100, service: service))
        #expect(!EntitlementGate.canAddHistoryItem(currentCount: 100_000, service: service))
        #expect(EntitlementGate.historyRetentionLimit(service: service) == 100)
    }

    @Test
    func freeHistoryRetentionCapsUserConfigurationAtCommercialLimit() {
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
    func freePlanEnforcesPinnedItemLimit() {
        let service = EntitlementService(snapshot: .freeDefault)

        #expect(EntitlementGate.canPinItem(currentPinnedCount: 2, service: service))
        #expect(!EntitlementGate.canPinItem(currentPinnedCount: 3, service: service))
        #expect(!EntitlementGate.canPinItem(currentPinnedCount: 10_000, service: service))
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
        #expect(reloaded.searchMatches(for: "deploy")["history-1"] == 1)
        #expect(reloaded.searchMatches(for: "Deploy command")["history-1"] == 0)
        #expect(reloaded.searchMatches(for: "command")["history-1"] == 2)

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
    func missingTextPayloadCanRecoverFromRealmTitleWithoutTreatingImagesAsText() {
        let textClip = BoardManClip()
        textClip.title = "git status --short"
        textClip.primaryType = NSPasteboard.PasteboardType.deprecatedString.rawValue
        #expect(textClip.boardManRecoverableText == "git status --short")

        let modernTextClip = BoardManClip()
        modernTextClip.title = "npm test"
        modernTextClip.primaryType = NSPasteboard.PasteboardType.string.rawValue
        #expect(modernTextClip.boardManRecoverableText == "npm test")

        let imageClip = BoardManClip()
        imageClip.title = "PNG image"
        imageClip.primaryType = NSPasteboard.PasteboardType.png.rawValue
        #expect(imageClip.boardManRecoverableText == nil)
    }

    @Test
    func overflowArchiveStoresTextWithDateAndSkipsImages() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextHistoryArchiveStoreTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("history.jsonl")
        defer { try? FileManager.default.removeItem(at: root) }

        let textClip = BoardManClip()
        textClip.dataHash = "text-entry"
        textClip.title = "git status --short"
        textClip.updateTime = 1_700_000_000
        textClip.primaryType = NSPasteboard.PasteboardType.string.rawValue

        let imageClip = BoardManClip()
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
    func freePlanEnforcesSnippetLimit() {
        let service = EntitlementService(snapshot: .freeDefault)

        #expect(EntitlementGate.canCreateSnippet(currentSnippetCount: 4, service: service))
        #expect(!EntitlementGate.canCreateSnippet(currentSnippetCount: 5, service: service))
        #expect(!EntitlementGate.canCreateSnippet(currentSnippetCount: 10_000, service: service))
    }

    @Test
    func freePlanEnforcesSnippetFolderLimit() {
        let service = EntitlementService(snapshot: .freeDefault)

        #expect(EntitlementGate.canCreateSnippetFolder(currentFolderCount: 0, service: service))
        #expect(!EntitlementGate.canCreateSnippetFolder(currentFolderCount: 1, service: service))
        #expect(!EntitlementGate.canCreateSnippetFolder(currentFolderCount: 10_000, service: service))
    }

    @Test
    func freeLimitChecksDoNotMutateExistingCounts() {
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
    func maskedItemStoreTogglesPersistsAndRemovesIdentifiers() throws {
        let suiteName = "BoardManMaskedItemStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BoardManMaskedItemStore(defaults: defaults)

        #expect(!store.isMasked("history-item"))
        #expect(store.toggle("history-item"))
        #expect(store.isMasked("history-item"))
        #expect(BoardManMaskedItemStore(defaults: defaults).isMasked("history-item"))
        #expect(!store.toggle("history-item"))
        #expect(!store.isMasked("history-item"))

        store.setMasked(true, for: "first")
        store.setMasked(true, for: "second")
        store.remove(["first"])
        #expect(!store.isMasked("first"))
        #expect(store.isMasked("second"))
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
            #expect(!EntitlementGate.canUse(feature: .futureSync, service: service))
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
        #expect(!EntitlementGate.canUse(feature: .futureSync, service: service))
    }

}

@Suite(.serialized)
final class CommercialLicenseBoundaryTests {

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

        let wrongBundle = SignedLicenseTokenVerificationContext(
            deviceID: deviceID,
            bundleID: "com.example.NotBoardMan",
            verificationDate: Date()
        )
        #expect(verifier.verify(token, context: wrongBundle) == .invalid(.bundleMismatch))

        let unsupportedVersion = try makeOwnerToken(
            privateKey: privateKey,
            deviceID: deviceID,
            tokenVersion: 2
        )
        #expect(verifier.verify(unsupportedVersion, context: context) == .invalid(.claimMismatch))

        let restrictedLifetime = try makeOwnerToken(
            privateKey: privateKey,
            deviceID: deviceID,
            limits: [
                "max_history_items": 1,
                "max_pinned_items": 1,
                "max_snippet_items": 1,
                "max_snippet_folders": 1
            ]
        )
        if case .verified(let payload) = verifier.verify(restrictedLifetime, context: context) {
            let snapshot = payload.entitlementSnapshot(lastVerifiedAt: Date())
            #expect(snapshot.limits == .lifetimeDefault)
            #expect(snapshot.canUse(.advancedSearch))
        } else {
            Issue.record("Expected the signed Lifetime token to normalize local limits.")
        }

        let tampered = token + "x"
        #expect(verifier.verify(tampered, context: context) == .invalid(.signatureInvalid))
    }

    @Test
    func signedProTokenSupportsSubscriptionAndTrialClaims() throws {
        let privateKey = P256.Signing.PrivateKey()
        let deviceID = UUID().uuidString
        let verifier = P256SignedLicenseTokenVerifier(
            publicKeyBase64: privateKey.publicKey.x963Representation.base64EncodedString()
        )
        let now = Date()
        let context = SignedLicenseTokenVerificationContext(
            deviceID: deviceID,
            bundleID: "com.uniplanck.BoardMan",
            verificationDate: now
        )

        for state in [LicenseState.proActive, .trial] {
            let token = try makeProToken(
                privateKey: privateKey,
                deviceID: deviceID,
                state: state,
                expiration: now.addingTimeInterval(3600)
            )
            let result = verifier.verify(token, context: context)
            if case .verified(let payload) = result {
                #expect(payload.plan == .pro)
                #expect(payload.licenseKind == .pro)
                #expect(payload.state == state)
                #expect(!payload.isLifetime)
                #expect(payload.features.contains(.futureSync))
            } else {
                Issue.record("Expected signed \(state.rawValue) token to verify.")
            }
        }

        let expired = try makeProToken(
            privateKey: privateKey,
            deviceID: deviceID,
            state: .proActive,
            expiration: now.addingTimeInterval(-60)
        )
        #expect(verifier.verify(expired, context: context) == .invalid(.tokenExpired))
    }

    @Test
    func commercialServiceConfigurationKeepsBackendOutsideClient() {
        let config = BoardManCommercialServiceConfiguration.current(
            environment: [BoardManCommercialServiceConfiguration.environmentKey: "https://billing.example.test/base"],
            infoDictionary: [:]
        )
        #expect(config.activationURL?.absoluteString == "https://billing.example.test/base/v1/licenses/activate")

        let insecureRemote = BoardManCommercialServiceConfiguration(
            baseURL: URL(string: "http://licenses.example.test")
        )
        #expect(insecureRemote.baseURL == nil)

        let localDevelopment = BoardManCommercialServiceConfiguration(
            baseURL: URL(string: "http://127.0.0.1:8787")
        )
        #expect(localDevelopment.activationURL?.absoluteString == "http://127.0.0.1:8787/v1/licenses/activate")

        let unconfigured = BoardManCommercialServiceConfiguration.current(
            environment: [:],
            infoDictionary: [:]
        )
        #expect(unconfigured.baseURL == nil)
        #expect(unconfigured.activationURL == nil)
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
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
        let directoryPermissions = directoryAttributes[.posixPermissions] as? NSNumber
        #expect(directoryPermissions?.intValue == 0o700)
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

    @Test
    func activationCoordinatorStoresAndAppliesVerifiedLifetimeToken() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManActivationCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = LocalDeviceIdentityService(fileURL: root.appendingPathComponent("device-id"))
        let deviceID = identity.deviceID()
        let privateKey = P256.Signing.PrivateKey()
        let rawToken = try makeOwnerToken(privateKey: privateKey, deviceID: deviceID)
        let client = RecordingLicenseActivationClient(
            response: LicenseActivationResponse(
                status: .activated,
                message: "Lifetime license activated.",
                signedToken: rawToken
            )
        )
        let store = MemoryLicenseTokenStore()
        let entitlementService = EntitlementService(snapshot: .freeDefault)
        let verificationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let coordinator = LicenseActivationCoordinator(
            client: client,
            verifier: P256SignedLicenseTokenVerifier(
                publicKeyBase64: privateKey.publicKey.x963Representation.base64EncodedString()
            ),
            tokenStore: store,
            entitlementService: entitlementService,
            deviceIdentity: identity,
            bundleID: "com.uniplanck.BoardMan",
            clientVersion: "9.9.9",
            now: { verificationDate }
        )

        let result = await coordinator.activate(licenseKey: "  LIFETIME-CODE  ")

        #expect(result.status == .activated)
        #expect(result.signedToken == nil)
        #expect(store.storedToken?.rawValue == rawToken)
        #expect(entitlementService.currentSnapshot.plan == .ownerLifetime)
        #expect(entitlementService.currentSnapshot.licenseState == .ownerLifetime)
        #expect(entitlementService.currentSnapshot.lastVerifiedAt == verificationDate)
        #expect(entitlementService.currentSnapshot.licenseMetadata?.licenseKeyMasked == "****TEST")
        #expect(entitlementService.currentSnapshot.licenseMetadata?.licenseKeyMasked != "OWNER-TEST")
        #expect(entitlementService.currentSnapshot.licenseMetadata?.deviceIdMasked == "****\(deviceID.suffix(4))")
        #expect(client.receivedRequest?.licenseKey == "LIFETIME-CODE")
        #expect(client.receivedRequest?.localDeviceID == deviceID)
        #expect(client.receivedRequest?.bundleID == "com.uniplanck.BoardMan")
        #expect(client.receivedRequest?.clientVersion == "9.9.9")
    }

    @Test
    func activationCoordinatorRejectsLegacyProTokenForNewActivation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManLegacyActivationRejectionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = LocalDeviceIdentityService(fileURL: root.appendingPathComponent("device-id"))
        let deviceID = identity.deviceID()
        let privateKey = P256.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rawToken = try makeProToken(
            privateKey: privateKey,
            deviceID: deviceID,
            state: .proActive,
            expiration: now.addingTimeInterval(3_600)
        )
        let client = RecordingLicenseActivationClient(
            response: LicenseActivationResponse(
                status: .activated,
                message: "Legacy token returned.",
                signedToken: rawToken
            )
        )
        let store = MemoryLicenseTokenStore()
        let entitlementService = EntitlementService(snapshot: .freeDefault)
        let coordinator = LicenseActivationCoordinator(
            client: client,
            verifier: P256SignedLicenseTokenVerifier(
                publicKeyBase64: privateKey.publicKey.x963Representation.base64EncodedString()
            ),
            tokenStore: store,
            entitlementService: entitlementService,
            deviceIdentity: identity,
            bundleID: "com.uniplanck.BoardMan",
            clientVersion: "9.9.9",
            now: { now }
        )

        let result = await coordinator.activate(licenseKey: "LEGACY-PRO-CODE")

        #expect(result.status == .verificationFailed)
        #expect(store.storedToken == nil)
        #expect(entitlementService.currentSnapshot.licenseState == .free)
    }

    @Test
    func activationCoordinatorRejectsActivatedResponseWithoutToken() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManMissingActivationTokenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryLicenseTokenStore()
        let coordinator = LicenseActivationCoordinator(
            client: RecordingLicenseActivationClient(
                response: LicenseActivationResponse(status: .activated, message: "Activated without token.")
            ),
            verifier: StubSignedLicenseTokenVerifier(mode: .parseOnly),
            tokenStore: store,
            entitlementService: EntitlementService(snapshot: .freeDefault),
            deviceIdentity: LocalDeviceIdentityService(fileURL: root.appendingPathComponent("device-id")),
            bundleID: "com.uniplanck.BoardMan",
            clientVersion: "9.9.9"
        )

        let result = await coordinator.activate(licenseKey: "LIFETIME-CODE")

        #expect(result.status == .verificationFailed)
        #expect(store.storedToken == nil)
    }

    @Test
    func bootstrapRestoresVerifiedLifetimeTokenWithoutNetwork() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManOfflineLicenseBootstrapTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "BoardManOfflineLicenseBootstrapTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let identity = LocalDeviceIdentityService(fileURL: root.appendingPathComponent("device-id"))
        let deviceID = identity.deviceID()
        let privateKey = P256.Signing.PrivateKey()
        let rawToken = try makeOwnerToken(privateKey: privateKey, deviceID: deviceID)
        let store = MemoryLicenseTokenStore(loadedToken: rawToken)
        let entitlementService = EntitlementService(snapshot: .freeDefault)
        let verificationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let bootstrap = LicenseBootstrapService(
            tokenStore: store,
            verifier: P256SignedLicenseTokenVerifier(
                publicKeyBase64: privateKey.publicKey.x963Representation.base64EncodedString()
            ),
            entitlementService: entitlementService,
            deviceIdentity: identity,
            bundleID: "com.uniplanck.BoardMan",
            now: { verificationDate },
            diagnosticDefaults: defaults
        )

        #expect(bootstrap.restoreEntitlement())
        #expect(entitlementService.currentSnapshot.plan == .ownerLifetime)
        #expect(entitlementService.currentSnapshot.licenseState == .ownerLifetime)
        #expect(entitlementService.currentSnapshot.lastVerifiedAt == verificationDate)
        #expect(entitlementService.currentSnapshot.licenseMetadata?.licenseKeyMasked == "****TEST")
        #expect(defaults.string(forKey: "BoardManDiagnosticEntitlementStatus") == "verified")
    }

    private final class RecordingLicenseActivationClient: LicenseActivationClient {
        let response: LicenseActivationResponse
        var receivedRequest: LicenseActivationRequest?

        init(response: LicenseActivationResponse) {
            self.response = response
        }

        func activate(_ request: LicenseActivationRequest) async -> LicenseActivationResponse {
            receivedRequest = request
            return response
        }
    }

    private final class MemoryLicenseTokenStore: LicenseTokenStoring {
        var loadedToken: String?
        var storedToken: SignedLicenseToken?

        init(loadedToken: String? = nil) {
            self.loadedToken = loadedToken
        }

        func loadSignedLicenseToken() -> String? {
            return loadedToken ?? storedToken?.rawValue
        }

        func storeVerifiedSignedLicenseToken(_ token: SignedLicenseToken) throws {
            storedToken = token
        }
    }

    private func makeOwnerToken(privateKey: P256.Signing.PrivateKey,
                                deviceID: String,
                                tokenVersion: Int = 1,
                                limits: [String: Int]? = nil) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: [
            "alg": "ES256",
            "kid": "test-owner-v1",
            "typ": "JWT"
        ], options: [.sortedKeys])
        var payloadObject: [String: Any] = [
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
            "token_version": tokenVersion
        ]
        payloadObject["limits"] = limits
        let payload = try JSONSerialization.data(withJSONObject: payloadObject, options: [.sortedKeys])
        let signingInput = "\(base64URL(header)).\(base64URL(payload))"
        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64URL(signature.rawRepresentation))"
    }

    private func makeProToken(privateKey: P256.Signing.PrivateKey,
                              deviceID: String,
                              state: LicenseState,
                              expiration: Date) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: [
            "alg": "ES256",
            "kid": "test-pro-v1",
            "typ": "JWT"
        ], options: [.sortedKeys])
        let payload = try JSONSerialization.data(withJSONObject: [
            "license_id": "PRO-TEST",
            "license_kind": "pro",
            "plan": "pro",
            "state": state.rawValue,
            "features": [
                EntitlementFeature.futureSync.rawValue,
                EntitlementFeature.cloudBackup.rawValue,
                EntitlementFeature.aiAssist.rawValue
            ],
            "issued_to": "test-subscriber",
            "sub": "test-subscriber",
            "iat": Int(Date().timeIntervalSince1970),
            "exp": Int(expiration.timeIntervalSince1970),
            "is_lifetime": false,
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
final class CommercialLicenseHardeningTests {

    @Test
    func localDeviceIdentityFailsClosedWhenPersistenceIsUnavailable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManDeviceIdentityFailureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockingParent = root.appendingPathComponent("not-a-directory")
        try Data("blocker".utf8).write(to: blockingParent)
        let identity = LocalDeviceIdentityService(
            fileURL: blockingParent.appendingPathComponent("device-id")
        )

        do {
            _ = try identity.persistentDeviceID()
            Issue.record("Expected stable device identity persistence to fail.")
        } catch {
            #expect(error as? LocalDeviceIdentityError == .persistenceFailed)
        }
    }

    @Test
    func activationCoordinatorRequiresStableDeviceAndBuildIdentityBeforeNetwork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManActivationPreflightTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let blockingParent = root.appendingPathComponent("not-a-directory")
        try Data("blocker".utf8).write(to: blockingParent)
        let identityFailureClient = RecordingLicenseActivationClient()
        let identityFailure = LicenseActivationCoordinator(
            client: identityFailureClient,
            verifier: StubSignedLicenseTokenVerifier(mode: .parseOnly),
            tokenStore: MemoryLicenseTokenStore(),
            entitlementService: EntitlementService(snapshot: .freeDefault),
            deviceIdentity: LocalDeviceIdentityService(
                fileURL: blockingParent.appendingPathComponent("device-id")
            ),
            bundleID: "com.uniplanck.BoardMan",
            clientVersion: "9.9.9"
        )

        let identityResult = await identityFailure.activate(licenseKey: "LIFETIME-CODE")
        #expect(identityResult.status == .storageFailed)
        #expect(identityFailureClient.receivedRequest == nil)

        let metadataFailureClient = RecordingLicenseActivationClient()
        let metadataFailure = LicenseActivationCoordinator(
            client: metadataFailureClient,
            verifier: StubSignedLicenseTokenVerifier(mode: .parseOnly),
            tokenStore: MemoryLicenseTokenStore(),
            entitlementService: EntitlementService(snapshot: .freeDefault),
            deviceIdentity: LocalDeviceIdentityService(fileURL: root.appendingPathComponent("device-id")),
            bundleID: nil,
            clientVersion: "9.9.9"
        )

        let metadataResult = await metadataFailure.activate(licenseKey: "LIFETIME-CODE")
        #expect(metadataResult.status == .notConfigured)
        #expect(metadataFailureClient.receivedRequest == nil)
    }

    @Test
    func bootstrapFallsBackToFreeWhenStableDeviceIdentityIsUnavailable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManBootstrapIdentityFailureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockingParent = root.appendingPathComponent("not-a-directory")
        try Data("blocker".utf8).write(to: blockingParent)
        let suiteName = "BoardManBootstrapIdentityFailureTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let entitlementService = EntitlementService(snapshot: .proActive())
        let bootstrap = LicenseBootstrapService(
            tokenStore: MemoryLicenseTokenStore(loadedToken: "header.payload.signature"),
            verifier: StubSignedLicenseTokenVerifier(mode: .parseOnly),
            entitlementService: entitlementService,
            deviceIdentity: LocalDeviceIdentityService(
                fileURL: blockingParent.appendingPathComponent("device-id")
            ),
            bundleID: "com.uniplanck.BoardMan",
            diagnosticDefaults: defaults
        )

        #expect(!bootstrap.restoreEntitlement())
        #expect(entitlementService.currentSnapshot.plan == .free)
        #expect(defaults.string(forKey: "BoardManDiagnosticEntitlementStatus") == "deviceIdentityUnavailable")
    }

    private final class RecordingLicenseActivationClient: LicenseActivationClient {
        var receivedRequest: LicenseActivationRequest?

        func activate(_ request: LicenseActivationRequest) async -> LicenseActivationResponse {
            receivedRequest = request
            return LicenseActivationResponse(status: .rejected, message: "Should not be called.")
        }
    }

    private final class MemoryLicenseTokenStore: LicenseTokenStoring {
        let loadedToken: String?

        init(loadedToken: String? = nil) {
            self.loadedToken = loadedToken
        }

        func loadSignedLicenseToken() -> String? {
            return loadedToken
        }

        func storeVerifiedSignedLicenseToken(_ token: SignedLicenseToken) throws {}
    }
}

@Suite(.serialized)
final class BoardManLicenseActivationClientTests {

    @Test
    func activationRequestEncodesOnlyPrivacySafeContractFields() throws {
        let request = LicenseActivationRequest(
            licenseKey: "  LIFETIME-CODE  ",
            localDeviceID: "device-id",
            bundleID: "com.uniplanck.BoardMan",
            clientVersion: "9.9.9"
        )

        let data = try JSONEncoder().encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(object.keys) == Set(["license_key", "device_id", "bundle_id", "client_version"]))
        #expect(object["license_key"] as? String == "LIFETIME-CODE")
        #expect(object["device_id"] as? String == "device-id")
        #expect(object["bundle_id"] as? String == "com.uniplanck.BoardMan")
        #expect(object["client_version"] as? String == "9.9.9")
    }

    @Test
    func urlSessionActivationClientPostsContractAndParsesResponse() async throws {
        LicenseActivationURLProtocolStub.reset()
        defer { LicenseActivationURLProtocolStub.reset() }
        LicenseActivationURLProtocolStub.configure(
            statusCode: 200,
            json: [
                "status": "activated",
                "message": "Lifetime license activated.",
                "signed_token": "header.payload.signature"
            ]
        )

        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = URLSessionLicenseActivationClient(
            configuration: BoardManCommercialServiceConfiguration(
                baseURL: URL(string: "https://licenses.example.test/base")
            ),
            session: session
        )

        let result = await client.activate(
            LicenseActivationRequest(
                licenseKey: "LIFETIME-CODE",
                localDeviceID: "device-id",
                bundleID: "com.uniplanck.BoardMan",
                clientVersion: "9.9.9"
            )
        )

        #expect(result.status == .activated)
        #expect(result.signedToken == "header.payload.signature")
        let captured = try #require(LicenseActivationURLProtocolStub.capturedRequest())
        #expect(captured.httpMethod == "POST")
        #expect(captured.url?.absoluteString == "https://licenses.example.test/base/v1/licenses/activate")
        #expect(captured.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test
    func urlSessionActivationClientPreservesSafeRejectionMessage() async {
        LicenseActivationURLProtocolStub.reset()
        defer { LicenseActivationURLProtocolStub.reset() }
        LicenseActivationURLProtocolStub.configure(
            statusCode: 409,
            json: [
                "status": "rejected",
                "message": "Deactivate the current device in MyPage first."
            ]
        )

        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = URLSessionLicenseActivationClient(
            configuration: BoardManCommercialServiceConfiguration(
                baseURL: URL(string: "https://licenses.example.test")
            ),
            session: session
        )

        let result = await client.activate(
            LicenseActivationRequest(
                licenseKey: "LIFETIME-CODE",
                localDeviceID: "device-id",
                bundleID: "com.uniplanck.BoardMan",
                clientVersion: "9.9.9"
            )
        )

        #expect(result.status == .rejected)
        #expect(result.message == "Deactivate the current device in MyPage first.")
        #expect(result.signedToken == nil)
    }

    @Test
    func urlSessionActivationClientRejectsIncompleteIdentityWithoutNetwork() async {
        LicenseActivationURLProtocolStub.reset()
        defer { LicenseActivationURLProtocolStub.reset() }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = URLSessionLicenseActivationClient(
            configuration: BoardManCommercialServiceConfiguration(
                baseURL: URL(string: "https://licenses.example.test")
            ),
            session: session
        )

        let result = await client.activate(
            LicenseActivationRequest(
                licenseKey: "LIFETIME-CODE",
                localDeviceID: "device-id",
                bundleID: nil,
                clientVersion: "9.9.9"
            )
        )

        #expect(result.status == .invalidInput)
        #expect(LicenseActivationURLProtocolStub.capturedRequest() == nil)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LicenseActivationURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private class LicenseActivationURLProtocolStub: URLProtocol {
        nonisolated(unsafe) private static var statusCode = 200
        nonisolated(unsafe) private static var responseData = Data()
        nonisolated(unsafe) private static var lastRequest: URLRequest?

        static func configure(statusCode: Int, json: [String: Any]) {
            self.statusCode = statusCode
            responseData = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
            lastRequest = nil
        }

        static func capturedRequest() -> URLRequest? {
            return lastRequest
        }

        static func reset() {
            statusCode = 200
            responseData = Data()
            lastRequest = nil
        }

        override class func canInit(with request: URLRequest) -> Bool {
            return true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }

        override func startLoading() {
            Self.lastRequest = request
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: Self.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.responseData)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
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
            let clip = BoardManClip()
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
        #expect(destination.objects(BoardManClip.self).count == 1)
        #expect(destination.objects(BoardManFolder.self).count == 1)
        #expect(destination.objects(BoardManSnippet.self).count == 2)
        #expect(destination.objects(BoardManFolder.self).first?.snippets.count == 2)
        let backups = try FileManager.default.contentsOfDirectory(at: backupURL, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        let backupPermissions = try #require(
            FileManager.default.attributesOfItem(atPath: backups[0].path)[.posixPermissions] as? NSNumber
        )
        let directoryPermissions = try #require(
            FileManager.default.attributesOfItem(atPath: backupURL.path)[.posixPermissions] as? NSNumber
        )
        #expect(backupPermissions.intValue & 0o777 == 0o600)
        #expect(directoryPermissions.intValue & 0o777 == 0o700)
        #expect(FileManager.default.fileExists(atPath: newerSourceURL.path))
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
            let snippet = BoardManSnippet()
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
        #expect(destination.objects(BoardManSnippet.self).count == 3)
        #expect(destination.object(ofType: BoardManSnippet.self, forPrimaryKey: "current-only")?.content == "Keep me")
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
        #expect(destination.objects(BoardManSnippet.self).count == 2)
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
    }

    @Test
    func backupFailureLeavesDestinationUntouchedAndPreservesSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationURL = root.appendingPathComponent("current/default.realm")
        let sourceURL = root.appendingPathComponent("legacy/default.realm")
        let blockedBackupURL = root.appendingPathComponent("backup-blocker")
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = try makeRealm(at: destinationURL)
        try destination.write {
            let current = BoardManSnippet()
            current.identifier = "current-only"
            current.title = "Current"
            current.content = "Do not mutate"
            destination.add(current)
        }
        try createLegacyRealm(at: sourceURL, snippetCount: 2)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(FileManager.default.createFile(atPath: blockedBackupURL.path, contents: Data("block".utf8)))

        let result = LegacySnippetMigrationService.migrateIfNeeded(
            into: destination,
            candidateURLs: [sourceURL],
            backupDirectoryURL: blockedBackupURL
        )

        #expect(result == .failed)
        #expect(destination.objects(BoardManSnippet.self).count == 1)
        #expect(destination.object(ofType: BoardManSnippet.self, forPrimaryKey: "current-only")?.content == "Do not mutate")
        #expect(destination.object(ofType: BoardManSnippet.self, forPrimaryKey: "legacy-snippet-0") == nil)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test
    func schemaSevenFixtureIsReadThroughMigrationWithoutRewritingLegacySource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationURL = root.appendingPathComponent("current/default.realm")
        let sourceURL = root.appendingPathComponent("legacy/default.realm")
        let backupURL = root.appendingPathComponent("backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = try makeRealm(at: destinationURL)
        try createLegacyRealm(at: sourceURL, snippetCount: 1, schemaVersion: 7)
        let originalSourceData = try Data(contentsOf: sourceURL)

        let result = LegacySnippetMigrationService.migrateIfNeeded(
            into: destination,
            candidateURLs: [sourceURL],
            backupDirectoryURL: backupURL
        )

        #expect(result == .restored(sourceDirectory: "legacy", folderCount: 1, snippetCount: 1))
        #expect(destination.objects(BoardManFolder.self).count == 1)
        #expect(destination.objects(BoardManSnippet.self).count == 1)
        #expect(try Data(contentsOf: sourceURL) == originalSourceData)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    private func makeRealm(at url: URL, schemaVersion: UInt64 = LegacySnippetMigrationService.schemaVersion) throws -> Realm {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Realm.Configuration(fileURL: url)
        configuration.schemaVersion = schemaVersion
        configuration.objectTypes = [BoardManClip.self, BoardManFolder.self, BoardManSnippet.self]
        return try Realm(configuration: configuration)
    }

    private func createLegacyRealm(
        at url: URL,
        snippetCount: Int,
        schemaVersion: UInt64 = LegacySnippetMigrationService.schemaVersion
    ) throws {
        let seedURL = url.deletingLastPathComponent()
            .appendingPathComponent("seed-\(UUID().uuidString).realm")
        let realm = try makeRealm(at: seedURL, schemaVersion: schemaVersion)
        try addLegacyData(to: realm, snippetCount: snippetCount)
        try realm.writeCopy(toFile: url)
        realm.invalidate()
    }

    private func addLegacyData(to realm: Realm, snippetCount: Int) throws {
        try realm.write {
            let folder = BoardManFolder()
            folder.identifier = "legacy-folder"
            folder.title = "Legacy"
            folder.index = 0
            for index in 0..<snippetCount {
                let snippet = BoardManSnippet()
                snippet.identifier = "legacy-snippet-\(index)"
                snippet.index = index
                snippet.title = "Snippet \(index)"
                snippet.content = "Content \(index)"
                folder.snippets.append(snippet)
            }
            realm.add(folder)

            let clip = BoardManClip()
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
            let current = BoardManClip()
            current.dataHash = "current"
            current.title = "Keep current"
            destination.add(current)
        }

        let source = try makeRealm(at: sourceURL)
        try source.write {
            let text = BoardManClip()
            text.dataHash = "legacy-text"
            text.title = "git status --short"
            text.primaryType = NSPasteboard.PasteboardType.deprecatedString.rawValue
            text.createdTime = 1_700_000_000_000
            text.updateTime = 1_700_000_000
            text.dataPath = root.appendingPathComponent("missing-text.data").path
            source.add(text)

            let image = BoardManClip()
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
        #expect(destination.objects(BoardManClip.self).count == 2)
        #expect(destination.object(ofType: BoardManClip.self, forPrimaryKey: "current")?.title == "Keep current")
        let restored = try #require(destination.object(ofType: BoardManClip.self, forPrimaryKey: "legacy-text"))
        #expect(restored.title == "git status --short")
        #expect(restored.createdTime == 1_700_000_000_000)
        #expect(FileManager.default.fileExists(atPath: restored.dataPath))
        #expect(destination.object(ofType: BoardManClip.self, forPrimaryKey: "legacy-image") == nil)
        #expect((try FileManager.default.contentsOfDirectory(at: backupURL, includingPropertiesForKeys: nil)).count == 1)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test
    func backupFailureRollsBackPreparedHistoryArchiveAndPreservesDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationURL = root.appendingPathComponent("current/default.realm")
        let sourceURL = root.appendingPathComponent("legacy/default.realm")
        let blockedBackupURL = root.appendingPathComponent("backup-blocker")
        let dataURL = root.appendingPathComponent("data", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = try makeRealm(at: destinationURL)
        try destination.write {
            let current = BoardManClip()
            current.dataHash = "current"
            current.title = "Keep current"
            destination.add(current)
        }

        let source = try makeRealm(at: sourceURL)
        try source.write {
            let text = BoardManClip()
            text.dataHash = "legacy-text"
            text.title = "rollback me"
            text.primaryType = NSPasteboard.PasteboardType.string.rawValue
            text.dataPath = root.appendingPathComponent("missing-text.data").path
            source.add(text)
        }
        source.invalidate()
        #expect(FileManager.default.createFile(atPath: blockedBackupURL.path, contents: Data("block".utf8)))

        let result = LegacyHistoryRecoveryService.migrateIfNeeded(
            into: destination,
            candidateURLs: [sourceURL],
            backupDirectoryURL: blockedBackupURL,
            dataDirectoryURL: dataURL
        )

        #expect(result == .failed)
        #expect(destination.objects(BoardManClip.self).count == 1)
        #expect(destination.object(ofType: BoardManClip.self, forPrimaryKey: "current")?.title == "Keep current")
        #expect(destination.object(ofType: BoardManClip.self, forPrimaryKey: "legacy-text") == nil)
        let preparedFiles = (try? FileManager.default.contentsOfDirectory(at: dataURL, includingPropertiesForKeys: nil)) ?? []
        #expect(preparedFiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    private func makeRealm(at url: URL) throws -> Realm {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Realm.Configuration(fileURL: url)
        configuration.schemaVersion = LegacySnippetMigrationService.schemaVersion
        configuration.objectTypes = [BoardManClip.self, BoardManFolder.self, BoardManSnippet.self]
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
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        let defaultsSuite = "BoardManHistoryOrderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let olderClip = BoardManClip()
        olderClip.dataHash = "older"
        olderClip.createdTime = 1_000
        olderClip.updateTime = 100

        let newerClip = BoardManClip()
        newerClip.dataHash = "newer"
        newerClip.createdTime = 2_000
        newerClip.updateTime = 200

        store.upsertClip(olderClip)
        store.upsertClip(newerClip)

        #expect(store.clipsSortedByCreatedTimeDescending().first?.dataHash == "newer")
        #expect(PasteCountStore(defaults: defaults, store: store).markUsed(clip: olderClip))
        #expect(store.clip(identifier: olderClip.dataHash)?.createdTime == 1_000)
        #expect(store.clipsSortedByUpdateTimeDescending().first?.dataHash == "older")
        #expect(store.clipsSortedByCreatedTimeDescending().first?.dataHash == "newer")
    }

    @Test
    func clipboardTextReconciliationRemovesOnlyExactDuplicatedLineBreaks() {
        let richText = "A\nB\n\nC"
        let duplicatedPlainText = "A\n\nB\n\n\n\nC"

        #expect(BoardManClipData.preferredTextValue(
            plainText: duplicatedPlainText,
            richText: richText
        ) == richText)
    }

    @Test
    func clipboardTextReconciliationHandlesChromeHTMLTrailingLineBreak() {
        let chromePlainText = "A\n\nB\n\nC"
        let htmlAsText = "A\nB\nC\n"
        #expect(BoardManClipData.preferredTextValue(
            plainText: chromePlainText,
            richText: htmlAsText
        ) == "A\nB\nC")
    }

    @Test
    func clipboardTextReconciliationHandlesNonUniformExtraLineBreaks() {
        let richText = "A\nB\n\nC\nD"
        let chromePlainText = "A\n\nB\n\n\nC\n\nD"

        #expect(BoardManClipData.preferredTextValue(
            plainText: chromePlainText,
            richText: richText
        ) == richText)
    }

    @Test
    func clipboardTextReconciliationDoesNotUseRichTextWhenItWouldAddLineBreaks() {
        let plainText = "A\nB"
        let richerLayout = "A\n\nB"

        #expect(BoardManClipData.preferredTextValue(
            plainText: plainText,
            richText: richerLayout
        ) == plainText)
    }

    @Test
    func clipboardTextReconciliationPreservesIntentionalBlankLinesWithoutProof() {
        let intentionalBlankLine = "A\nB\n\nC"
        #expect(BoardManClipData.preferredTextValue(
            plainText: intentionalBlankLine,
            richText: nil
        ) == intentionalBlankLine)

        let nonMatchingRichText = "A\nB\nC"
        #expect(BoardManClipData.preferredTextValue(
            plainText: intentionalBlankLine,
            richText: nonMatchingRichText
        ) == intentionalBlankLine)
    }

    @Test
    func clipboardTextReconciliationCanonicalizesLineEndingEncoding() {
        #expect(BoardManClipData.preferredTextValue(
            plainText: "A\r\nB\r\n\r\nC",
            richText: nil
        ) == "A\nB\n\nC")
    }

    @Test
    func pasteCountCacheUpdatesImmediatelyAndFlushesToDefaults() throws {
        let defaultsSuite = "PasteCountCacheTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let clip = BoardManClip()
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
    func chromiumPasteTargetsReceiveLongerActivationSettleDelay() {
        #expect(BoardManPanelPasteCoordinator.pasteTargetSettleDelay(bundleIdentifier: "com.google.chrome.for.testing") == 0.24)
        #expect(BoardManPanelPasteCoordinator.pasteTargetSettleDelay(bundleIdentifier: "com.brave.Browser") == 0.24)
        #expect(BoardManPanelPasteCoordinator.pasteTargetSettleDelay(bundleIdentifier: "com.microsoft.edgemac") == 0.24)
        #expect(BoardManPanelPasteCoordinator.pasteTargetSettleDelay(bundleIdentifier: "com.apple.TextEdit") == 0.08)
        #expect(BoardManPanelPasteCoordinator.pasteTargetSettleDelay(bundleIdentifier: nil) == 0.08)
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
            withRootObject: BoardManClipData(image: firstImage),
            requiringSecureCoding: false
        )
        let decodedObject = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encoded)
        let decodedData = try #require(decodedObject as? BoardManClipData)
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

@Suite(.serialized)
final class BoardManPersistenceCompatibilityTests {

    @Test
    func boardManRealmTypesKeepLegacyTableNames() throws {
        #expect(BoardManClip.className() == "CPYClip")
        #expect(BoardManFolder.className() == "CPYFolder")
        #expect(BoardManSnippet.className() == "CPYSnippet")

        var configuration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        configuration.objectTypes = [BoardManClip.self, BoardManFolder.self, BoardManSnippet.self]
        let realm = try Realm(configuration: configuration)

        #expect(realm.schema["CPYClip"] != nil)
        #expect(realm.schema["CPYFolder"] != nil)
        #expect(realm.schema["CPYSnippet"] != nil)
        #expect(realm.schema["BoardManClip"] == nil)
        #expect(realm.schema["BoardManFolder"] == nil)
        #expect(realm.schema["BoardManSnippet"] == nil)
    }

    @Test
    func legacyClipDataArchiveNamesResolveToBoardManType() {
        BoardManClipData.registerLegacyArchiveAliases()

        #expect(NSKeyedUnarchiver.class(forClassName: "CPYClipData") === BoardManClipData.self)
        #expect(NSKeyedUnarchiver.class(forClassName: "Clipy.CPYClipData") === BoardManClipData.self)
        #expect(NSKeyedUnarchiver.class(forClassName: "Board_Man.CPYClipData") === BoardManClipData.self)
    }
}

@MainActor @Suite(.serialized)
final class BoardManInteractionRuleTests {

    @Test
    func previewScaleAndHorizontalNavigationRulesAreBounded() {
        #expect(BoardManPanel.clampedPreviewScale(0) == 100)
        #expect(BoardManPanel.clampedPreviewScale(20) == 50)
        #expect(BoardManPanel.clampedPreviewScale(250) == 200)
        #expect(BoardManPanel.effectivePreviewScale(storedValue: 50, isPro: false) == 50)
        #expect(BoardManPanel.effectivePreviewScale(storedValue: 50, isPro: true) == 50)
        #expect(BoardManPanel.effectivePreviewScale(storedValue: 200, isPro: true) == 200)
        #expect(BoardManPanel.clampedItemTextScale(0) == 100)
        #expect(BoardManPanel.clampedItemTextScale(60) == 80)
        #expect(BoardManPanel.clampedItemTextScale(120) == 120)
        #expect(BoardManPanel.clampedItemTextScale(170) == 140)

        #expect(BoardManPanel.tabDelta(horizontalDelta: -30, verticalDelta: 3) == 1)
        #expect(BoardManPanel.tabDelta(horizontalDelta: 30, verticalDelta: 3) == -1)
        #expect(BoardManPanel.tabDelta(horizontalDelta: 10, verticalDelta: 0) == nil)
        #expect(BoardManPanel.tabDelta(horizontalDelta: 30, verticalDelta: 28) == nil)
        #expect(BoardManPanel.usesStackedHistorySettingsLayout(width: 519))
        #expect(!BoardManPanel.usesStackedHistorySettingsLayout(width: 520))
        #expect(BoardManPanel.usesStackedAppearanceSettingsLayout(width: 469))
        #expect(!BoardManPanel.usesStackedAppearanceSettingsLayout(width: 470))
        #expect(BoardManHistoryRowView.backgroundKind(
            isSelected: true,
            isHovered: false,
            hasHighlight: true,
            hasUsedAppearance: true
        ) == .highlight)
        #expect(BoardManHistoryRowView.backgroundKind(
            isSelected: true,
            isHovered: false,
            hasHighlight: false,
            hasUsedAppearance: true
        ) == .selected)
    }

    @Test
    func historySnippetLinksTrackBothDirectionsAndCanBeRemoved() {
        let suiteName = "BoardManHistorySnippetLinksTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = HistorySnippetLinkStore(defaults: defaults)

        store.link(snippetIdentifier: "snippet-a", historyIdentifier: "history-1")
        store.link(snippetIdentifier: "snippet-b", historyIdentifier: "history-1")
        #expect(store.historyIdentifier(forSnippet: "snippet-a") == "history-1")
        #expect(store.snippetIdentifiers(forHistory: "history-1") == ["snippet-a", "snippet-b"])

        store.unlinkSnippet("snippet-a")
        #expect(store.historyIdentifier(forSnippet: "snippet-a") == nil)
        #expect(store.snippetIdentifiers(forHistory: "history-1") == ["snippet-b"])

        store.unlinkHistory("history-1")
        #expect(store.historyIdentifier(forSnippet: "snippet-b") == nil)
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
    func historyCellMasksContentAndKeepsPinOnTheLeft() throws {
        let defaults = AppEnvironment.current.defaults
        let originalPinLabelStyle = defaults.string(forKey: Constants.UserDefaults.boardManPinLabelStyle)
        defaults.set(BoardManPinLabelStyle.full.rawValue, forKey: Constants.UserDefaults.boardManPinLabelStyle)
        defer {
            if let originalPinLabelStyle {
                defaults.set(originalPinLabelStyle, forKey: Constants.UserDefaults.boardManPinLabelStyle)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.boardManPinLabelStyle)
            }
        }

        let cell = BoardManHistoryCellView(frame: NSRect(x: 0, y: 0, width: 760, height: 62))
        let item = BoardManHistoryItem(
            title: "secret content",
            primaryTitle: "secret content",
            compactTitle: "secret content",
            metadataText: "now",
            timestampText: "now",
            countText: "12",
            previewTitle: "secret content",
            dataHash: "masked-item",
            imageDataPath: "",
            inlineThumbnail: nil,
            pasteCount: 12,
            isPinned: true,
            isMasked: true,
            isEnabled: true,
            source: .clip,
            categoryIdentifier: nil,
            categoryTitle: nil
        )
        cell.configure(
            item: item,
            isSelected: false,
            usageStyle: "badge",
            useLiquidGlass: false,
            lightenTheme: false,
            themePreset: .defaultPreset,
            timestampPosition: .below
        )
        cell.layoutSubtreeIfNeeded()

        let descendants = cell.subviews
        let primary = try #require(descendants.first {
            $0.identifier?.rawValue == "BoardManHistoryPrimaryLabel"
        } as? NSTextField)
        let pin = try #require(descendants.first {
            $0.identifier?.rawValue == "BoardManHistoryPinBadge"
        } as? NSTextField)
        let count = try #require(descendants.first {
            $0.identifier?.rawValue == "BoardManHistoryCountBadge"
        } as? NSTextField)
        #expect(primary.stringValue == "＊＊＊＊＊")
        #expect(!pin.isHidden)
        #expect(pin.frame.maxX < primary.frame.minX, "Pin must be positioned on the left side of the row.")
        #expect(primary.frame.maxX < count.frame.minX, "Usage count must remain on the right side.")

        let unselectedCellFrame = cell.frame
        let unselectedFrames = [primary.frame, pin.frame, count.frame]
        cell.configure(
            item: item,
            isSelected: true,
            usageStyle: "badge",
            useLiquidGlass: false,
            lightenTheme: false,
            themePreset: .defaultPreset,
            timestampPosition: .below
        )
        cell.layoutSubtreeIfNeeded()
        #expect(cell.frame == unselectedCellFrame,
                "Selection must not resize the history or snippet cell.")
        #expect([primary.frame, pin.frame, count.frame] == unselectedFrames,
                "Selection must not shift history or snippet row contents horizontally.")
        let selectedFontSize = primary.font?.pointSize
        cell.configure(
            item: item,
            isSelected: false,
            usageStyle: "badge",
            useLiquidGlass: false,
            lightenTheme: false,
            themePreset: .defaultPreset,
            timestampPosition: .below
        )
        cell.layoutSubtreeIfNeeded()
        #expect(primary.font?.pointSize == selectedFontSize,
                "Clearing selection must restore the same row text size instead of leaving a larger selected font behind.")

        let narrowCell = BoardManHistoryCellView(frame: NSRect(x: 0, y: 0, width: 600, height: 46))
        let narrowItem = BoardManHistoryItem(
            title: "A long reusable template title that must absorb narrow-width compression",
            primaryTitle: "A long reusable template title that must absorb narrow-width compression",
            compactTitle: "A long reusable template title that must absorb narrow-width compression",
            metadataText: "22h",
            timestampText: "22h",
            countText: "",
            previewTitle: "A long reusable template title that must absorb narrow-width compression",
            dataHash: "narrow-pinned-item",
            imageDataPath: "",
            inlineThumbnail: nil,
            pasteCount: 0,
            isPinned: true,
            isMasked: false,
            isEnabled: true,
            source: .clip,
            categoryIdentifier: nil,
            categoryTitle: nil
        )
        narrowCell.configure(
            item: narrowItem,
            isSelected: false,
            usageStyle: "badge",
            useLiquidGlass: false,
            lightenTheme: false,
            themePreset: .defaultPreset,
            timestampPosition: .right
        )
        narrowCell.layoutSubtreeIfNeeded()
        let narrowPrimary = try #require(narrowCell.subviews.first {
            $0.identifier?.rawValue == "BoardManHistoryPrimaryLabel"
        } as? NSTextField)
        let narrowPin = try #require(narrowCell.subviews.first {
            $0.identifier?.rawValue == "BoardManHistoryPinBadge"
        } as? NSTextField)
        let narrowTimestamp = try #require(narrowCell.subviews.first {
            $0.identifier?.rawValue == "BoardManHistoryTimestampLabel"
        } as? NSTextField)
        #expect(narrowPin.frame.width == 44, "Narrow rows must not squeeze the Pin badge.")
        #expect(narrowTimestamp.frame.width == 72, "Narrow rows must not squeeze the timestamp.")
        #expect(narrowPrimary.frame.minX - narrowPin.frame.maxX >= 12,
                "Narrow rows need stable breathing room after the Pin badge.")
        #expect(narrowPrimary.frame.maxX <= narrowTimestamp.frame.minX - 12,
                "Only the center title may compress between fixed accessories.")
        let configuredTextScale = CGFloat(BoardManPanel.clampedItemTextScale(
            AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManItemTextScale)
        )) / 100
        #expect((narrowPrimary.font?.pointSize ?? 99) <= (12.75 * configuredTextScale) + 0.01,
                "Narrow rows should use the compact title font at the configured text scale instead of squeezing accessories.")

        let resizedCellFrame = BoardManHistoryCellView.synchronizedCellFrame(
            existingFrame: NSRect(x: 14, y: 0, width: 746, height: 46),
            safeWidth: 600
        )
        #expect(resizedCellFrame.minX == 14,
                "Responsive resizing must preserve the native table-cell leading inset.")
        #expect(resizedCellFrame.maxX == 600,
                "Responsive resizing must fill the remaining width without removing the leading inset.")
    }

    @Test
    func capCenteredTextFrameKeepsCapitalCenterStableAndFitsDescendersAcrossScales() {
        let capCenterY: CGFloat = 23
        for scale in [0.8, 1.0, 1.3, 1.4] {
            let font = NSFont.systemFont(ofSize: 13.5 * scale, weight: .medium)
            let label = NSTextField(labelWithString: "F g y p q j")
            label.font = font
            let frame = boardManCapCenteredTextFrame(
                for: label,
                originX: 10,
                width: 280,
                capCenterY: capCenterY
            )
            let baselineY = frame.maxY - label.firstBaselineOffsetFromTop
            let resolvedCapCenterY = baselineY + (font.capHeight / 2)
            let descenderBottomY = baselineY + font.descender

            #expect(abs(resolvedCapCenterY - capCenterY) < 0.001,
                    "Capital-height center must stay fixed regardless of text scale.")
            #expect(descenderBottomY >= frame.minY - 0.001,
                    "Font descenders must fit inside the dynamically sized text frame.")
        }
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
        #expect(BoardManTimestampInteraction.allowed("clickMask") == .clickMask)
        #expect(BoardManTimestampInteraction.allowed("longPressMask") == .longPressMask)
        #expect(BoardManTimestampInteraction.click.runsShortcutOnClick)
        #expect(BoardManTimestampInteraction.longPress.runsShortcutOnLongPress)
        #expect(BoardManTimestampInteraction.clickMask.togglesMaskOnClick)
        #expect(BoardManTimestampInteraction.longPressMask.togglesMaskOnLongPress)
        #expect(BoardManLongPressAction.allowed("toggleMask") == .toggleMask)

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
final class BoardManTimestampHitTests {
    @Test
    func rightTimestampHitRectCoversVisibleTimestampOnly() throws {
        let metadataLabel = NSTextField(labelWithString: "")
        let timestampFrame = NSRect(x: 640, y: 13, width: 72, height: 20)
        let hitRect = try #require(boardManTimestampHitRect(
            timestampText: "22h",
            timestampPosition: .right,
            timestampAccessoryFrame: timestampFrame,
            metadataLabel: metadataLabel
        ))
        #expect(hitRect.contains(NSPoint(x: timestampFrame.midX, y: timestampFrame.midY)))
        #expect(!hitRect.contains(NSPoint(x: timestampFrame.minX - 20, y: timestampFrame.midY)))
    }
}

final class BoardManFilterSettingsTests {

    @Test
    func savedFiltersPersistCriteriaSelectionAndValidGroups() throws {
        let suiteName = "BoardManSavedFilterTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BoardManSavedFilterStore(defaults: defaults)
        let condition = BoardManHistoryCondition(
            isEnabled: true,
            minimumLength: 12,
            includedTerms: ["deploy", "release"],
            excludedTerms: ["draft"],
            matchesAllIncludedTerms: false,
            shellLikeOnly: true
        )
        let preset = BoardManSavedFilterPreset(
            id: "release-filter",
            name: "Release commands",
            usageFilterRawValue: BoardManHistoryUsageFilter.used.rawValue,
            condition: condition,
            snippetGroupIdentifiers: ["group-a", "deleted-group"]
        )

        #expect(store.presets.isEmpty)
        #expect(preset.hasCriteria)
        _ = store.save(preset)
        #expect(store.presets == [preset])
        #expect(store.selectedPreset == preset)
        #expect(store.selectedPreset?.usageFilter == .used)
        #expect(preset.validSnippetGroupIdentifiers(availableIdentifiers: ["group-a", "group-b"]) == ["group-a"])

        var renamed = preset
        renamed.name = "Release only"
        _ = store.save(renamed)
        #expect(store.presets == [renamed])
        #expect(store.selectedPreset?.name == "Release only")

        store.delete(renamed.id)
        #expect(store.presets.isEmpty)
        #expect(store.selectedPresetID == nil)
    }

}

@MainActor @Suite(.serialized)
final class BoardManUIRegressionTests {

    @Test
    func majorTabsAndSettingsCategoriesStayInsidePanel() async throws {
        let originalRealmConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        defer { Realm.Configuration.defaultConfiguration = originalRealmConfiguration }

        let defaults = AppEnvironment.current.defaults
        let originalTimestampFormat = defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat)
        let originalTimestampPosition = defaults.string(forKey: Constants.UserDefaults.boardManTimestampPosition)
        let originalLanguage = defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        let originalUIStyle = defaults.string(forKey: Constants.UserDefaults.boardManUIStyle)
        let originalItemTextScale = defaults.object(forKey: Constants.UserDefaults.boardManItemTextScale)
        let originalMaxHistory = defaults.object(forKey: Constants.UserDefaults.maxHistorySize)
        defaults.set("relative", forKey: Constants.UserDefaults.boardManTimestampFormat)
        defaults.set("below", forKey: Constants.UserDefaults.boardManTimestampPosition)
        defaults.set("English", forKey: Constants.UserDefaults.boardManLanguage)
        defaults.set("Default", forKey: Constants.UserDefaults.boardManUIStyle)
        defaults.set(100, forKey: Constants.UserDefaults.boardManItemTextScale)
        defaults.set(100, forKey: Constants.UserDefaults.maxHistorySize)
        defer {
            defaults.set(originalTimestampFormat, forKey: Constants.UserDefaults.boardManTimestampFormat)
            defaults.set(originalTimestampPosition, forKey: Constants.UserDefaults.boardManTimestampPosition)
            defaults.set(originalLanguage, forKey: Constants.UserDefaults.boardManLanguage)
            defaults.set(originalUIStyle, forKey: Constants.UserDefaults.boardManUIStyle)
            if let originalItemTextScale {
                defaults.set(originalItemTextScale, forKey: Constants.UserDefaults.boardManItemTextScale)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.boardManItemTextScale)
            }
            if let originalMaxHistory {
                defaults.set(originalMaxHistory, forKey: Constants.UserDefaults.maxHistorySize)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.maxHistorySize)
            }
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
            assertSnippetManagerControls(root)
        }

        panel.selectSettingsTab()
        await settlePanelLayout(panel)
        guard let root = panel.contentView else {
            Issue.record("Settings content view was not created.")
            return
        }
        let expectedTitles = Set(["General", "Appearance", "History", "Templates", "Privacy", "Updates", "License"])
        let categories = allSubviews(of: root)
            .compactMap { $0 as? BoardManSettingsCategoryButton }
            .filter { expectedTitles.contains($0.title) }
            .sorted { $0.tag < $1.tag }
        #expect(panel.presentationItemScope == .historyOnly)
        #expect(categories.count == expectedTitles.count, "Settings sidebar did not create all categories.")
        let settingsScroll = allSubviews(of: root)
            .compactMap { $0 as? NSScrollView }
            .first { $0.identifier?.rawValue == "BoardManSettingsScrollView" }
        #expect(settingsScroll?.isHidden == false, "Settings content scroll view is not visible.")
        #expect((settingsScroll?.documentView?.frame.height ?? 0) >= (settingsScroll?.contentView.bounds.height ?? 0),
                "Settings document is shorter than its viewport and cannot provide stable scrolling.")
        if let documentView = settingsScroll?.documentView {
            #expect(categories.allSatisfy { !$0.isDescendant(of: documentView) },
                    "Settings sidebar categories must stay fixed outside the scrolling document.")
        }
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
            let appearanceViews = allSubviews(of: root)
            let popupTitles = appearanceViews
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

            func view<T: NSView>(_ identifier: String, as type: T.Type = T.self) -> T? {
                appearanceViews.first { $0.identifier?.rawValue == identifier } as? T
            }
            let previewCard = try #require(view("BoardManAppearancePreviewCard", as: BoardManSettingsCardView.self))
            let preview = try #require(view("BoardManAppearanceLivePreview", as: BoardManAppearancePreviewView.self))
            let layoutCard = try #require(view("BoardManAppearanceLayoutCard", as: BoardManSettingsCardView.self))
            let timestampCard = try #require(view("BoardManAppearanceTimestampCard", as: BoardManSettingsCardView.self))
            let usageCard = try #require(view("BoardManAppearanceUsageCard", as: BoardManSettingsCardView.self))
            let themeCard = try #require(view("BoardManAppearanceThemeCard", as: BoardManSettingsCardView.self))
            let advancedCard = try #require(view("BoardManAppearanceAdvancedCard", as: BoardManSettingsCardView.self))
            let advancedToggle = try #require(view("BoardManAppearanceAdvancedToggle", as: NSButton.self))
            try assertItemTextScaleControls(appearanceViews)

            #expect(previewCard.isHidden == false && preview.isHidden == false)
            #expect(previewCard.frame.contains(preview.frame), "Live preview must remain inside the preview card.")
            #expect(preview.frame.minX - previewCard.frame.minX >= 20,
                    "Live preview needs deliberate horizontal breathing room.")
            #expect(preview.frame.minY - previewCard.frame.minY >= 16,
                    "Live preview needs deliberate bottom breathing room.")
            #expect(layoutCard.frame.minY > timestampCard.frame.maxY,
                    "Narrow Appearance settings should stack Layout above Timestamp.")
            #expect(timestampCard.frame.minY > usageCard.frame.maxY,
                    "Narrow Appearance settings should stack Timestamp above Usage.")
            #expect(usageCard.frame.minY > themeCard.frame.maxY,
                    "Narrow Appearance settings should stack Usage above Theme.")
            #expect(advancedToggle.isHidden == false)
            #expect(advancedCard.isHidden, "Advanced appearance settings should start collapsed.")

            if let uiPopup = appearanceViews.compactMap({ $0 as? NSPopUpButton }).first(where: {
                Set(["Default", "Simple", "Monochrome"]).isSubset(of: Set($0.itemTitles))
            }) {
                uiPopup.selectItem(withTitle: "Simple")
                _ = uiPopup.sendAction(uiPopup.action, to: uiPopup.target)
                await settlePanelLayout(panel)
                #expect(preview.uiStyleRawValueForTesting == "Simple",
                        "Live preview must consume the selected UI style instead of rendering the default style.")
            } else {
                Issue.record("Appearance UI style popup was not found.")
            }

            let relativePopupIDs = [
                "BoardManRelativeNumberStylePopup", "BoardManRelativeUnitStylePopup",
                "BoardManRelativeSuffixStylePopup", "BoardManRelativeNowStylePopup"
            ]
            let relativePopups = relativePopupIDs.compactMap { identifier in
                appearanceViews.first { $0.identifier?.rawValue == identifier } as? NSPopUpButton
            }
            #expect(relativePopups.count == relativePopupIDs.count)
            #expect(relativePopups.allSatisfy { $0.isHidden },
                    "Fine-grained relative-time controls should stay out of the default view.")

            let collapsedDocumentHeight = settingsScroll?.documentView?.frame.height ?? 0
            _ = advancedToggle.sendAction(advancedToggle.action, to: advancedToggle.target)
            await settlePanelLayout(panel)
            #expect(advancedCard.isHidden == false)
            #expect(relativePopups.allSatisfy { !$0.isHidden })
            #expect((settingsScroll?.documentView?.frame.height ?? 0) > collapsedDocumentHeight,
                    "Expanding advanced appearance should grow the scroll document rather than cramming controls.")

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
            #expect(alignedPopups.count == 6, "Appearance core popups could not be identified.")
            for popup in alignedPopups + relativePopups {
                #expect(abs(popup.frame.height - 30) <= 0.5,
                        "Appearance popup height is not aligned to the 30pt control grid.")
            }

            let textScale = allSubviews(of: root).first { $0.identifier?.rawValue == "BoardManTextPreviewScaleSlider" }
            let imageScale = allSubviews(of: root).first { $0.identifier?.rawValue == "BoardManImagePreviewScaleSlider" }
            #expect(textScale is NSSlider)
            #expect(imageScale is NSSlider)
            #expect(textScale?.isHidden == false && imageScale?.isHidden == false)
            #expect(abs((textScale?.frame.width ?? 0) - (imageScale?.frame.width ?? 0)) <= 0.5)
        }

        for category in categories {
            _ = category.sendAction(category.action, to: category.target)
            await settlePanelLayout(panel)
            assertTopLevelLayout(panel, mode: "Settings category \(category.tag)", expectsSearch: false)

            assertSettingsCategoryControls(title: category.title, descendants: allSubviews(of: root))
        }
    }

    private func assertItemTextScaleControls(_ views: [NSView]) throws {
        let field = try #require(views.first {
            $0.identifier?.rawValue == "BoardManItemTextScaleField"
        } as? NSTextField)
        let decrease = try #require(views.first {
            $0.identifier?.rawValue == "BoardManItemTextScaleDecreaseButton"
        } as? NSButton)
        let increase = try #require(views.first {
            $0.identifier?.rawValue == "BoardManItemTextScaleIncreaseButton"
        } as? NSButton)
        let formatter = try #require(field.formatter as? NumberFormatter)

        #expect(!field.isHidden && !decrease.isHidden && !increase.isHidden)
        #expect(field.integerValue == 100)
        #expect(formatter.minimum?.intValue == 80 && formatter.maximum?.intValue == 140)
        _ = increase.sendAction(increase.action, to: increase.target)
        #expect(field.integerValue == 105)
        _ = decrease.sendAction(decrease.action, to: decrease.target)
        #expect(field.integerValue == 100)
        field.integerValue = 141
        _ = field.sendAction(field.action, to: field.target)
        #expect(field.integerValue == 140)
        field.integerValue = 100
        _ = field.sendAction(field.action, to: field.target)
    }

    private func assertSnippetManagerControls(_ root: NSView) {
        let descendants = allSubviews(of: root)
        let titleField = descendants.first { $0.identifier?.rawValue == "BoardManSnippetEditorTitleField" } as? NSTextField
        let statusLabel = descendants.first { $0.identifier?.rawValue == "BoardManSnippetEditorStatusLabel" } as? NSTextField
        let saveButton = descendants.first { $0.identifier?.rawValue == "BoardManSnippetSaveButton" } as? NSButton
        let cancelButton = descendants.first { $0.identifier?.rawValue == "BoardManSnippetCancelButton" } as? NSButton
        let folderToggle = descendants.compactMap { $0 as? NSButton }.first { $0.title == "Group Enabled" }
        let snippetToggle = descendants.compactMap { $0 as? NSButton }.first { $0.title == "Snippet Enabled" }
        let hoverGroupPopup = descendants.compactMap { $0 as? BoardManHoverPopUpButton }.first { !$0.isHidden }
        let groupPopup = descendants.first {
            $0.identifier?.rawValue == "BoardManSnippetGroupPopup"
        } as? NSPopUpButton

        #expect(titleField != nil, "Snippet title editor was not created.")
        #expect((groupPopup?.selectedItem?.representedObject as? String) == BoardManPanel.allCategoriesIdentifier,
                "Empty snippet group selection should visibly fall back to All Groups.")
        #expect(saveButton?.target != nil && saveButton?.action != nil,
                "Snippet Save button is missing its action wiring.")
        #expect(cancelButton?.target != nil && cancelButton?.action != nil,
                "Snippet Cancel button is missing its action wiring.")
        #expect(hoverGroupPopup != nil, "Snippet group selector is not hover-aware.")
        let snippetTable = descendants.compactMap { $0 as? NSTableView }.first { !$0.isHidden }
        #expect(snippetTable?.doubleAction != nil,
                "Templates table must expose a double-click action for editing.")
        #expect((titleField?.frame.width ?? 0) >= 250, "Snippet title editor is still cramped.")
        if let titleField, let statusLabel, let folderToggle, let snippetToggle {
            #expect(statusLabel.isHidden, "The redundant snippet editor status band should remain removed.")
            #expect(abs(folderToggle.frame.midY - snippetToggle.frame.midY) <= 0.5)
            #expect(folderToggle.frame.minY >= 12, "Snippet enable controls need deliberate bottom padding.")
            #expect(titleField.frame.maxY <= (titleField.superview?.bounds.maxY ?? titleField.frame.maxY) - 12,
                    "Snippet title needs deliberate top padding.")
        }
    }

}

extension BoardManUIRegressionTests {

    @Test
    func searchEditingHoverAndFilterPresentationStayStable() async throws {
        let originalRealmConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        defer { Realm.Configuration.defaultConfiguration = originalRealmConfiguration }

        let panel = BoardManPanel()
        panel.setFrame(NSRect(x: 0, y: 0, width: 800, height: 760), display: false)
        defer { panel.orderOut(nil) }
        await presentPanelForTesting(panel)

        let root = try #require(panel.contentView)
        let descendants = allSubviews(of: root)
        let tabs = try #require(descendants.compactMap { $0 as? BoardManHeaderTabBar }.first)
        #expect(!(tabs is NSSegmentedControl),
                "Header tabs must not use NSSegmentedControl because AppKit adds a system hover halo.")
        #expect(tabs.layer?.masksToBounds == true)
        #expect((tabs.layer?.shadowOpacity ?? 1) == 0)
        #expect(tabs.buttons.allSatisfy { !$0.isBordered && $0.focusRingType == .none })
        #expect(tabs.buttons.allSatisfy { ($0.layer?.shadowOpacity ?? 1) == 0 })
        let tabFrameBeforeHover = tabs.frame
        let buttonFramesBeforeHover = tabs.buttons.map(\.frame)
        let trailingTab = 1
        tabs.updateHoveredTab(at: NSPoint(x: tabs.bounds.maxX - 4, y: tabs.bounds.midY))
        let trailingHoverRect = try #require(tabs.hoverBackgroundRect(forTab: trailingTab))
        #expect(tabs.hoveredIndex == trailingTab)
        #expect(trailingHoverRect.maxX <= tabs.bounds.maxX)
        #expect(trailingHoverRect.minX >= tabs.bounds.minX)
        #expect(tabs.frame == tabFrameBeforeHover, "Hover must not resize or move the tab bar.")
        #expect(tabs.buttons.map(\.frame) == buttonFramesBeforeHover,
                "Hover must not change either custom tab button frame.")
        #expect((tabs.layer?.shadowOpacity ?? 1) == 0,
                "Hover must never add an outer glow to the custom tab capsule.")

        let search = try #require(descendants.compactMap { $0 as? NSSearchField }.first)
        let searchCell = try #require(search.cell as? BoardManCenteredSearchFieldCell)
        let searchFrameBeforeEditing = search.frame
        search.stringValue = ""
        #expect(panel.makeFirstResponder(search))
        search.selectText(nil)
        await settlePanelLayout(panel)
        let editor = try #require(search.currentEditor() as? NSTextView)
        let editorFrameAtInputStart = editor.frame
        search.stringValue = "layout"
        await settlePanelLayout(panel)
        #expect(editor.frame == editorFrameAtInputStart,
                "Entering search text must not move the field editor.")
        #expect(search.frame == searchFrameBeforeEditing,
                "Starting search input must not move or resize the search control.")
        let textRect = searchCell.searchTextRect(forBounds: search.bounds)
        let cancelRect = searchCell.cancelButtonRect(forBounds: search.bounds)
        #expect(abs(cancelRect.midY - textRect.midY) <= 0.5,
                "The search clear button must stay vertically aligned with the input text.")
        search.stringValue = ""
        search.abortEditing()

        let conditionButton = try #require(allSubviews(of: root)
            .compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "BoardManHistoryConditionButton" })
        _ = conditionButton.sendAction(conditionButton.action, to: conditionButton.target)
        await settlePanelLayout(panel)
        await settlePanelLayout(panel)
        let sheet = try #require(panel.attachedSheet)
        #expect(sheet.sheetParent === panel,
                "The history filter must remain an attached sheet above Board-Man.")
        await waitForWindowVisibility(sheet, toEqual: true)
        #expect(sheet.isVisible, "The history filter sheet was not visible after opening.")
        panel.endSheet(sheet, returnCode: .cancel)
        sheet.orderOut(nil)
    }

    @Test
    func snippetEditModeWaitsForClickAndUsesReadableTextSurface() async throws {
        let originalRealmConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        defer { Realm.Configuration.defaultConfiguration = originalRealmConfiguration }

        let realm = try Realm()
        let folder = BoardManFolder()
        folder.title = "Test group"
        folder.enable = true
        let snippet = BoardManSnippet()
        snippet.title = "Deploy command"
        snippet.content = "git status && git push"
        snippet.enable = true
        folder.snippets.append(snippet)
        try realm.write {
            realm.add(folder)
        }

        let panel = BoardManPanel()
        panel.setFrame(NSRect(x: 0, y: 0, width: 800, height: 760), display: false)
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        panel.openSnippetsManagerMode()
        panel.loadItemsForTesting([
            BoardManHistoryItem(
                title: snippet.title,
                primaryTitle: snippet.title,
                compactTitle: snippet.title,
                metadataText: folder.title,
                timestampText: "",
                countText: "",
                previewTitle: snippet.content,
                dataHash: snippet.identifier,
                imageDataPath: "",
                inlineThumbnail: nil,
                pasteCount: 0,
                isPinned: false,
                isMasked: false,
                isEnabled: true,
                source: .snippet,
                categoryIdentifier: folder.identifier,
                categoryTitle: folder.title
            )
        ])
        panel.selectItemForTesting(at: 0)
        await settlePanelLayout(panel)

        let root = try #require(panel.contentView)
        let descendants = allSubviews(of: root)
        let editButton = try #require(descendants.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "BoardManSnippetEditButton"
        })
        let titleField = try #require(descendants.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "BoardManSnippetEditorTitleField"
        })
        let contentView = try #require(descendants.compactMap { $0 as? NSTextView }.first {
            $0.identifier?.rawValue == "BoardManSnippetEditorTextView"
        })
        let contentScroll = try #require(descendants.compactMap { $0 as? NSScrollView }.first {
            $0.identifier?.rawValue == "BoardManSnippetEditorScrollView"
        })

        #expect(!titleField.isEditable)
        #expect(!contentView.isEditable)
        _ = editButton.sendAction(editButton.action, to: editButton.target)
        await settlePanelLayout(panel)
        #expect(titleField.isEditable && titleField.isSelectable)
        #expect(contentView.isEditable && contentView.isSelectable)
        #expect(titleField.currentEditor() == nil,
                "Entering edit mode must not automatically focus the title field.")
        #expect(contentView.string == snippet.content)
        #expect(titleField.textColor == .textColor)
        #expect(titleField.backgroundColor == .textBackgroundColor)
        #expect(contentView.textColor == .textColor)
        #expect(contentView.backgroundColor == .textBackgroundColor)
        #expect(contentScroll.backgroundColor == .textBackgroundColor)

        #expect(panel.makeFirstResponder(titleField))
        titleField.selectText(nil)
        #expect(titleField.currentEditor() != nil,
                "The title field must become editable after the user focuses it.")
        titleField.abortEditing()
        #expect(panel.makeFirstResponder(contentView),
                "The content field must become editable after the user focuses it.")
    }

    @Test
    func settingsUpdateTextUsesDynamicReadableColors() async throws {
        let originalRealmConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        defer { Realm.Configuration.defaultConfiguration = originalRealmConfiguration }

        let panel = BoardManPanel()
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.setFrame(NSRect(x: 0, y: 0, width: 800, height: 760), display: false)
        panel.selectSettingsTab()
        await settlePanelLayout(panel)
        let root = try #require(panel.contentView)
        let updatesButton = try #require(allSubviews(of: root)
            .compactMap { $0 as? BoardManSettingsCategoryButton }
            .first { $0.tag == 5 })
        _ = updatesButton.sendAction(updatesButton.action, to: updatesButton.target)
        await settlePanelLayout(panel)

        let visibleTextFields = allSubviews(of: root).compactMap { $0 as? NSTextField }.filter { !$0.isHidden }
        #expect(!visibleTextFields.isEmpty)
        let darkAppearance = try #require(panel.appearance)
        for field in visibleTextFields {
            var resolvedColor: NSColor?
            darkAppearance.performAsCurrentDrawingAppearance {
                resolvedColor = (field.textColor ?? .textColor).usingColorSpace(.deviceRGB)
            }
            let color = try #require(resolvedColor)
            let luminance = (0.2126 * color.redComponent)
                + (0.7152 * color.greenComponent)
                + (0.0722 * color.blueComponent)
            #expect(luminance >= 0.35,
                    "Settings contains low-contrast dark text: \(field.stringValue), luminance=\(luminance)")
        }
    }

    private func settlePanelLayout(_ panel: BoardManPanel) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func presentPanelForTesting(_ panel: BoardManPanel) async {
        panel.orderFrontRegardless()
        await waitForWindowVisibility(panel, toEqual: true)
        await settlePanelLayout(panel)
    }

    private func waitForWindowVisibility(
        _ window: NSWindow,
        toEqual expectedVisibility: Bool,
        attempts: Int = 50
    ) async {
        for _ in 0..<attempts {
            if window.isVisible == expectedVisibility {
                return
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
                    continuation.resume()
                }
            }
        }
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        return view.subviews + view.subviews.flatMap(allSubviews(of:))
    }
}

extension BoardManUIRegressionTests {

    @Test
    func multipleSnippetGroupsFilterTogetherAndDeletedGroupsAreDiscarded() throws {
        let originalRealmConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        defer { Realm.Configuration.defaultConfiguration = originalRealmConfiguration }

        let realm = try Realm()
        let firstFolder = BoardManFolder()
        firstFolder.title = "First"
        firstFolder.enable = true
        let secondFolder = BoardManFolder()
        secondFolder.title = "Second"
        secondFolder.enable = true
        try realm.write {
            realm.add([firstFolder, secondFolder])
        }
        let firstIdentifier = firstFolder.identifier
        let secondIdentifier = secondFolder.identifier

        func snippetItem(hash: String, folder: BoardManFolder) -> BoardManHistoryItem {
            return BoardManHistoryItem(
                title: hash,
                primaryTitle: hash,
                compactTitle: hash,
                metadataText: folder.title,
                timestampText: "",
                countText: "",
                previewTitle: hash,
                dataHash: hash,
                imageDataPath: "",
                inlineThumbnail: nil,
                pasteCount: 0,
                isPinned: false,
                isMasked: false,
                isEnabled: true,
                source: .snippet,
                categoryIdentifier: folder.identifier,
                categoryTitle: folder.title
            )
        }

        let panel = BoardManPanel()
        panel.openSnippetsManagerMode()
        panel.loadItemsForTesting([
            snippetItem(hash: "first", folder: firstFolder),
            snippetItem(hash: "second", folder: secondFolder)
        ])
        panel.setSnippetGroupIdentifiersForTesting(Set([firstIdentifier, secondIdentifier]))

        #expect(panel.activeSnippetGroupIdentifiersForTesting == Set([firstIdentifier, secondIdentifier]))
        #expect(panel.visibleItemHashesForTesting == ["first", "second"])
        let popup = try #require(panel.contentView.flatMap { root in
            (root.subviews + root.subviews.flatMap { $0.subviews })
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.identifier?.rawValue == "BoardManSnippetGroupPopup" }
        })
        #expect(popup.itemArray.first { ($0.representedObject as? String) == firstIdentifier }?.state == .on)
        #expect(popup.itemArray.first { ($0.representedObject as? String) == secondIdentifier }?.state == .on)

        try realm.write {
            realm.delete(secondFolder)
        }
        panel.reloadSnippetGroupsForTesting()
        #expect(panel.activeSnippetGroupIdentifiersForTesting == Set([firstIdentifier]))
        #expect(panel.visibleItemHashesForTesting == ["first"])
        #expect(!popup.itemArray.contains { ($0.representedObject as? String) == secondIdentifier })
    }

    @Test
    func horizontalNavigationPolicyBoundsHistoryAllAndSnippetGroups() {
        let categories = ["all", "first", "second"]

        #expect(BoardManPanelNavigationPolicy.target(
            activeTab: .history,
            activeSnippetGroupIdentifiers: [],
            snippetCategoryIdentifiers: categories,
            delta: 1
        ) == .snippets(categoryIdentifier: "all"))
        #expect(BoardManPanelNavigationPolicy.target(
            activeTab: .snippets,
            activeSnippetGroupIdentifiers: [],
            snippetCategoryIdentifiers: categories,
            delta: 1
        ) == .snippets(categoryIdentifier: "first"))
        #expect(BoardManPanelNavigationPolicy.target(
            activeTab: .snippets,
            activeSnippetGroupIdentifiers: ["first"],
            snippetCategoryIdentifiers: categories,
            delta: 1
        ) == .snippets(categoryIdentifier: "second"))
        #expect(BoardManPanelNavigationPolicy.target(
            activeTab: .snippets,
            activeSnippetGroupIdentifiers: ["second"],
            snippetCategoryIdentifiers: categories,
            delta: 1
        ) == nil)
        #expect(BoardManPanelNavigationPolicy.target(
            activeTab: .snippets,
            activeSnippetGroupIdentifiers: [],
            snippetCategoryIdentifiers: categories,
            delta: -1
        ) == .history)
        #expect(BoardManPanelNavigationPolicy.target(
            activeTab: .settings,
            activeSnippetGroupIdentifiers: [],
            snippetCategoryIdentifiers: categories,
            delta: 1
        ) == nil)
    }

    @Test
    func horizontalArrowNavigationMovesThroughHistoryAllAndSnippetGroups() throws {
        let originalRealmConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        defer { Realm.Configuration.defaultConfiguration = originalRealmConfiguration }

        let realm = try Realm()
        let firstFolder = BoardManFolder()
        firstFolder.title = "First"
        firstFolder.index = 0
        let secondFolder = BoardManFolder()
        secondFolder.title = "Second"
        secondFolder.index = 1
        try realm.write {
            realm.add([firstFolder, secondFolder])
        }

        let firstIdentifier = firstFolder.identifier
        let secondIdentifier = secondFolder.identifier
        let panel = BoardManPanel()
        panel.selectHistoryTab()

        #expect(panel.activePanelTabForTesting == "history")

        panel.moveHorizontalNavigationForTesting(delta: 1)
        #expect(panel.activePanelTabForTesting == "snippets")
        #expect(panel.activeSnippetGroupIdentifiersForTesting.isEmpty,
                "Right from History should enter Templates at All Groups.")

        panel.moveHorizontalNavigationForTesting(delta: 1)
        #expect(panel.activeSnippetGroupIdentifiersForTesting == Set([firstIdentifier]),
                "The first Templates group should follow All Groups.")

        panel.moveHorizontalNavigationForTesting(delta: 1)
        #expect(panel.activeSnippetGroupIdentifiersForTesting == Set([secondIdentifier]),
                "Groups should follow their persisted index order.")

        panel.moveHorizontalNavigationForTesting(delta: 1)
        #expect(panel.activeSnippetGroupIdentifiersForTesting == Set([secondIdentifier]),
                "Right navigation should stop at the final group instead of wrapping.")

        panel.moveHorizontalNavigationForTesting(delta: -1)
        #expect(panel.activeSnippetGroupIdentifiersForTesting == Set([firstIdentifier]))

        panel.moveHorizontalNavigationForTesting(delta: -1)
        #expect(panel.activeSnippetGroupIdentifiersForTesting.isEmpty,
                "Left from the first group should return to All Groups.")

        panel.moveHorizontalNavigationForTesting(delta: -1)
        #expect(panel.activePanelTabForTesting == "history",
                "Left from Templates All should return to History.")

        panel.moveHorizontalNavigationForTesting(delta: -1)
        #expect(panel.activePanelTabForTesting == "history",
                "Left navigation should stop at History instead of wrapping.")
    }

    @Test
    func responsiveTemplateTabLabelsStayReadableAcrossLanguages() async throws {
        let originalRealmConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        defer { Realm.Configuration.defaultConfiguration = originalRealmConfiguration }

        let defaults = AppEnvironment.current.defaults
        let originalLanguage = defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        defer { defaults.set(originalLanguage, forKey: Constants.UserDefaults.boardManLanguage) }

        let expectations: [(BoardManLanguage, String, String)] = [
            (.english, "Templates", "Text"),
            (.japanese, "定型文", "定型"),
            (.simplifiedChinese, "模板", "模板"),
            (.korean, "문구", "문구")
        ]

        for (language, regularTitle, compactTitle) in expectations {
            defaults.set(language.rawValue, forKey: Constants.UserDefaults.boardManLanguage)
            let panel = BoardManPanel()
            panel.setFrame(NSRect(x: 0, y: 0, width: 800, height: 760), display: false)
            await settlePanelLayout(panel)
            let root = try #require(panel.contentView)
            let regularTabs = try #require(allSubviews(of: root)
                .compactMap { $0 as? BoardManHeaderTabBar }.first)
            #expect(regularTabs.snippetsButton.title == regularTitle)
            #expect(regularTabs.snippetsButton.toolTip == regularTitle)
            #expect((regularTabs.snippetsButton.font?.pointSize ?? 0) >= 12.5)

            panel.setFrame(NSRect(x: 0, y: 0, width: 640, height: 760), display: false)
            await settlePanelLayout(panel)
            #expect(regularTabs.snippetsButton.title == compactTitle)
            #expect(regularTabs.snippetsButton.toolTip == regularTitle)
            #expect((regularTabs.snippetsButton.font?.pointSize ?? 99) <= 11.25)
        }
    }

    @Test
    func panelHidesWhenApplicationDeactivates() async {
        let panel = BoardManPanel()
        #expect(panel.hidesOnDeactivate)

        await presentPanelForTesting(panel)
        #expect(panel.isVisible)

        NotificationCenter.default.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
        await settlePanelLayout(panel)
        await waitForWindowVisibility(panel, toEqual: false)
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
        let tabs = descendants.compactMap { $0 as? BoardManHeaderTabBar }.first
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

        guard let tabs = descendants.compactMap({ $0 as? BoardManHeaderTabBar }).first else {
            Issue.record("Custom hover-aware header tabs were not created.")
            return
        }
        #expect(tabs.buttons.count == 2,
                "The header should expose only History and Templates as primary tabs.")
        #expect(tabs.buttons.allSatisfy { !$0.isBordered && $0.focusRingType == .none })
        tabs.updateHoveredTab(at: NSPoint(x: tabs.bounds.maxX - 4, y: tabs.bounds.midY))
        #expect(tabs.hoveredIndex == 1, "Header hover tracking did not resolve the trailing Templates tab.")

        let settingsButton = descendants.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "BoardManSettingsButton"
        }
        #expect(settingsButton?.isHidden == false)
        #expect(settingsButton?.target != nil && settingsButton?.action != nil,
                "The header Settings gear is missing its action wiring.")
        if let settingsButton {
            #expect(abs(settingsButton.frame.midY - tabs.frame.midY) <= 0.5,
                    "The Settings gear is not vertically aligned with the primary tabs.")
        }

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
                #expect(cell.searchButtonOpticalYOffset == -2,
                        "Search icon requires the requested 2pt upward optical correction in flipped control coordinates.")
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
            .first { $0.segmentCount == 3 }
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

@MainActor
private func assertSettingsCategoryControls(title: String, descendants: [NSView]) {
    if title == "General" {
        let field = descendants.first { $0.identifier?.rawValue == "BoardManVisibleHistoryField" } as? NSTextField
        let stepper = descendants.first { $0.identifier?.rawValue == "BoardManVisibleHistoryStepper" } as? NSStepper
        let decrease = descendants.first { $0.identifier?.rawValue == "BoardManVisibleHistoryDecreaseButton" } as? NSButton
        let increase = descendants.first { $0.identifier?.rawValue == "BoardManVisibleHistoryIncreaseButton" } as? NSButton
        #expect(field?.isHidden == false && field?.isEditable == true && field?.isBezeled == true)
        #expect(field?.target != nil && field?.action != nil)
        #expect(stepper?.isHidden == true, "The native stepper should remain hidden behind the explicit minus/plus controls.")
        #expect(decrease?.isHidden == false && decrease?.target != nil && decrease?.action != nil)
        #expect(increase?.isHidden == false && increase?.target != nil && increase?.action != nil)
        if let field, let stepper, let decrease, let increase {
            #expect(decrease.frame.maxX < field.frame.minX)
            #expect(field.frame.maxX < increase.frame.minX)
            #expect(abs(field.frame.midY - decrease.frame.midY) <= 0.5)
            #expect(abs(field.frame.midY - increase.frame.midY) <= 0.5)
            field.integerValue = 250
            _ = field.sendAction(field.action, to: field.target)
            #expect(AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize) == 250)
            #expect(stepper.integerValue == 250)
        }
    } else if title == "Appearance" {
        let identifiers = ["BoardManRelativeNumberStylePopup", "BoardManRelativeUnitStylePopup",
                           "BoardManRelativeSuffixStylePopup", "BoardManRelativeNowStylePopup"]
        let popups = identifiers.compactMap { identifier in
            descendants.first { $0.identifier?.rawValue == identifier } as? NSPopUpButton
        }
        #expect(popups.count == identifiers.count)
        for popup in popups {
            #expect(popup.isHidden == false)
            #expect(abs(popup.frame.height - 30) <= 0.5)
        }
        if let referenceWidth = popups.first?.frame.width {
            #expect(popups.allSatisfy { abs($0.frame.width - referenceWidth) <= 0.5 },
                    "The Under 1 minute popup is shorter than the other relative-time controls.")
        }
    } else if title == "History" {
        let toggle = descendants.first { $0.identifier?.rawValue == "BoardManTimestampShortcutEnabledButton" } as? NSButton
        let shortcutLabel = descendants.compactMap { $0 as? NSTextField }.first {
            $0.stringValue == "Shortcut for time action"
        }
        let delay = descendants.first { $0.identifier?.rawValue == "BoardManTimestampShortcutDelayField" } as? NSTextField
        let delayStepper = descendants.first { $0.identifier?.rawValue == "BoardManTimestampShortcutDelayStepper" } as? NSStepper
        let delayDecrease = descendants.first { $0.identifier?.rawValue == "BoardManTimestampShortcutDelayDecreaseButton" } as? NSButton
        let delayIncrease = descendants.first { $0.identifier?.rawValue == "BoardManTimestampShortcutDelayIncreaseButton" } as? NSButton
        let shortcutRecord = descendants.first { $0.identifier?.rawValue == "BoardManTimestampShortcutRecordView" }
        let interaction = descendants.first { view in
            guard let popup = view as? NSPopUpButton else { return false }
            return popup.itemTitles.contains("Click: Run Shortcut Below")
        } as? NSPopUpButton
        let preset = descendants.first { $0.identifier?.rawValue == "BoardManTimedPinPresetPopup" } as? NSPopUpButton
        let add = descendants.first { $0.identifier?.rawValue == "BoardManTimedPinPresetAddButton" } as? NSButton
        let remove = descendants.first { $0.identifier?.rawValue == "BoardManTimedPinPresetRemoveButton" } as? NSButton
        let pinLabel = descendants.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Pin duration" }
        let field = descendants.first { $0.identifier?.rawValue == "BoardManTimedPinDurationField" } as? NSTextField
        let stepper = descendants.first { $0.identifier?.rawValue == "BoardManTimedPinDurationStepper" } as? NSStepper
        let decrease = descendants.first { $0.identifier?.rawValue == "BoardManTimedPinDurationDecreaseButton" } as? NSButton
        let increase = descendants.first { $0.identifier?.rawValue == "BoardManTimedPinDurationIncreaseButton" } as? NSButton
        let unit = descendants.compactMap { $0 as? NSPopUpButton }.first {
            Set(["Minutes", "Hours", "Days", "Weeks"]).isSubset(of: Set($0.itemTitles))
        }
        #expect(toggle?.isHidden == false && toggle?.target != nil && toggle?.action != nil)
        #expect(delay?.isHidden == false && delay?.isEditable == true && delay?.isBezeled == true)
        #expect(delayStepper?.isHidden == true)
        #expect(delayDecrease?.isHidden == false && delayDecrease?.target != nil && delayDecrease?.action != nil)
        #expect(delayIncrease?.isHidden == false && delayIncrease?.target != nil && delayIncrease?.action != nil)
        if let shortcutLabel, let shortcutRecord {
            #expect(shortcutLabel.frame.minY > shortcutRecord.frame.maxY,
                    "Narrow History settings should stack the shortcut label above its recorder.")
            #expect(shortcutLabel.frame.width >= shortcutRecord.frame.width,
                    "The shortcut label must not be squeezed into a truncated side column.")
        }
        #expect(interaction?.itemTitles.contains("Long Press: Run Shortcut Below") == true)
        #expect(interaction?.itemTitles.contains("Click: Hide / Show Content") == true)
        #expect(interaction?.itemTitles.contains("Long Press: Hide / Show Content") == true)
        if let toggle {
            let originalEnabled = AppEnvironment.current.defaults.bool(
                forKey: Constants.UserDefaults.boardManTimestampShortcutEnabled
            )
            defer {
                AppEnvironment.current.defaults.set(
                    originalEnabled,
                    forKey: Constants.UserDefaults.boardManTimestampShortcutEnabled
                )
            }
            toggle.state = .off
            _ = toggle.sendAction(toggle.action, to: toggle.target)
            #expect(delay?.isEnabled == true)
            #expect(delayStepper?.isEnabled == true)
            #expect(delayDecrease?.isEnabled == true)
            #expect(delayIncrease?.isEnabled == true)
            #expect(abs((shortcutRecord?.alphaValue ?? 0) - 1) <= 0.01,
                    "The timestamp shortcut must remain editable and undimmed while disabled.")
        }
        #expect(preset?.isHidden == false && (preset?.numberOfItems ?? 0) >= 1)
        #expect(add?.target != nil && add?.action != nil)
        #expect(remove?.target != nil && remove?.action != nil)
        #expect(field?.isEditable == true && field?.isSelectable == true && field?.isEnabled == true && field?.isBezeled == true)
        #expect(field?.target != nil && field?.action != nil)
        #expect(stepper?.isHidden == true)
        #expect(decrease?.isHidden == false && decrease?.target != nil && decrease?.action != nil)
        #expect(increase?.isHidden == false && increase?.target != nil && increase?.action != nil)
        if let pinLabel, let preset, let add, let remove, let field, let decrease, let increase, let unit {
            #expect(pinLabel.frame.minY > preset.frame.maxY,
                    "Pin duration label should sit above the preset control row.")
            #expect(abs(preset.frame.midY - add.frame.midY) <= 0.5)
            #expect(abs(preset.frame.midY - remove.frame.midY) <= 0.5)
            #expect(preset.frame.minY > field.frame.maxY,
                    "Preset selection should be separated from the value and unit row.")
            #expect(decrease.frame.maxX < field.frame.minX,
                    "Pin duration minus button should remain on the left of its input.")
            #expect(field.frame.maxX < increase.frame.minX)
            #expect(increase.frame.maxX < unit.frame.minX,
                    "Pin duration unit should follow the explicit minus/plus controls.")
            #expect(abs(field.frame.midY - decrease.frame.midY) <= 0.5)
            #expect(abs(field.frame.midY - increase.frame.midY) <= 0.5)
            #expect(abs(field.frame.midY - unit.frame.midY) <= 0.5)
        }
    } else if title == "Snippets" {
        let manage = descendants.first { $0.identifier?.rawValue == "BoardManManageSnippetsButton" } as? NSButton
        let scroll = descendants.first { $0.identifier?.rawValue == "BoardManSnippetShortcutScrollView" } as? NSScrollView
        #expect(manage?.isHidden == false && scroll?.isHidden == false)
        if let manage, let scroll {
            let gap = scroll.frame.minY - manage.frame.maxY
            #expect(gap >= 10 && gap <= 18,
                    "Manage Snippets should sit directly below the shortcut list with deliberate spacing.")
            #expect(manage.frame.minY >= 20, "Manage Snippets is still pinned against the bottom edge.")
        }
    }
}

// swiftlint:enable file_length
