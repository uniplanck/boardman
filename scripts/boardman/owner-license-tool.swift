#!/usr/bin/env swift

import CryptoKit
import Foundation
import Security

private enum ToolError: Error, CustomStringConvertible {
    case invalidCommand
    case keychain(OSStatus)
    case invalidPrivateKey
    case missingIssuerKey
    case issuerKeyMismatch
    case invalidAppPath
    case encoding
    case fileSystem

    var description: String {
        switch self {
        case .invalidCommand:
            return "Usage: owner-license-tool.swift bootstrap-key | install [--app PATH] [--issued-to NAME] [--subject SUBJECT]"
        case .keychain(let status):
            return "Keychain operation failed (status: \(status))."
        case .invalidPrivateKey:
            return "The owner issuer private key in Keychain is invalid."
        case .missingIssuerKey:
            return "The owner issuer private key is not installed on this Mac."
        case .issuerKeyMismatch:
            return "The owner issuer key does not match the public key bundled with Board-Man."
        case .invalidAppPath:
            return "The canonical Board-Man app was not found."
        case .encoding:
            return "Could not encode the owner license token."
        case .fileSystem:
            return "Could not write Board-Man local license state."
        }
    }
}

private enum KeychainNames {
    static let issuerService = "com.uniplanck.BoardMan.OwnerIssuer"
    static let issuerAccount = "p256-private-key-v1"
    static let legacyDeviceService = "com.uniplanck.BoardMan.LocalDeviceIdentity"
    static let legacyDeviceAccount = "localDeviceId"
    static let legacyTokenService = "com.uniplanck.BoardMan.LicenseToken"
    static let legacyTokenAccount = "signedLicenseToken"
}

private enum LocalState {
    static let ownerPublicKeyBase64 = "BGGgQPFnOgKAk821OQGix9fQLDPrqJSCEP98KvCBXqs4YZ6Vfw6QmscEpbZROEjiAavFvNNc1V/fCw1cYa62Cuc="

    static var directoryURL: URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL.appendingPathComponent("com.uniplanck.BoardMan", isDirectory: true)
    }

    static var tokenURL: URL {
        return directoryURL.appendingPathComponent("owner-license.jwt", isDirectory: false)
    }

    static var deviceIDURL: URL {
        return directoryURL.appendingPathComponent("device-id", isDirectory: false)
    }
}

private func readGenericPassword(service: String, account: String) throws -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
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

private func upsertGenericPassword(service: String, account: String, data: Data) throws {
    let baseQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]
    let updateStatus = SecItemUpdate(
        baseQuery as CFDictionary,
        [kSecValueData as String: data] as CFDictionary
    )
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
        throw ToolError.keychain(updateStatus)
    }

    var addQuery = baseQuery
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
        throw ToolError.keychain(addStatus)
    }
}

private func writePrivateData(_ data: Data, to fileURL: URL) throws {
    let fileManager = FileManager.default
    do {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    } catch {
        throw ToolError.fileSystem
    }
}

private func loadPrivateKey() throws -> P256.Signing.PrivateKey {
    guard let data = try readGenericPassword(service: KeychainNames.issuerService,
                                             account: KeychainNames.issuerAccount) else {
        throw ToolError.missingIssuerKey
    }
    guard let key = try? P256.Signing.PrivateKey(rawRepresentation: data) else {
        throw ToolError.invalidPrivateKey
    }
    return key
}

private func loadOrCreatePrivateKey() throws -> P256.Signing.PrivateKey {
    if let key = try? loadPrivateKey() {
        return key
    }
    let key = P256.Signing.PrivateKey()
    try upsertGenericPassword(service: KeychainNames.issuerService,
                              account: KeychainNames.issuerAccount,
                              data: key.rawRepresentation)
    return key
}

private func readValidDeviceID(from fileURL: URL) -> String? {
    guard let data = try? Data(contentsOf: fileURL),
          let value = String(data: data, encoding: .utf8),
          UUID(uuidString: value) != nil else {
        return nil
    }
    return value
}

