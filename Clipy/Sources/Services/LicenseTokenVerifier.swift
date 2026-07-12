//
//  LicenseTokenVerifier.swift
//
//  Clipy
//

import CryptoKit
import Foundation

struct SignedLicenseTokenVerificationContext: Equatable {
    let deviceID: String?
    let bundleID: String?
    let verificationDate: Date

    init(deviceID: String? = nil,
         bundleID: String? = Bundle.main.bundleIdentifier,
         verificationDate: Date = Date()) {
        self.deviceID = deviceID
        self.bundleID = bundleID
        self.verificationDate = verificationDate
    }
}

enum SignedLicenseTokenVerificationFailure: String, Equatable {
    case malformedToken
    case signatureInvalid
    case tokenExpired
    case deviceMismatch
    case bundleMismatch
    case unsupportedAlgorithm
    case claimMismatch
}

enum SignedLicenseTokenVerificationResult: Equatable {
    case verified(SignedLicenseToken.Payload)
    case invalid(SignedLicenseTokenVerificationFailure)
    case unsupported(String)
    case notConfigured

    var entitlementSnapshot: EntitlementSnapshot? {
        guard case .verified(let payload) = self else {
            return nil
        }

        return payload.entitlementSnapshot(lastVerifiedAt: Date())
    }
}

protocol SignedLicenseTokenVerifying {
    func verify(_ token: String,
                context: SignedLicenseTokenVerificationContext) -> SignedLicenseTokenVerificationResult
}

private enum BoardManLicenseVerificationConfiguration {
    static let ownerPublicKeyBase64 = "BGGgQPFnOgKAk821OQGix9fQLDPrqJSCEP98KvCBXqs4YZ6Vfw6QmscEpbZROEjiAavFvNNc1V/fCw1cYa62Cuc="
}

final class P256SignedLicenseTokenVerifier: SignedLicenseTokenVerifying {
    private let publicKey: P256.Signing.PublicKey?

    init(publicKeyBase64: String = BoardManLicenseVerificationConfiguration.ownerPublicKeyBase64) {
        guard let data = Data(base64Encoded: publicKeyBase64) else {
            publicKey = nil
            return
        }
        publicKey = try? P256.Signing.PublicKey(x963Representation: data)
    }

    func verify(_ token: String,
                context: SignedLicenseTokenVerificationContext = SignedLicenseTokenVerificationContext()) -> SignedLicenseTokenVerificationResult {
        guard let publicKey else { return .notConfigured }
        guard let parsedToken = try? SignedLicenseToken(rawValue: token) else {
            return .invalid(.malformedToken)
        }
        guard parsedToken.header.algorithm == "ES256" else {
            return .invalid(.unsupportedAlgorithm)
        }

        let sections = token.split(separator: ".", omittingEmptySubsequences: false)
        guard sections.count == 3,
              let signingInput = "\(sections[0]).\(sections[1])".data(using: .utf8),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: parsedToken.signatureData),
              publicKey.isValidSignature(signature, for: signingInput) else {
            return .invalid(.signatureInvalid)
        }

        let payload = parsedToken.payload
        if payload.expiresAt.map({ $0 <= context.verificationDate }) == true {
            return .invalid(.tokenExpired)
        }
        if let expectedDeviceID = context.deviceID, payload.deviceID != expectedDeviceID {
            return .invalid(.deviceMismatch)
        }
        if let expectedBundleID = context.bundleID, payload.bundleID != expectedBundleID {
            return .invalid(.bundleMismatch)
        }
        guard payload.licenseKind == .ownerLifetime,
              payload.plan == .ownerLifetime,
              payload.state == .ownerLifetime,
              payload.isLifetime,
              payload.expiresAt == nil,
              payload.tokenVersion == 1 else {
            return .invalid(.claimMismatch)
        }

        return .verified(payload)
    }
}

final class LicenseBootstrapService {
    static let shared = LicenseBootstrapService()

