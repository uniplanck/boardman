//
//  Entitlement.swift
//
//  Clipy
//

import Foundation

enum LicenseState: String, Equatable {
    case free
    case trial
    case proActive
    case proExpired
    case invalid
    case offlineGrace
    case locked
}

enum EntitlementPlan: String, Equatable {
    case free
    case trial
    case pro
    case founder
}

enum EntitlementFeature: String, CaseIterable, Hashable {
    case clipboardHistory
    case snippets
    case standardSearch
    case pasteCountVisibility
    case coreAppearance
    case essentialHotkeys
    case appearanceAdvanced
    case extendedHotkeys
    case exportImport
    case unlimitedSnippets
    case pasteAnalytics
}

struct EntitlementLimits: Equatable {
    let maxHistoryItems: Int
    let maxPinnedItems: Int
    let maxSnippets: Int
    let maxSavedSearches: Int
    let maxThemePresets: Int

    static let freeDefault = EntitlementLimits(
        maxHistoryItems: 100,
        maxPinnedItems: 3,
        maxSnippets: 5,
        maxSavedSearches: 0,
        maxThemePresets: 1
    )

    static let proDefault = EntitlementLimits(
        maxHistoryItems: Int.max,
        maxPinnedItems: Int.max,
        maxSnippets: Int.max,
        maxSavedSearches: 50,
        maxThemePresets: 20
    )
}

struct EntitlementSnapshot: Equatable {
    let state: LicenseState
    let plan: EntitlementPlan
    let features: Set<EntitlementFeature>
    let limits: EntitlementLimits
    let licenseID: String?
    let issuedAt: Date?
    let expiresAt: Date?
    let lastVerifiedAt: Date?
    let offlineGraceExpiresAt: Date?

    var isProEntitled: Bool {
        switch state {
        case .trial, .proActive, .offlineGrace:
            return plan == .trial || plan == .pro || plan == .founder
        case .free, .proExpired, .invalid, .locked:
            return false
        }
    }

    func canUse(_ feature: EntitlementFeature) -> Bool {
        return features.contains(feature)
    }

    static let freeDefault = EntitlementSnapshot(
        state: .free,
        plan: .free,
        features: [
            .clipboardHistory,
            .snippets,
            .standardSearch,
            .pasteCountVisibility,
            .coreAppearance,
            .essentialHotkeys
        ],
        limits: .freeDefault,
        licenseID: nil,
        issuedAt: nil,
        expiresAt: nil,
        lastVerifiedAt: nil,
        offlineGraceExpiresAt: nil
    )

#if DEBUG
    static let debugPro = EntitlementSnapshot(
        state: .proActive,
        plan: .pro,
        features: Set(EntitlementFeature.allCases),
        limits: .proDefault,
        licenseID: "debug-local-pro",
        issuedAt: Date(),
        expiresAt: nil,
        lastVerifiedAt: Date(),
        offlineGraceExpiresAt: nil
    )
#endif

    static func founderLifetime(activatedAt: Date = Date()) -> EntitlementSnapshot {
        return EntitlementSnapshot(
            state: .proActive,
            plan: .founder,
            features: Set(EntitlementFeature.allCases),
            limits: .proDefault,
            licenseID: "internal-founder-lifetime",
            issuedAt: activatedAt,
            expiresAt: nil,
            lastVerifiedAt: activatedAt,
            offlineGraceExpiresAt: nil
        )
    }
}

final class EntitlementService {

    static let shared = EntitlementService()

    private let lock = NSRecursiveLock(name: "com.uniplanck.BoardMan.EntitlementService")
    private var snapshot: EntitlementSnapshot

#if DEBUG
    var debugOverrideSnapshot: EntitlementSnapshot? {
        get {
            lock.lock(); defer { lock.unlock() }
            return _debugOverrideSnapshot
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _debugOverrideSnapshot = newValue
        }
    }

    private var _debugOverrideSnapshot: EntitlementSnapshot?
#endif

    init(snapshot: EntitlementSnapshot = LocalFounderLicenseStore.shared.entitlementSnapshot() ?? .freeDefault) {
        self.snapshot = snapshot
    }

    var currentSnapshot: EntitlementSnapshot {
        lock.lock(); defer { lock.unlock() }
#if DEBUG
        if let debugOverrideSnapshot = _debugOverrideSnapshot {
            return debugOverrideSnapshot
        }
#endif
        return snapshot
    }

    func canUse(_ feature: EntitlementFeature) -> Bool {
        return currentSnapshot.canUse(feature)
    }

    func activateFounderLifetime(activatedAt: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        snapshot = .founderLifetime(activatedAt: activatedAt)
    }
}

enum EntitlementGate {

    static func canUse(_ feature: EntitlementFeature,
                       service: EntitlementService = .shared) -> Bool {
        return service.canUse(feature)
    }

    static func currentSnapshot(service: EntitlementService = .shared) -> EntitlementSnapshot {
        return service.currentSnapshot
    }
}
