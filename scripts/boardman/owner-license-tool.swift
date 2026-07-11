#!/usr/bin/env swift

import CryptoKit
import Foundation
import Security

private enum ToolError: Error, CustomStringConvertible {
    case invalidCommand
    case keychain(OSStatus)
    case invalidPrivateKey
    case missingIssuerKey
    case invalidTrustedApplication
    case invalidAccessControl
    case encoding

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
        case .invalidTrustedApplication:
            return "Could not create the Board-Man trusted application entry."
        case .invalidAccessControl:
            return "Could not create Keychain access control for Board-Man."
        case .encoding:
            return "Could not encode the owner license token."
        }
    }
}

private enum KeychainNames {
    static let issuerService = "com.uniplanck.BoardMan.OwnerIssuer"
    static let issuerAccount = "p256-private-key-v1"
    static let deviceService = "com.uniplanck.BoardMan.LocalDeviceIdentity"
    static let deviceAccount = "localDeviceId"
    static let tokenService = "com.uniplanck.BoardMan.LicenseToken"
    static let tokenAccount = "signedLicenseToken"
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

private func upsertGenericPassword(service: String,
                                   account: String,
                                   data: Data,
                                   access: SecAccess? = nil) throws {
    let baseQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]
    let updateStatus = SecItemUpdate(
        baseQuery as CFDictionary,
        [kSecValueData as String: data] as CFDictionary
    )
    if updateStatus == errSecSuccess {
        return
    }
    guard updateStatus == errSecItemNotFound else {
        throw ToolError.keychain(updateStatus)
    }

    var addQuery = baseQuery
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    if let access {
        addQuery[kSecAttrAccess as String] = access
    }
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
        throw ToolError.keychain(addStatus)
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

private func loadOrCreateDeviceID() throws -> String {
    if let data = try readGenericPassword(service: KeychainNames.deviceService,
                                          account: KeychainNames.deviceAccount),
       let value = String(data: data, encoding: .utf8),
       UUID(uuidString: value) != nil {
        return value
    }

    let value = UUID().uuidString
    guard let data = value.data(using: .utf8) else { throw ToolError.encoding }
    try upsertGenericPassword(service: KeychainNames.deviceService,
                              account: KeychainNames.deviceAccount,
                              data: data)
    return value
}

private func boardManAccess(appPath: String) throws -> SecAccess {
    var trustedApplication: SecTrustedApplication?
    let trustedStatus = SecTrustedApplicationCreateFromPath(appPath, &trustedApplication)
    guard trustedStatus == errSecSuccess, let trustedApplication else {
        throw ToolError.invalidTrustedApplication
    }

    var access: SecAccess?
    let accessStatus = SecAccessCreate("Board-Man Owner Lifetime License" as CFString,
                                      [trustedApplication] as CFArray,
                                      &access)
    guard accessStatus == errSecSuccess, let access else {
        throw ToolError.invalidAccessControl
    }
    return access
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
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
        let privateKey = try loadPrivateKey()
        let appPath = argumentValue("--app", default: "/Applications/Board-Man.app")
        let issuedTo = argumentValue("--issued-to", default: "Board-Man Owner")
        let subject = argumentValue("--subject", default: "planckworld")
        let deviceID = try loadOrCreateDeviceID()
        let token = try makeOwnerToken(privateKey: privateKey,
                                       deviceID: deviceID,
                                       issuedTo: issuedTo,
                                       subject: subject)
        guard let tokenData = token.data(using: .utf8) else { throw ToolError.encoding }
        let access = try boardManAccess(appPath: appPath)
        try upsertGenericPassword(service: KeychainNames.tokenService,
                                  account: KeychainNames.tokenAccount,
                                  data: tokenData,
                                  access: access)
        print("Owner Lifetime token installed in Keychain for the canonical Board-Man app.")

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
