//
//  BoardManPayloadRecovery.swift
//  Board-Man
//
//  Bounded repair for text history whose archived payload is missing or unreadable.
//

import AppKit
import CryptoKit
import Foundation
import PINCache

struct BoardManPayloadRecoveryResult: Sendable, Equatable {
    let repaired: Bool
    let dataPath: String?
}

enum BoardManPayloadRecoveryService {
    static func rebuildRecoverableTextPayload(
        snapshot: BoardManClipSnapshot,
        store: BoardManStore,
        directoryURL: URL = URL(
            fileURLWithPath: BoardManRuntimeSupport.applicationSupportFolder(),
            isDirectory: true
        ),
        fileManager: FileManager = .default
    ) -> BoardManPayloadRecoveryResult {
        if payloadIsReadable(at: snapshot.dataPath, fileManager: fileManager) {
            return BoardManPayloadRecoveryResult(repaired: false, dataPath: snapshot.dataPath)
        }

        let clip = snapshot.makeClip()
        guard let text = clip.boardManRecoverableText else {
            return BoardManPayloadRecoveryResult(repaired: false, dataPath: nil)
        }
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let fileURL = directoryURL.appendingPathComponent(recoveryFileName(identifier: clip.dataHash))
            let payload = BoardManClipData(string: text)
            guard BoardManRuntimeSupport.archiveRootObjectAtomically(payload, to: fileURL.path) else {
                return BoardManPayloadRecoveryResult(repaired: false, dataPath: nil)
            }
            clip.dataPath = fileURL.path
            store.upsertClip(clip, searchMetadata: .make(from: payload))
            return BoardManPayloadRecoveryResult(repaired: true, dataPath: fileURL.path)
        } catch {
            BoardManRuntimeSupport.sendDiagnosticLog(
                "Recoverable text payload rebuild failed: \(error.localizedDescription)"
            )
            return BoardManPayloadRecoveryResult(repaired: false, dataPath: nil)
        }
    }

    private static func payloadIsReadable(at path: String, fileManager: FileManager) -> Bool {
        guard !path.isEmpty, fileManager.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let payload = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? BoardManClipData else {
            return false
        }
        return payload != nil
    }

    private static func recoveryFileName(identifier: String) -> String {
        let digest = SHA256.hash(data: Data(identifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "recovered-\(digest).data"
    }
}

enum BoardManThumbnailRecoveryService {
    private static let recoveryQueue = DispatchQueue(
        label: "com.uniplanck.BoardMan.ThumbnailRecovery",
        qos: .utility
    )

    static func cachedImage(
        for snapshot: BoardManClipSnapshot,
        completion: ((NSImage?) -> Void)? = nil
    ) -> NSImage? {
        guard !snapshot.thumbnailPath.isEmpty else { return nil }
        if let image = PINCache.shared.object(forKey: snapshot.thumbnailPath) as? NSImage {
            return image
        }

        recoveryQueue.async {
            let image = recoverableImage(for: snapshot)
            if let image {
                PINCache.shared.setObjectAsync(image, forKey: snapshot.thumbnailPath, completion: nil)
            }
            guard let completion else { return }
            DispatchQueue.main.async {
                completion(image)
            }
        }
        return nil
    }

    static func recoverableImage(
        for snapshot: BoardManClipSnapshot,
        fileManager: FileManager = .default
    ) -> NSImage? {
        guard !snapshot.dataPath.isEmpty,
              fileManager.fileExists(atPath: snapshot.dataPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: snapshot.dataPath)),
              let decoded = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data),
              let payload = decoded as? BoardManClipData else {
            return nil
        }
        return snapshot.isColorCode ? payload.colorCodeImage : payload.thumbnailImage
    }
}
