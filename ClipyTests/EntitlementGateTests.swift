import CryptoKit
import Foundation
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
