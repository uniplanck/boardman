//
//  LicenseToken.swift
//
//  Clipy
//

import Foundation
import Security

enum LicenseKind: String, Equatable {
    case free
    case pro
    case ownerLifetime
}

struct SignedLicenseToken: Equatable {

    struct Header: Equatable {
        let algorithm: String
        let keyID: String?
        let type: String?
    }

    struct Payload: Equatable {
        let licenseID: String
        let licenseKind: LicenseKind
        let plan: EntitlementPlan
        let state: LicenseState
        let features: Set<EntitlementFeature>
        let limits: EntitlementLimits
        let issuedTo: String?
        let subject: String?
        let issuedAt: Date?
        let expiresAt: Date?
        let isLifetime: Bool
        let deviceID: String?
        let bundleID: String?
        let tokenVersion: Int?

        func entitlementSnapshot(lastVerifiedAt: Date,
                                 offlineGraceExpiresAt: Date? = nil) -> EntitlementSnapshot {
            let metadata = LicenseMetadata(
                licenseKeyMasked: licenseID,
                deviceIdMasked: deviceID.map(Self.masked),
                activatedAt: issuedAt,
                lastVerifiedAt: lastVerifiedAt,
                status: state.rawValue,
                licenseKind: licenseKind,
                issuedTo: issuedTo ?? subject
            )
            return EntitlementSnapshot(
                plan: plan,
                licenseState: state,
                features: features,
                limits: limits,
                licenseMetadata: metadata,
                expiresAt: expiresAt,
                offlineGraceExpiresAt: offlineGraceExpiresAt
            )
        }

        private static func masked(_ value: String) -> String {
            guard value.count > 4 else { return "****" }
            return "****" + value.suffix(4)
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
              let stateRawValue = payloadDTO.state,
              let licenseKindRawValue = payloadDTO.licenseKind ?? payloadDTO.plan else {
            throw ParseError.missingRequiredClaim
        }

        guard let licenseKind = LicenseKind(rawValue: licenseKindRawValue) else {
            throw ParseError.unknownPlan(licenseKindRawValue)
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
            licenseKind: licenseKind,
            plan: plan,
            state: state,
            features: Set((payloadDTO.features ?? []).compactMap(EntitlementFeature.init(rawValue:))),
            limits: payloadDTO.limits?.entitlementLimits ?? (plan.isUnlimited ? .proDefault : .freeDefault),
            issuedTo: payloadDTO.issuedTo,
            subject: payloadDTO.subject,
            issuedAt: payloadDTO.iat.flatMap(Date.init(licenseClaimValue:)),
            expiresAt: payloadDTO.exp.flatMap(Date.init(licenseClaimValue:)),
            isLifetime: payloadDTO.isLifetime ?? (state == .ownerLifetime),
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
    let licenseKind: String?
    let plan: String?
    let state: String?
    let features: [String]?
    let limits: LimitsDTO?
    let issuedTo: String?
    let subject: String?
    let iat: LicenseClaimDate?
    let exp: LicenseClaimDate?
    let isLifetime: Bool?
    let deviceID: String?
    let bundleID: String?
    let tokenVersion: Int?

    enum CodingKeys: String, CodingKey {
        case licenseID = "license_id"
        case licenseKind = "license_kind"
        case plan
        case state
        case features
        case limits
        case issuedTo = "issued_to"
        case subject = "sub"
        case iat
        case exp
        case isLifetime = "is_lifetime"
        case deviceID = "device_id"
        case bundleID = "bundle_id"
        case tokenVersion = "token_version"
    }
}

private struct LimitsDTO: Decodable {
    let maxHistoryItems: Int?
    let maxPinnedItems: Int?
    let maxSnippetItems: Int?
    let maxSnippetFolders: Int?

    enum CodingKeys: String, CodingKey {
        case maxHistoryItems = "max_history_items"
        case maxPinnedItems = "max_pinned_items"
        case maxSnippetItems = "max_snippet_items"
        case maxSnippetFolders = "max_snippet_folders"
    }

    var entitlementLimits: EntitlementLimits {
        return EntitlementLimits(
            maxHistoryItems: maxHistoryItems ?? EntitlementLimits.freeDefault.maxHistoryItems,
            maxPinnedItems: maxPinnedItems ?? EntitlementLimits.freeDefault.maxPinnedItems,
            maxSnippetItems: maxSnippetItems ?? EntitlementLimits.freeDefault.maxSnippetItems,
            maxSnippetFolders: maxSnippetFolders ?? EntitlementLimits.freeDefault.maxSnippetFolders
        )
    }
}

private extension EntitlementPlan {
    var isUnlimited: Bool {
        return self == .pro || self == .ownerLifetime
    }
}

protocol LicenseTokenStoring {
    func loadSignedLicenseToken() -> String?
    func storeVerifiedSignedLicenseToken(_ token: SignedLicenseToken) throws
}

enum LicenseTokenStorageError: Error, Equatable {
    case encodingFailed
    case keychain(OSStatus)
}

final class FutureKeychainLicenseTokenStore: LicenseTokenStoring {
    private enum Keychain {
        static let service = "com.uniplanck.BoardMan.LicenseToken"
        static let account = "signedLicenseToken"
    }

    func loadSignedLicenseToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func storeVerifiedSignedLicenseToken(_ token: SignedLicenseToken) throws {
        guard let data = token.rawValue.data(using: .utf8) else {
            throw LicenseTokenStorageError.encodingFailed
        }

        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw LicenseTokenStorageError.keychain(updateStatus)
        }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw LicenseTokenStorageError.keychain(addStatus)
        }
    }

    private func baseQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keychain.service,
            kSecAttrAccount as String: Keychain.account
        ]
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
