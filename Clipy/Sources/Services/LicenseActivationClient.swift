//
//  LicenseActivationClient.swift
//
//  Clipy
//

import Foundation

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

        return LicenseActivationResponse(
            status: .notConfigured,
            message: "Activation requires future signed token verification and is not enabled in this build."
        )
    }
}
