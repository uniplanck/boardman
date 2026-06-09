import Foundation
import Testing
@testable import Clipy

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
    func freeHistoryLimitIsOneHundred() {
        let service = EntitlementService(snapshot: .freeDefault)

        #expect(EntitlementGate.canAddHistoryItem(currentCount: 99, service: service))
        #expect(!EntitlementGate.canAddHistoryItem(currentCount: 100, service: service))
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
}
