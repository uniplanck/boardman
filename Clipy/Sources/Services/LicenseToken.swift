//
//  LicenseToken.swift
//
//  Clipy
//

import Foundation

struct SignedLicenseToken: Equatable {

    struct Header: Equatable {
        let algorithm: String
        let keyID: String?
        let type: String?
    }

    struct Payload: Equatable {
        let licenseID: String
        let plan: EntitlementPlan
        let state: LicenseState
        let features: Set<EntitlementFeature>
        let limits: EntitlementLimits
        let issuedAt: Date?
        let expiresAt: Date?
        let deviceID: String?
        let bundleID: String?
        let tokenVersion: Int?

        func entitlementSnapshot(lastVerifiedAt: Date,
                                 offlineGraceExpiresAt: Date? = nil) -> EntitlementSnapshot {
            return EntitlementSnapshot(
                state: state,
                plan: plan,
                features: features,
                limits: limits,
                licenseID: licenseID,
                issuedAt: issuedAt,
                expiresAt: expiresAt,
                lastVerifiedAt: lastVerifiedAt,
                offlineGraceExpiresAt: offlineGraceExpiresAt
            )
        }
    }

    enum ParseError: Error, Equatable {
        case invalidCompactToken
        case invalidBase64URLSection
        case invalidJSONPayload
        case missingRequiredClaim
        case unknownPlan(String)
        case unknownState(String)
    }

    let rawValue: String
    let headerData: Data
    let payloadData: Data
    let signatureData: Data
    let header: Header
    let payload: Payload

    init(rawValue: String) throws {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            throw ParseError.invalidCompactToken
        }

        guard let headerData = Data(base64URLEncoded: String(parts[0])),
              let payloadData = Data(base64URLEncoded: String(parts[1])),
              let signatureData = Data(base64URLEncoded: String(parts[2])) else {
            throw ParseError.invalidBase64URLSection
        }

        let decoder = JSONDecoder()
        guard let headerDTO = try? decoder.decode(HeaderDTO.self, from: headerData),
              let payloadDTO = try? decoder.decode(PayloadDTO.self, from: payloadData) else {
            throw ParseError.invalidJSONPayload
        }

        guard let algorithm = headerDTO.alg,
              let licenseID = payloadDTO.licenseID,
              let planRawValue = payloadDTO.plan,
              let stateRawValue = payloadDTO.state else {
            throw ParseError.missingRequiredClaim
        }

        guard let plan = EntitlementPlan(rawValue: planRawValue) else {
            throw ParseError.unknownPlan(planRawValue)
        }

        guard let state = LicenseState(rawValue: stateRawValue) else {
            throw ParseError.unknownState(stateRawValue)
        }

        self.rawValue = rawValue
        self.headerData = headerData
        self.payloadData = payloadData
        self.signatureData = signatureData
        self.header = Header(algorithm: algorithm, keyID: headerDTO.kid, type: headerDTO.typ)
        self.payload = Payload(
            licenseID: licenseID,
            plan: plan,
            state: state,
            features: Set((payloadDTO.features ?? []).compactMap(EntitlementFeature.init(rawValue:))),
            limits: payloadDTO.limits?.entitlementLimits ?? (plan == .pro ? .proDefault : .freeDefault),
            issuedAt: payloadDTO.iat.flatMap(Date.init(licenseClaimValue:)),
            expiresAt: payloadDTO.exp.flatMap(Date.init(licenseClaimValue:)),
            deviceID: payloadDTO.deviceID,
            bundleID: payloadDTO.bundleID,
            tokenVersion: payloadDTO.tokenVersion
        )
    }
}

private struct HeaderDTO: Decodable {
    let alg: String?
    let kid: String?
    let typ: String?
}

private struct PayloadDTO: Decodable {
    let licenseID: String?
    let plan: String?
    let state: String?
    let features: [String]?
    let limits: LimitsDTO?
    let iat: LicenseClaimDate?
    let exp: LicenseClaimDate?
    let deviceID: String?
    let bundleID: String?
    let tokenVersion: Int?

    enum CodingKeys: String, CodingKey {
        case licenseID = "license_id"
        case plan
        case state
        case features
        case limits
        case iat
        case exp
        case deviceID = "device_id"
        case bundleID = "bundle_id"
        case tokenVersion = "token_version"
    }
}

private struct LimitsDTO: Decodable {
    let maxHistoryItems: Int?
    let maxSnippets: Int?
    let maxSavedSearches: Int?
    let maxThemePresets: Int?

    enum CodingKeys: String, CodingKey {
        case maxHistoryItems = "max_history_items"
        case maxSnippets = "max_snippets"
        case maxSavedSearches = "max_saved_searches"
        case maxThemePresets = "max_theme_presets"
    }

    var entitlementLimits: EntitlementLimits {
        return EntitlementLimits(
            maxHistoryItems: maxHistoryItems ?? EntitlementLimits.freeDefault.maxHistoryItems,
            maxSnippets: maxSnippets ?? EntitlementLimits.freeDefault.maxSnippets,
            maxSavedSearches: maxSavedSearches ?? EntitlementLimits.freeDefault.maxSavedSearches,
            maxThemePresets: maxThemePresets ?? EntitlementLimits.freeDefault.maxThemePresets
        )
    }
}

private enum LicenseClaimDate: Decodable, Equatable {
    case seconds(TimeInterval)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(TimeInterval.self) {
            self = .seconds(seconds)
            return
        }

        self = .string(try container.decode(String.self))
    }
}

private extension Date {
    init?(licenseClaimValue value: LicenseClaimDate) {
        switch value {
        case .seconds(let seconds):
            self.init(timeIntervalSince1970: seconds)
        case .string(let string):
            guard let date = ISO8601DateFormatter().date(from: string) else {
                return nil
            }
            self = date
        }
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let paddingLength = (4 - base64.count % 4) % 4
        if paddingLength > 0 {
            base64 += String(repeating: "=", count: paddingLength)
        }

        self.init(base64Encoded: base64)
    }
}
