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
        #expect(entitlement.limits.maxHistoryItems == 100)
        #expect(entitlement.limits.maxPinnedItems == 3)
        #expect(entitlement.limits.maxSnippetItems == 5)
        #expect(entitlement.limits.maxSnippetFolders == 1)
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
    func freeSnippetLimitIsFive() {
        let service = EntitlementService(snapshot: .freeDefault)

        #expect(EntitlementGate.canCreateSnippet(currentSnippetCount: 4, service: service))
        #expect(!EntitlementGate.canCreateSnippet(currentSnippetCount: 5, service: service))
    }

    @Test
    func freeSnippetFolderLimitIsOne() {
        let service = EntitlementService(snapshot: .freeDefault)

        #expect(EntitlementGate.canCreateSnippetFolder(currentFolderCount: 0, service: service))
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
final class BoardManPanelLayoutTests {

    @Test
    func majorTabsAndSettingsCategoriesStayInsidePanel() async {
        let originalRealmConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        defer { Realm.Configuration.defaultConfiguration = originalRealmConfiguration }

        let defaults = AppEnvironment.current.defaults
        let originalTimestampFormat = defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat)
        let originalTimestampPosition = defaults.string(forKey: Constants.UserDefaults.boardManTimestampPosition)
        defaults.set("relative", forKey: Constants.UserDefaults.boardManTimestampFormat)
        defaults.set("below", forKey: Constants.UserDefaults.boardManTimestampPosition)
        defer {
            defaults.set(originalTimestampFormat, forKey: Constants.UserDefaults.boardManTimestampFormat)
            defaults.set(originalTimestampPosition, forKey: Constants.UserDefaults.boardManTimestampPosition)
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
        }

        for category in categories {
            _ = category.sendAction(category.action, to: category.target)
            await settlePanelLayout(panel)
            assertTopLevelLayout(panel, mode: "Settings category \(category.tag)", expectsSearch: false)
        }
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
                #expect(abs(textRect.midY - search.bounds.midY) <= 0.5,
                        "Search text is not vertically centered.")
                #expect(abs(iconRect.midY - search.bounds.midY) <= 0.5,
                        "Search icon is not vertically centered.")
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
