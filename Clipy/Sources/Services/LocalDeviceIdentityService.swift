//
//  LocalDeviceIdentityService.swift
//
//  Clipy
//

import Foundation

final class LocalDeviceIdentityService {

    static let shared = LocalDeviceIdentityService()

    private let lock = NSRecursiveLock(name: "com.uniplanck.BoardMan.LocalDeviceIdentityService")
    private let fileURL: URL
    private var cachedDeviceID: String?

    init(fileURL: URL = BoardManLocalStatePaths.deviceIDURL) {
        self.fileURL = fileURL
    }

    func deviceID() -> String {
        lock.lock(); defer { lock.unlock() }

        if let cachedDeviceID {
            return cachedDeviceID
        }

        if let existingDeviceID = readDeviceID() {
            cachedDeviceID = existingDeviceID
            return existingDeviceID
        }

        let newDeviceID = UUID().uuidString
        if storeDeviceID(newDeviceID) {
            cachedDeviceID = newDeviceID
            return newDeviceID
        }

        cachedDeviceID = newDeviceID
        return newDeviceID
    }

    private func readDeviceID() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let value = String(data: data, encoding: .utf8),
              UUID(uuidString: value) != nil else {
            return nil
        }
        return value
    }

    private func storeDeviceID(_ deviceID: String) -> Bool {
        guard let data = deviceID.data(using: .utf8) else {
            return false
        }
        do {
            try BoardManLocalStatePaths.writePrivateData(data, to: fileURL)
            return true
        } catch {
            return false
        }
    }
}
