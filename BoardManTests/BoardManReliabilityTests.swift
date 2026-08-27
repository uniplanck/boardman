import AppKit
import Foundation
import Testing
@testable import Board_Man

@Suite
struct BoardManReliabilityTests {
    @Test
    func sqliteIntegrityAndBackupRoundTripStayHealthy() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("source.sqlite")
        let backupURL = root.appendingPathComponent("backup/BoardMan.sqlite")
        let restoreURL = root.appendingPathComponent("restore/BoardMan.sqlite")
        let store = try SQLiteBoardManStore(fileURL: sourceURL)

        #expect(try store.integrityReport().isHealthy)
        try store.createBackup(at: backupURL)
        let restored = try SQLiteBoardManStore.restoreBackup(from: backupURL, to: restoreURL)
        #expect(try restored.integrityReport().isHealthy)
    }

    @Test
    func malformedSQLiteBackupFailsClosed() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let backupURL = root.appendingPathComponent("malformed.sqlite")
        let destinationURL = root.appendingPathComponent("restore.sqlite")
        try Data("not-a-sqlite-database".utf8).write(to: backupURL)

        var didThrow = false
        do {
            _ = try SQLiteBoardManStore.restoreBackup(from: backupURL, to: destinationURL)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
        #expect(!FileManager.default.fileExists(atPath: destinationURL.path))
    }

    @Test
    func payloadGarbageCollectorDeletesOnlyUnreferencedPayloads() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let liveURL = root.appendingPathComponent("live.data")
        let orphanURL = root.appendingPathComponent("orphan.data")
        let databaseURL = root.appendingPathComponent("BoardMan.sqlite")
        let nestedDirectory = root.appendingPathComponent("Nested", isDirectory: true)
        let nestedPayload = nestedDirectory.appendingPathComponent("nested.data")
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try Data("live".utf8).write(to: liveURL)
        try Data("orphan".utf8).write(to: orphanURL)
        try Data("db".utf8).write(to: databaseURL)
        try Data("nested".utf8).write(to: nestedPayload)

        let orphanURLs = BoardManPayloadGarbageCollector.orphanPayloadURLs(
            in: root,
            liveDataPaths: [liveURL.path]
        )
        #expect(orphanURLs.map(\.lastPathComponent) == ["orphan.data"])
        #expect(BoardManPayloadGarbageCollector.collect(in: root, liveDataPaths: [liveURL.path]) == 1)
        #expect(FileManager.default.fileExists(atPath: liveURL.path))
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
        #expect(FileManager.default.fileExists(atPath: nestedPayload.path))
    }

    @Test
    func payloadArchiveWriteIsAtomicAndRoundTrips() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let payloadURL = root.appendingPathComponent("payload.data")
        let payload = BoardManClipData(string: "reliability payload")

        #expect(BoardManRuntimeSupport.archiveRootObjectAtomically(payload, to: payloadURL.path))
        let restored = try #require(
            NSKeyedUnarchiver.unarchiveObject(withFile: payloadURL.path) as? BoardManClipData
        )
        #expect(restored.stringValue == "reliability payload")
    }

    @Test
    func diagnosticMessagesRedactHomePathsAndStayBounded() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let raw = "failure path=\(home)/Library/Application Support/Board-Man/private.data\n"
            + String(repeating: "x", count: 2_000)
        let redacted = BoardManRuntimeSupport.redactedDiagnosticMessage(raw)

        #expect(!redacted.contains(home))
        #expect(redacted.contains("~/Library/Application Support/Board-Man/private.data"))
        #expect(!redacted.contains("\n"))
        #expect(redacted.count <= 1_024)
    }

    @Test
    func versionedRecoveryArchiveRoundTripsDatabasePayloadsAndTemplates() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteBoardManStore(fileURL: root.appendingPathComponent("source.sqlite"))
        let payloadURL = root.appendingPathComponent("source-payload.data")
        let payload = BoardManClipData(string: "archive payload")
        #expect(BoardManRuntimeSupport.archiveRootObjectAtomically(payload, to: payloadURL.path))

        let clip = makeClip(identifier: "archive-history", title: "Archive History", dataPath: payloadURL.path)
        store.upsertClip(clip, searchMetadata: .make(from: payload))
        let folder = BoardManFolder()
        folder.identifier = "archive-folder"
        folder.index = 0
        folder.title = "Recovery"
        store.upsertFolder(folder)
        let snippet = BoardManSnippet()
        snippet.identifier = "archive-snippet"
        snippet.index = 0
        snippet.title = "Recovered snippet"
        snippet.content = "template body"
        store.upsertSnippet(snippet, folderIdentifier: folder.identifier)

        let archiveURL = root.appendingPathComponent("BoardMan.boardman-recovery", isDirectory: true)
        let restoredRootURL = root.appendingPathComponent("Restored", isDirectory: true)
        try BoardManRecoveryArchiveService.createArchive(from: store, at: archiveURL)
        let restored = try BoardManRecoveryArchiveService.restoreArchive(
            from: archiveURL,
            to: restoredRootURL
        )

        let restoredClip = try #require(restored.clip(identifier: clip.dataHash))
        #expect(restoredClip.dataPath.hasPrefix(restoredRootURL.path))
        let restoredData = try Data(contentsOf: URL(fileURLWithPath: restoredClip.dataPath))
        let decoded = try #require(NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(restoredData) as? BoardManClipData)
        #expect(decoded.stringValue == "archive payload")
        #expect(restored.folder(identifier: folder.identifier)?.title == "Recovery")
        #expect(restored.snippet(identifier: snippet.identifier)?.content == "template body")
        #expect(restored.folderIdentifier(forSnippetIdentifier: snippet.identifier) == folder.identifier)
        #expect(try restored.integrityReport().isHealthy)
    }

    @Test
    func recoveryArchiveRejectsTamperedPayloadWithoutCreatingDestination() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteBoardManStore(fileURL: root.appendingPathComponent("source.sqlite"))
        let payloadURL = root.appendingPathComponent("payload.data")
        let payload = BoardManClipData(string: "untampered")
        #expect(BoardManRuntimeSupport.archiveRootObjectAtomically(payload, to: payloadURL.path))
        store.upsertClip(
            makeClip(identifier: "tamper-history", title: "Tamper", dataPath: payloadURL.path),
            searchMetadata: .make(from: payload)
        )

        let archiveURL = root.appendingPathComponent("Archive", isDirectory: true)
        try BoardManRecoveryArchiveService.createArchive(from: store, at: archiveURL)
        let manifestData = try Data(contentsOf: archiveURL.appendingPathComponent("manifest.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(BoardManRecoveryArchiveManifest.self, from: manifestData)
        let relativePath = try #require(manifest.payloads.first?.relativePath)
        try Data("tampered".utf8).write(
            to: archiveURL.appendingPathComponent("Payloads").appendingPathComponent(relativePath)
        )

        let restoredRootURL = root.appendingPathComponent("Restored", isDirectory: true)
        var rejected = false
        do {
            _ = try BoardManRecoveryArchiveService.restoreArchive(from: archiveURL, to: restoredRootURL)
        } catch BoardManRecoveryArchiveError.payloadSizeMismatch(_) {
            rejected = true
        } catch BoardManRecoveryArchiveError.payloadDigestMismatch(_) {
            rejected = true
        }
        #expect(rejected)
        #expect(!FileManager.default.fileExists(atPath: restoredRootURL.path))
    }

    @Test
    func payloadRecoveryRebuildsMissingTextPayloadAndUpdatesStore() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteBoardManStore(fileURL: root.appendingPathComponent("source.sqlite"))
        let missingURL = root.appendingPathComponent("missing.data")
        let recoveryDirectory = root.appendingPathComponent("RecoveredPayloads", isDirectory: true)
        let clip = makeClip(
            identifier: "recoverable-text",
            title: "metadata fallback text",
            dataPath: missingURL.path
        )
        store.upsertClip(clip)

        let result = BoardManPayloadRecoveryService.rebuildRecoverableTextPayload(
            snapshot: BoardManClipSnapshot(clip),
            store: store,
            directoryURL: recoveryDirectory
        )

        #expect(result.repaired)
        let recoveredPath = try #require(result.dataPath)
        #expect(FileManager.default.fileExists(atPath: recoveredPath))
        #expect(store.clip(identifier: clip.dataHash)?.dataPath == recoveredPath)
        let recoveredData = try Data(contentsOf: URL(fileURLWithPath: recoveredPath))
        let payload = try #require(
            NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(recoveredData) as? BoardManClipData
        )
        #expect(payload.stringValue == "metadata fallback text")
    }

    @Test
    func payloadRecoveryPreservesReadablePayloadAndRejectsNonTextMetadata() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteBoardManStore(fileURL: root.appendingPathComponent("source.sqlite"))
        let payloadURL = root.appendingPathComponent("existing.data")
        #expect(BoardManRuntimeSupport.archiveRootObjectAtomically(
            BoardManClipData(string: "authoritative payload"),
            to: payloadURL.path
        ))
        let textClip = makeClip(
            identifier: "existing-text",
            title: "metadata should not overwrite",
            dataPath: payloadURL.path
        )
        store.upsertClip(textClip)

        let preserved = BoardManPayloadRecoveryService.rebuildRecoverableTextPayload(
            snapshot: BoardManClipSnapshot(textClip),
            store: store,
            directoryURL: root.appendingPathComponent("RecoveredText", isDirectory: true)
        )
        #expect(!preserved.repaired)
        #expect(preserved.dataPath == payloadURL.path)
        #expect(store.clip(identifier: textClip.dataHash)?.dataPath == payloadURL.path)

        let imageClip = makeClip(
            identifier: "missing-image",
            title: "Image",
            dataPath: root.appendingPathComponent("missing-image.data").path
        )
        imageClip.primaryType = NSPasteboard.PasteboardType.png.rawValue
        store.upsertClip(imageClip)
        let rejected = BoardManPayloadRecoveryService.rebuildRecoverableTextPayload(
            snapshot: BoardManClipSnapshot(imageClip),
            store: store,
            directoryURL: root.appendingPathComponent("RecoveredImage", isDirectory: true)
        )
        #expect(!rejected.repaired)
        #expect(rejected.dataPath == nil)
        #expect(store.clip(identifier: imageClip.dataHash)?.dataPath == imageClip.dataPath)
    }

    @Test
    func thumbnailRecoveryRebuildsImageFromArchivedPayload() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = AppEnvironment.current.defaults
        let oldWidth = defaults.integer(forKey: Constants.UserDefaults.thumbnailWidth)
        let oldHeight = defaults.integer(forKey: Constants.UserDefaults.thumbnailHeight)
        defer {
            defaults.set(oldWidth, forKey: Constants.UserDefaults.thumbnailWidth)
            defaults.set(oldHeight, forKey: Constants.UserDefaults.thumbnailHeight)
        }
        defaults.set(64, forKey: Constants.UserDefaults.thumbnailWidth)
        defaults.set(64, forKey: Constants.UserDefaults.thumbnailHeight)

        let payloadURL = root.appendingPathComponent("image.data")
        let sourceImage = NSImage(size: NSSize(width: 80, height: 40))
        sourceImage.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 80, height: 40)).fill()
        sourceImage.unlockFocus()
        let payload = BoardManClipData(image: sourceImage)
        #expect(BoardManRuntimeSupport.archiveRootObjectAtomically(payload, to: payloadURL.path))

        let clip = makeClip(identifier: "recoverable-image", title: "Image", dataPath: payloadURL.path)
        clip.primaryType = NSPasteboard.PasteboardType.tiff.rawValue
        clip.thumbnailPath = "missing-thumbnail-cache-key"
        let recovered = try #require(
            BoardManThumbnailRecoveryService.recoverableImage(for: BoardManClipSnapshot(clip))
        )

        #expect(recovered.size.width > 0)
        #expect(recovered.size.height > 0)
        #expect(recovered.size.width <= 64)
        #expect(recovered.size.height <= 64)
    }

    @Test
    func pasteReliabilityProfilesCoverMajorTargetFamilies() {
        struct TargetCase {
            let bundleIdentifier: String?
            let family: BoardManPasteTargetFamily
            let settleDelay: TimeInterval
        }
        let cases = [
            TargetCase(bundleIdentifier: "com.google.Chrome", family: .chromium, settleDelay: 0.24),
            TargetCase(bundleIdentifier: "com.tinyspeck.slackmacgap", family: .electron, settleDelay: 0.24),
            TargetCase(bundleIdentifier: "org.mozilla.firefox", family: .firefox, settleDelay: 0.12),
            TargetCase(bundleIdentifier: "com.apple.Safari", family: .safari, settleDelay: 0.08),
            TargetCase(bundleIdentifier: "com.apple.Terminal", family: .terminal, settleDelay: 0.08),
            TargetCase(bundleIdentifier: "com.apple.TextEdit", family: .nativeOrUnknown, settleDelay: 0.08),
            TargetCase(bundleIdentifier: nil, family: .nativeOrUnknown, settleDelay: 0.08)
        ]

        for target in cases {
            let profile = BoardManPasteReliabilityPolicy.profile(bundleIdentifier: target.bundleIdentifier)
            #expect(profile.family == target.family)
            #expect(profile.settleDelay == target.settleDelay)
            #expect(profile.activationRetryDelay == 0.03)
            #expect(profile.maximumActivationAttempts == 12)
        }
    }

    private func makeClip(identifier: String, title: String, dataPath: String) -> BoardManClip {
        let clip = BoardManClip()
        clip.dataHash = identifier
        clip.title = title
        clip.dataPath = dataPath
        clip.primaryType = NSPasteboard.PasteboardType.string.rawValue
        clip.createdTime = 1
        clip.updateTime = 1
        return clip
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManReliabilityTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
