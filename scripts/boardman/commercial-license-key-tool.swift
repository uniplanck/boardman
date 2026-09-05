#!/usr/bin/env swift

import CryptoKit
import Foundation
import Security

private enum KeychainNames {
    static let service = "com.uniplanck.BoardMan.CommercialIssuer"
    static let account = "p256-private-key-v1"
}

private enum ToolError: Error, CustomStringConvertible {
    case invalidCommand
    case keychain(OSStatus)
    case invalidPrivateKey

    var description: String {
        switch self {
        case .invalidCommand:
            return "Usage: commercial-license-key-tool.swift bootstrap-key | private-jwk"
        case .keychain(let status):
            return "Keychain operation failed (status: \(status))."
        case .invalidPrivateKey:
            return "The commercial issuer private key in Keychain is invalid."
        }
    }
}

private func readKeyData() throws -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: KeychainNames.service,
        kSecAttrAccount as String: KeychainNames.account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
        throw ToolError.keychain(status)
    }
    return data
}

private func upsertKeyData(_ data: Data) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: KeychainNames.service,
        kSecAttrAccount as String: KeychainNames.account
    ]
    let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else { throw ToolError.keychain(updateStatus) }

    var addQuery = query
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else { throw ToolError.keychain(addStatus) }
}

private func loadOrCreateKey() throws -> P256.Signing.PrivateKey {
    if let data = try readKeyData() {
        guard let key = try? P256.Signing.PrivateKey(rawRepresentation: data) else {
            throw ToolError.invalidPrivateKey
        }
        return key
    }
    let key = P256.Signing.PrivateKey()
    try upsertKeyData(key.rawRepresentation)
    return key
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func privateJWK(_ key: P256.Signing.PrivateKey) throws -> String {
    let publicBytes = key.publicKey.x963Representation
    guard publicBytes.count == 65, publicBytes.first == 0x04 else {
        throw ToolError.invalidPrivateKey
    }
    let x = publicBytes.subdata(in: 1..<33)
    let y = publicBytes.subdata(in: 33..<65)
    let object: [String: String] = [
        "kty": "EC",
        "crv": "P-256",
        "x": base64URL(x),
        "y": base64URL(y),
        "d": base64URL(key.rawRepresentation)
    ]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    guard let value = String(data: data, encoding: .utf8) else { throw ToolError.invalidPrivateKey }
    return value
}

private func run() throws {
    guard CommandLine.arguments.count == 2 else { throw ToolError.invalidCommand }
    let key = try loadOrCreateKey()
    switch CommandLine.arguments[1] {
    case "bootstrap-key":
        print(key.publicKey.x963Representation.base64EncodedString())
    case "private-jwk":
        print(try privateJWK(key))
    default:
        throw ToolError.invalidCommand
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
    exit(1)
}