private func loadOrCreateDeviceID() throws -> String {
    if let existing = readValidDeviceID(from: LocalState.deviceIDURL) {
        return existing
    }

    if let legacyData = try readGenericPassword(service: KeychainNames.legacyDeviceService,
                                                account: KeychainNames.legacyDeviceAccount),
       let legacyValue = String(data: legacyData, encoding: .utf8),
       UUID(uuidString: legacyValue) != nil {
        try writePrivateData(legacyData, to: LocalState.deviceIDURL)
        print("Legacy device identity migrated to Application Support.")
        return legacyValue
    }

    let value = UUID().uuidString
    guard let data = value.data(using: .utf8) else { throw ToolError.encoding }
    try writePrivateData(data, to: LocalState.deviceIDURL)
    print("New local device identity created in Application Support.")
    return value
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func decodeBase64URL(_ value: String) -> Data? {
    var base64 = value
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder != 0 {
        base64.append(String(repeating: "=", count: 4 - remainder))
    }
    return Data(base64Encoded: base64)
}

private func ownerPublicKey() throws -> P256.Signing.PublicKey {
    guard let data = Data(base64Encoded: LocalState.ownerPublicKeyBase64),
          let key = try? P256.Signing.PublicKey(x963Representation: data) else {
        throw ToolError.issuerKeyMismatch
    }
    return key
}

private func isReusableOwnerToken(_ data: Data,
                                  publicKey: P256.Signing.PublicKey,
                                  deviceID: String) -> Bool {
    guard let token = String(data: data, encoding: .utf8) else { return false }
    let sections = token.split(separator: ".", omittingEmptySubsequences: false)
    guard sections.count == 3 else { return false }

    let signingInput = "\(sections[0]).\(sections[1])"
    guard let signingData = signingInput.data(using: .utf8),
          let signatureData = decodeBase64URL(String(sections[2])),
          let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData),
          publicKey.isValidSignature(signature, for: signingData),
          let payloadData = decodeBase64URL(String(sections[1])),
          let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
        return false
    }

    return payload["plan"] as? String == "ownerLifetime"
        && payload["state"] as? String == "ownerLifetime"
        && payload["is_lifetime"] as? Bool == true
        && payload["device_id"] as? String == deviceID
        && payload["bundle_id"] as? String == "com.uniplanck.BoardMan"
}

private func reusableTokenData(deviceID: String,
                               publicKey: P256.Signing.PublicKey) throws -> Data? {
    if let currentData = try? Data(contentsOf: LocalState.tokenURL),
       isReusableOwnerToken(currentData, publicKey: publicKey, deviceID: deviceID) {
        print("Existing verified Owner Lifetime token preserved.")
        return currentData
    }

    if let legacyData = try readGenericPassword(service: KeychainNames.legacyTokenService,
                                                account: KeychainNames.legacyTokenAccount),
       isReusableOwnerToken(legacyData, publicKey: publicKey, deviceID: deviceID) {
        print("Legacy Owner Lifetime token migrated to Application Support.")
        return legacyData
    }

    return nil
}

private func jsonData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}

private func argumentValue(_ name: String, default defaultValue: String) -> String {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1) else {
        return defaultValue
    }
    return CommandLine.arguments[index + 1]
}

private func makeOwnerToken(privateKey: P256.Signing.PrivateKey,
                            deviceID: String,
                            issuedTo: String,
                            subject: String) throws -> String {
    let header: [String: Any] = [
        "alg": "ES256",
        "kid": "owner-local-v1",
        "typ": "JWT"
    ]
    let payload: [String: Any] = [
        "license_id": "OWNER-\(UUID().uuidString)",
        "license_kind": "ownerLifetime",
        "plan": "ownerLifetime",
        "state": "ownerLifetime",
        "features": [
            "unlimitedHistory",
            "unlimitedSnippets",
            "advancedAppearance",
            "exportImport",
            "pasteAnalytics",
            "futureSync"
        ],
        "issued_to": issuedTo,
        "sub": subject,
        "iat": Int(Date().timeIntervalSince1970),
        "is_lifetime": true,
        "device_id": deviceID,
        "bundle_id": "com.uniplanck.BoardMan",
        "token_version": 1
    ]

    let headerSection = base64URL(try jsonData(header))
    let payloadSection = base64URL(try jsonData(payload))
    let signingInput = "\(headerSection).\(payloadSection)"
    guard let signingData = signingInput.data(using: .utf8) else { throw ToolError.encoding }
    let signature = try privateKey.signature(for: signingData)
    return "\(signingInput).\(base64URL(signature.rawRepresentation))"
}

private func run() throws {
    guard CommandLine.arguments.count >= 2 else { throw ToolError.invalidCommand }
    let command = CommandLine.arguments[1]

    switch command {
    case "bootstrap-key":
        let privateKey = try loadOrCreatePrivateKey()
        print(privateKey.publicKey.x963Representation.base64EncodedString())

    case "install":
        let appPath = argumentValue("--app", default: "/Applications/Board-Man.app")
        guard FileManager.default.fileExists(atPath: appPath) else {
            throw ToolError.invalidAppPath
        }

        let issuedTo = argumentValue("--issued-to", default: "Board-Man Owner")
        let subject = argumentValue("--subject", default: "planckworld")
        let deviceID = try loadOrCreateDeviceID()
        let publicKey = try ownerPublicKey()

        let tokenData: Data
        if let reusableData = try reusableTokenData(deviceID: deviceID, publicKey: publicKey) {
            tokenData = reusableData
        } else {
            let privateKey = try loadPrivateKey()
            guard privateKey.publicKey.x963Representation.base64EncodedString() == LocalState.ownerPublicKeyBase64 else {
                throw ToolError.issuerKeyMismatch
            }
            let token = try makeOwnerToken(privateKey: privateKey,
                                           deviceID: deviceID,
                                           issuedTo: issuedTo,
                                           subject: subject)
            guard let generatedData = token.data(using: .utf8) else {
                throw ToolError.encoding
            }
            tokenData = generatedData
            print("New Owner Lifetime token generated.")
        }

        try writePrivateData(tokenData, to: LocalState.tokenURL)
        print("Owner Lifetime local state installed without application Keychain access.")

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
