//
//  LicenseTokenVerifier.swift
//
//  Clipy
//

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