    private let tokenStore: LicenseTokenStoring
    private let verifier: SignedLicenseTokenVerifying

    init(tokenStore: LicenseTokenStoring = SignedLicenseTokenFileStore(),
         verifier: SignedLicenseTokenVerifying = P256SignedLicenseTokenVerifier()) {
        self.tokenStore = tokenStore
        self.verifier = verifier
    }

    @discardableResult
    func restoreEntitlement() -> Bool {
        guard let token = tokenStore.loadSignedLicenseToken() else {
            EntitlementService.shared.replaceSnapshot(.freeDefault)
            publishDiagnostic(status: "missingToken", plan: .free)
            return false
        }

        let context = SignedLicenseTokenVerificationContext(
            deviceID: LocalDeviceIdentityService.shared.deviceID(),
            bundleID: Bundle.main.bundleIdentifier,
            verificationDate: Date()
        )
        switch verifier.verify(token, context: context) {
        case .verified(let payload):
            let snapshot = payload.entitlementSnapshot(lastVerifiedAt: context.verificationDate)
            guard snapshot.isProEntitled else {
                EntitlementService.shared.replaceSnapshot(.freeDefault)
                publishDiagnostic(status: "inactive", plan: .free)
                return false
            }
            EntitlementService.shared.replaceSnapshot(snapshot)
            publishDiagnostic(status: "verified", plan: snapshot.plan)
            return true
        case .invalid:
            EntitlementService.shared.replaceSnapshot(.freeDefault)
            publishDiagnostic(status: "invalid", plan: .free)
            return false
        case .unsupported:
            EntitlementService.shared.replaceSnapshot(.freeDefault)
            publishDiagnostic(status: "unsupported", plan: .free)
            return false
        case .notConfigured:
            EntitlementService.shared.replaceSnapshot(.freeDefault)
            publishDiagnostic(status: "notConfigured", plan: .free)
            return false
        }
    }

    private func publishDiagnostic(status: String, plan: EntitlementPlan) {
        // Diagnostic only. Entitlement decisions never read these defaults.
        let defaults = UserDefaults.standard
        defaults.set(status, forKey: "BoardManDiagnosticEntitlementStatus")
        defaults.set(plan.rawValue, forKey: "BoardManDiagnosticEntitlementPlan")
        defaults.set(Date(), forKey: "BoardManDiagnosticEntitlementCheckedAt")
    }
}

final class StubSignedLicenseTokenVerifier: SignedLicenseTokenVerifying {

    enum Mode: Equatable {
        case notConfigured
        case parseOnly
    }

    private let mode: Mode

    init(mode: Mode = .notConfigured) {
        self.mode = mode
    }

    func verify(_ token: String,
                context: SignedLicenseTokenVerificationContext = SignedLicenseTokenVerificationContext()) -> SignedLicenseTokenVerificationResult {
        switch mode {
        case .notConfigured:
            return .notConfigured
        case .parseOnly:
            return parseOnlyResult(for: token, context: context)
        }
    }

    private func parseOnlyResult(for token: String,
                                 context: SignedLicenseTokenVerificationContext) -> SignedLicenseTokenVerificationResult {
        guard let parsedToken = try? SignedLicenseToken(rawValue: token) else {
            return .invalid(.malformedToken)
        }

        if parsedToken.payload.expiresAt.map({ $0 <= context.verificationDate }) == true {
            return .invalid(.tokenExpired)
        }

        if let expectedDeviceID = context.deviceID,
           let tokenDeviceID = parsedToken.payload.deviceID,
           tokenDeviceID != expectedDeviceID {
            return .invalid(.deviceMismatch)
        }

        if let expectedBundleID = context.bundleID,
           let tokenBundleID = parsedToken.payload.bundleID,
           tokenBundleID != expectedBundleID {
            return .invalid(.bundleMismatch)
        }

        return .unsupported("Signed token parsing is available, but production signature verification is not configured.")
    }
}
