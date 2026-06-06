//
//  LocalDeviceIdentityService.swift
//
//  Clipy
//

import Foundation
import Security

final class LocalDeviceIdentityService {

    static let shared = LocalDeviceIdentityService()

    private enum Keychain {
        static let service = "com.uniplanck.BoardMan.LocalDeviceIdentity"
        static let account = "localDeviceId"
    }

    private let lock = NSRecursiveLock(name: "com.uniplanck.BoardMan.LocalDeviceIdentityService")
    private var cachedDeviceID: String?

    func deviceID() -> String {
        lock.lock(); defer { lock.unlock() }

        if let cachedDeviceID = cachedDeviceID {
            return cachedDeviceID
        }

        if let existingDeviceID = readDeviceIDFromKeychain() {
            cachedDeviceID = existingDeviceID
            return existingDeviceID
        }

        let newDeviceID = UUID().uuidString
        if storeDeviceIDInKeychain(newDeviceID) {
            cachedDeviceID = newDeviceID
            return newDeviceID
        }

        cachedDeviceID = newDeviceID
        return newDeviceID
    }

    private func readDeviceIDFromKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              UUID(uuidString: value) != nil else {
            return nil
        }

        return value
    }

    private func storeDeviceIDInKeychain(_ deviceID: String) -> Bool {
        guard let data = deviceID.data(using: .utf8) else {
            return false
        }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }

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
}
