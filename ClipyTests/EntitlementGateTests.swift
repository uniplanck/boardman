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

@MainActor @Suite(.serialized)
final class BoardManPanelLayoutTests {

    @Test
    func majorTabsAndSettingsCategoriesStayInsidePanel() async {
        let originalRealmConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        defer { Realm.Configuration.defaultConfiguration = originalRealmConfiguration }

        let panel = BoardManPanel()
        panel.setFrame(NSRect(x: 0, y: 0, width: 680, height: 760), display: false)
        await settlePanelLayout(panel)
        #expect(panel.presentationItemScope == .historyOnly)
        assertTopLevelLayout(panel, mode: "History", expectsSearch: true)
        assertHeaderChrome(panel, expectsSearch: true)
        assertHistoryRowGeometry(panel)

        panel.openSnippetsManagerMode()
        await settlePanelLayout(panel)
        #expect(panel.presentationItemScope == .complete)
        assertTopLevelLayout(panel, mode: "Snippets", expectsSearch: true)
        assertHeaderChrome(panel, expectsSearch: true)
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
            #expect((category.image?.size.width ?? 0) >= 20,
                    "Settings sidebar icon is missing its leading content inset.")
        }

        for category in categories {
            _ = category.sendAction(category.action, to: category.target)
            await settlePanelLayout(panel)
            assertTopLevelLayout(panel, mode: "Settings category \(category.tag)", expectsSearch: false)
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
            #expect(search.cell is NSSearchFieldCell,
                    "Search field is not using the native AppKit search cell.")
            #expect((search.layer?.borderWidth ?? 0) == 0,
                    "Search field has a second custom layer border.")
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
