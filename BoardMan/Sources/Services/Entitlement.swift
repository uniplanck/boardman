//
//  Entitlement.swift
//  Board-Man
//

import Foundation

enum LicenseState: String, Equatable {
    case free
    case trial
    case proActive
    case ownerLifetime
    case proExpired
    case invalid
    case offlineGrace
    case locked
}

enum Plan: String, Equatable {
    case free
    case pro
    case ownerLifetime
}

typealias EntitlementPlan = Plan

enum EntitlementFeature: String, CaseIterable, Hashable {
    // Legacy local capabilities. These remain parseable for existing signed
    // tokens, but the MIT client no longer requires a commercial entitlement
    // to use them.
    case unlimitedHistory
    case unlimitedSnippets
    case advancedAppearance
    case exportImport
    case pasteAnalytics

    // Commercial-service capabilities. These depend on infrastructure that
    // lives outside the MIT client and therefore still require entitlement.
    case futureSync
    case cloudBackup
    case aiAssist
    case teamSharing
    case accountServices
    case apiAccess
    case commercialSupport
}

extension EntitlementFeature {
    static let appearanceAdvanced: EntitlementFeature = .advancedAppearance

    var requiresCommercialService: Bool {
        switch self {
        case .unlimitedHistory, .unlimitedSnippets, .advancedAppearance, .exportImport, .pasteAnalytics:
            return false
        case .futureSync, .cloudBackup, .aiAssist, .teamSharing, .accountServices, .apiAccess, .commercialSupport:
            return true
        }
    }
}

typealias Feature = EntitlementFeature

enum EntitlementLimit: Equatable {
    case historyItems
    case pinnedItems
    case snippetItems
    case snippetFolders
}

struct PlanLimits: Equatable {
    static let unlimited = Int.max

    let maxHistoryItems: Int
    let maxPinnedItems: Int
    let maxSnippetItems: Int
    let maxSnippetFolders: Int

    var maxSnippets: Int {
        return maxSnippetItems
    }

    static let freeDefault = PlanLimits(
        maxHistoryItems: unlimited,
        maxPinnedItems: unlimited,
        maxSnippetItems: unlimited,
        maxSnippetFolders: unlimited
    )

    static let proDefault = PlanLimits(
        maxHistoryItems: unlimited,
        maxPinnedItems: unlimited,
        maxSnippetItems: unlimited,
        maxSnippetFolders: unlimited
    )
}

typealias EntitlementLimits = PlanLimits

struct LicenseMetadata: Equatable {
    let licenseKeyMasked: String?
    let deviceIdMasked: String?
    let activatedAt: Date?
    let lastVerifiedAt: Date?
    let status: String
    let licenseKind: LicenseKind?
    let issuedTo: String?

    init(licenseKeyMasked: String?,
         deviceIdMasked: String?,
         activatedAt: Date?,
         lastVerifiedAt: Date?,
         status: String,
         licenseKind: LicenseKind? = nil,
         issuedTo: String? = nil) {
        self.licenseKeyMasked = licenseKeyMasked
        self.deviceIdMasked = deviceIdMasked
        self.activatedAt = activatedAt
        self.lastVerifiedAt = lastVerifiedAt
        self.status = status
        self.licenseKind = licenseKind
        self.issuedTo = issuedTo
    }
}

struct Entitlement: Equatable {
    let plan: Plan
    let licenseState: LicenseState
    let features: Set<EntitlementFeature>
    let limits: PlanLimits
    let licenseMetadata: LicenseMetadata?
    let expiresAt: Date?
    let offlineGraceExpiresAt: Date?

    init(plan: Plan,
         licenseState: LicenseState,
         features: Set<EntitlementFeature>,
         limits: PlanLimits,
         licenseMetadata: LicenseMetadata? = nil,
         expiresAt: Date? = nil,
         offlineGraceExpiresAt: Date? = nil) {
        self.plan = plan
        self.licenseState = licenseState
        self.features = features
        self.limits = limits
        self.licenseMetadata = licenseMetadata
        self.expiresAt = expiresAt
        self.offlineGraceExpiresAt = offlineGraceExpiresAt
    }

    init(state: LicenseState,
         plan: EntitlementPlan,
         features: Set<EntitlementFeature>,
         limits: EntitlementLimits,
         licenseID: String?,
         issuedAt: Date?,
         expiresAt: Date?,
         lastVerifiedAt: Date?,
         offlineGraceExpiresAt: Date?) {
        let metadata = LicenseMetadata(
            licenseKeyMasked: licenseID,
            deviceIdMasked: nil,
            activatedAt: issuedAt,
            lastVerifiedAt: lastVerifiedAt,
            status: state.rawValue
        )
        self.init(
            plan: plan,
            licenseState: state,
            features: features,
            limits: limits,
            licenseMetadata: metadata,
            expiresAt: expiresAt,
            offlineGraceExpiresAt: offlineGraceExpiresAt
        )
    }

    var state: LicenseState {
        return licenseState
    }

    var licenseID: String? {
        return licenseMetadata?.licenseKeyMasked
    }

    var issuedAt: Date? {
        return licenseMetadata?.activatedAt
    }

    var lastVerifiedAt: Date? {
        return licenseMetadata?.lastVerifiedAt
    }

