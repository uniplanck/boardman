//
//  LicenseActivationClient.swift
//  Board-Man
//
//  Public client boundary for Board-Man commercial services. The MIT client
//  sends an activation request and accepts only a server-signed entitlement
//  token. Billing, account state, fraud controls, and signing keys stay on the
//  non-public service side.
//

import Foundation

struct LicenseActivationRequest: Equatable, Encodable {
    let licenseKey: String
    let localDeviceID: String?
    let bundleID: String?
    let clientVersion: String?

    init(licenseKey: String,
         localDeviceID: String? = nil,
         bundleID: String? = Bundle.main.bundleIdentifier,
         clientVersion: String? = Bundle.main.appVersion) {
        self.licenseKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.localDeviceID = localDeviceID
        self.bundleID = bundleID
        self.clientVersion = clientVersion
    }

    private enum CodingKeys: String, CodingKey {
        case licenseKey = "license_key"
        case localDeviceID = "device_id"
        case bundleID = "bundle_id"
        case clientVersion = "client_version"
    }
}

enum LicenseActivationStatus: String, Equatable {
    case activated
    case notConfigured
    case invalidInput
    case networkUnavailable
    case rejected
    case serverError
    case verificationFailed
    case storageFailed
}

struct LicenseActivationResponse: Equatable {
    let status: LicenseActivationStatus
    let message: String
    let signedToken: String?

    init(status: LicenseActivationStatus,
         message: String,
         signedToken: String? = nil) {
        self.status = status
        self.message = message
        self.signedToken = signedToken
    }
}

protocol LicenseActivationClient {
    func activate(_ request: LicenseActivationRequest) async -> LicenseActivationResponse
}

struct BoardManCommercialServiceConfiguration: Equatable {
    static let environmentKey = "BOARD_MAN_COMMERCIAL_SERVICE_BASE_URL"
    static let infoPlistKey = "BoardManCommercialServiceBaseURL"

    let baseURL: URL?

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment,
                        infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> BoardManCommercialServiceConfiguration {
        let configuredValue = environment[environmentKey]
            ?? (infoDictionary?[infoPlistKey] as? String)
        let url = configuredValue.flatMap(URL.init(string:))
        return BoardManCommercialServiceConfiguration(baseURL: url)
    }

    var activationURL: URL? {
        baseURL?.appendingPathComponent("v1/licenses/activate", isDirectory: false)
    }
}

final class URLSessionLicenseActivationClient: LicenseActivationClient {
    private let configuration: BoardManCommercialServiceConfiguration
    private let session: URLSession

    init(configuration: BoardManCommercialServiceConfiguration = .current(),
         session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func activate(_ request: LicenseActivationRequest) async -> LicenseActivationResponse {
        guard !request.licenseKey.isEmpty else {
            return LicenseActivationResponse(
                status: .invalidInput,
                message: "Enter a license key."
            )
        }
        guard let activationURL = configuration.activationURL else {
            return LicenseActivationResponse(
                status: .notConfigured,
                message: "Board-Man commercial services are not configured in this build."
            )
        }

        var urlRequest = URLRequest(url: activationURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                return LicenseActivationResponse(
                    status: .serverError,
                    message: "The activation service returned an invalid response."
                )
            }

            let wireResponse = try? JSONDecoder().decode(LicenseActivationWireResponse.self, from: data)
            guard (200...299).contains(httpResponse.statusCode) else {
                return LicenseActivationResponse(
                    status: .rejected,
                    message: wireResponse?.message ?? "The activation service rejected this request."
                )
            }
            guard let wireResponse else {
                return LicenseActivationResponse(
                    status: .serverError,
                    message: "The activation service returned malformed JSON."
                )
            }

            return LicenseActivationResponse(
                status: LicenseActivationStatus(rawValue: wireResponse.status) ?? .serverError,
                message: wireResponse.message ?? "Activation response received.",
                signedToken: wireResponse.signedToken
            )
        } catch is URLError {
            return LicenseActivationResponse(
                status: .networkUnavailable,
                message: "The activation service is unreachable."
            )
        } catch {
            return LicenseActivationResponse(
                status: .serverError,
                message: "The activation request could not be created."
            )
        }
    }
}

final class LicenseActivationCoordinator {
    private let client: LicenseActivationClient
    private let verifier: SignedLicenseTokenVerifying
    private let tokenStore: LicenseTokenStoring
    private let entitlementService: EntitlementService
    private let deviceIdentity: LocalDeviceIdentityService

    init(client: LicenseActivationClient = URLSessionLicenseActivationClient(),
         verifier: SignedLicenseTokenVerifying = P256SignedLicenseTokenVerifier(),
         tokenStore: LicenseTokenStoring = SignedLicenseTokenFileStore(),
         entitlementService: EntitlementService = .shared,
         deviceIdentity: LocalDeviceIdentityService = .shared) {
        self.client = client
        self.verifier = verifier
        self.tokenStore = tokenStore
        self.entitlementService = entitlementService
        self.deviceIdentity = deviceIdentity
    }

    func activate(licenseKey: String) async -> LicenseActivationResponse {
        let deviceID = deviceIdentity.deviceID()
        let request = LicenseActivationRequest(
            licenseKey: licenseKey,
            localDeviceID: deviceID
        )
        let response = await client.activate(request)
        guard response.status == .activated,
              let rawToken = response.signedToken else {
            return response
        }

        let context = SignedLicenseTokenVerificationContext(
            deviceID: deviceID,
            bundleID: request.bundleID,
            verificationDate: Date()
        )
        guard case .verified(let payload) = verifier.verify(rawToken, context: context),
              let parsedToken = try? SignedLicenseToken(rawValue: rawToken) else {
            return LicenseActivationResponse(
                status: .verificationFailed,
                message: "The activation service returned a token that Board-Man could not verify."
            )
        }

        do {
            try tokenStore.storeVerifiedSignedLicenseToken(parsedToken)
        } catch {
            return LicenseActivationResponse(
                status: .storageFailed,
                message: "The verified license could not be stored locally."
            )
        }

        entitlementService.replaceSnapshot(
            payload.entitlementSnapshot(lastVerifiedAt: Date())
        )
        return response
    }
}

final class StubLicenseActivationClient: LicenseActivationClient {
    func activate(_ request: LicenseActivationRequest) async -> LicenseActivationResponse {
        guard !request.licenseKey.isEmpty else {
            return LicenseActivationResponse(
                status: .invalidInput,
                message: "Enter a license key."
            )
        }
        return LicenseActivationResponse(
            status: .notConfigured,
            message: "Commercial services are intentionally not bundled into the MIT client."
        )
    }
}

private struct LicenseActivationWireResponse: Decodable {
    let status: String
    let message: String?
    let signedToken: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case message
        case signedToken = "signed_token"
    }
}
