//
//  LicenseActivationClient.swift
//
//  Clipy
//

import Foundation
import CryptoKit
import Security

struct LicenseActivationRequest: Equatable {
    let licenseKey: String
    let localDeviceID: String?

    init(licenseKey: String, localDeviceID: String? = nil) {
        self.licenseKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.localDeviceID = localDeviceID
    }
}

enum LicenseActivationStatus: String, Equatable {
    case activated
    case notConfigured
    case invalidInput
    case networkUnavailable
    case unsupported
}

struct LicenseActivationResponse: Equatable {
    let status: LicenseActivationStatus
    let message: String
}

protocol LicenseActivationClient {
    func activate(_ request: LicenseActivationRequest) -> LicenseActivationResponse
}

final class StubLicenseActivationClient: LicenseActivationClient {

    func activate(_ request: LicenseActivationRequest) -> LicenseActivationResponse {
        guard !request.licenseKey.isEmpty else {
            return LicenseActivationResponse(
                status: .invalidInput,
                message: "Enter a license key to test the local activation boundary."
            )
        }

        if LocalFounderLicenseStore.shared.activateIfFounderCode(request.licenseKey) {
            EntitlementService.shared.activateFounderLifetime()
            return LicenseActivationResponse(
                status: .activated,
                message: "Founder Lifetime activated locally."
            )
        }

        return LicenseActivationResponse(
            status: .unsupported,
            message: "Unknown code. Production license activation still requires a signed token backend."
        )
    }
}

final class LocalFounderLicenseStore {

    static let shared = LocalFounderLicenseStore()

    private enum Keychain {
        static let service = "com.uniplanck.BoardMan.FounderLicense"
        static let account = "founderLifetimeActivation"
    }

    private static let founderCodeSHA256 = "65ad70f678859f024d41b9594298d6f25da87ce06b80318f329052d7648a56dd"

    func entitlementSnapshot() -> EntitlementSnapshot? {
        guard let activatedAt = activationDate() else { return nil }
        return .founderLifetime(activatedAt: activatedAt)
    }

    func activateIfFounderCode(_ code: String) -> Bool {
        guard sha256Hex(code.trimmingCharacters(in: .whitespacesAndNewlines)) == Self.founderCodeSHA256 else {
            return false
        }
        return storeActivation(Date())
    }

    private func activationDate() -> Date? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              let seconds = TimeInterval(value) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private func storeActivation(_ date: Date) -> Bool {
        let value = String(date.timeIntervalSince1970)
        guard let data = value.data(using: .utf8) else { return false }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        if addStatus == errSecDuplicateItem {
            let attributes = [kSecValueData as String: data]
            return SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }
        return false
    }

    private func baseQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keychain.service,
            kSecAttrAccount as String: Keychain.account
        ]
    }

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