    var isProEntitled: Bool {
        switch licenseState {
        case .trial, .proActive:
            return plan == .pro
        case .ownerLifetime:
            return plan == .ownerLifetime
        case .free, .proExpired, .invalid, .offlineGrace, .locked:
            return false
        }
    }

    func canUse(_ feature: EntitlementFeature) -> Bool {
        if !feature.requiresCommercialService {
            return true
        }
        return isProEntitled && features.contains(feature)
    }

    static let freeDefault = Entitlement(
        plan: .free,
        licenseState: .free,
        features: [],
        limits: .freeDefault,
        licenseMetadata: LicenseMetadata(
            licenseKeyMasked: nil,
            deviceIdMasked: nil,
            activatedAt: nil,
            lastVerifiedAt: nil,
            status: LicenseState.free.rawValue
        )
    )

    static func proActive(metadata: LicenseMetadata? = nil) -> Entitlement {
        return Entitlement(
            plan: .pro,
            licenseState: .proActive,
            features: Set(EntitlementFeature.allCases),
            limits: .proDefault,
            licenseMetadata: metadata ?? LicenseMetadata(
                licenseKeyMasked: nil,
                deviceIdMasked: nil,
                activatedAt: nil,
                lastVerifiedAt: nil,
                status: LicenseState.proActive.rawValue
            )
        )
    }

    static func ownerLifetime(metadata: LicenseMetadata) -> Entitlement {
        return Entitlement(
            plan: .ownerLifetime,
            licenseState: .ownerLifetime,
            features: Set(EntitlementFeature.allCases),
            limits: .proDefault,
            licenseMetadata: metadata
        )
    }
}

typealias EntitlementSnapshot = Entitlement

final class EntitlementService {

    static let shared = EntitlementService()

    private let lock = NSRecursiveLock(name: "com.uniplanck.BoardMan.EntitlementService")
    private var snapshot: EntitlementSnapshot

    init(snapshot: EntitlementSnapshot = .freeDefault) {
        self.snapshot = snapshot
    }

    var currentSnapshot: EntitlementSnapshot {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    func canUse(_ feature: EntitlementFeature) -> Bool {
        return currentSnapshot.canUse(feature)
    }

    func replaceSnapshot(_ snapshot: EntitlementSnapshot) {
        lock.lock(); defer { lock.unlock() }
        self.snapshot = snapshot
    }

}

enum EntitlementGate {

    static func canUse(feature: EntitlementFeature,
                       service: EntitlementService = .shared) -> Bool {
        return service.canUse(feature)
    }

    static func canUse(_ feature: EntitlementFeature,
                       service: EntitlementService = .shared) -> Bool {
        return canUse(feature: feature, service: service)
    }

    static func limit(for limit: EntitlementLimit,
                      service: EntitlementService = .shared) -> Int? {
        // History, pins, snippets, and snippet groups are local client capabilities.
        // Commercial tokens may describe historical limits, but they must never gate local use.
        return nil
    }

    static func canAddHistoryItem(currentCount: Int,
                                  service: EntitlementService = .shared) -> Bool {
        return canAdd(currentCount: currentCount, limit: .historyItems, service: service)
    }

    static func historyRetentionLimit(service: EntitlementService = .shared) -> Int? {
        return limit(for: .historyItems, service: service)
    }

    static func canPinItem(currentPinnedCount: Int,
                           service: EntitlementService = .shared) -> Bool {
        return canAdd(currentCount: currentPinnedCount, limit: .pinnedItems, service: service)
    }

    static func canCreateSnippet(currentSnippetCount: Int,
                                 service: EntitlementService = .shared) -> Bool {
        return canAdd(currentCount: currentSnippetCount, limit: .snippetItems, service: service)
    }

    static func canCreateSnippetFolder(currentFolderCount: Int,
                                       service: EntitlementService = .shared) -> Bool {
        return canAdd(currentCount: currentFolderCount, limit: .snippetFolders, service: service)
    }

    static func requiresUpgrade(for feature: EntitlementFeature,
                                service: EntitlementService = .shared) -> Bool {
        return !canUse(feature: feature, service: service)
    }

    static func requiresUpgrade(for limit: EntitlementLimit,
                                currentCount: Int,
                                service: EntitlementService = .shared) -> Bool {
        return !canAdd(currentCount: currentCount, limit: limit, service: service)
    }

    static func currentSnapshot(service: EntitlementService = .shared) -> EntitlementSnapshot {
        return service.currentSnapshot
    }

    private static func canAdd(currentCount: Int,
                               limit: EntitlementLimit,
                               service: EntitlementService) -> Bool {
        guard let value = self.limit(for: limit, service: service) else {
            return true
        }
        return currentCount < value
    }

    private static func limitValue(for limit: EntitlementLimit,
                                   in entitlement: EntitlementSnapshot) -> Int? {
        let value: Int
        switch limit {
        case .historyItems:
            value = entitlement.limits.maxHistoryItems
        case .pinnedItems:
            value = entitlement.limits.maxPinnedItems
        case .snippetItems:
            value = entitlement.limits.maxSnippetItems
        case .snippetFolders:
            value = entitlement.limits.maxSnippetFolders
        }

        return value == PlanLimits.unlimited ? nil : value
    }
}
